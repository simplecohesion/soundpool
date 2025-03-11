/// @nodoc
// ignore_for_file: unused_element, unused_element_parameter

library soundpool_web;

import 'dart:async';
import 'dart:js_interop';
// ignore: uri_does_not_exist
import 'package:web/web.dart';
import 'dart:typed_data';
import 'dart:core';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:http/http.dart' as http;
import 'package:soundpool_platform_interface/soundpool_platform_interface.dart';

/// @nodoc

class SoundpoolPlugin extends SoundpoolPlatform {
  static void registerWith(Registrar registrar) {
    SoundpoolPlatform.instance = new SoundpoolPlugin();
  }

  final Map<int, _AudioContextWrapper> _pool = {};

  void _checkSupported() {
    // final supported = AudioContext.supported;
    // if (!supported) {
    //   throw UnsupportedError(
    //       'Required AudioContext API is not supported by this browser.');
    // }
  }

  @override
  Future<int> init(
      int streamType, int maxStreams, Map<String, dynamic> options) async {
    _checkSupported();
    // stream type and streams limit are not supported
    var wrapperIndex = _pool.length + 1;
    _pool[wrapperIndex] = _AudioContextWrapper();
    return wrapperIndex;
  }

  @override
  Future<int> loadUint8List(
      int poolId, Uint8List rawSound, int priority) async {
    Uint8List rawSoundCopy = Uint8List.fromList(rawSound);
    int id = poolId;
    _AudioContextWrapper wrapper = _pool[id]!;
    return await wrapper.load(rawSoundCopy.buffer);
  }

  @override
  Future<int> loadUri(int poolId, String uri, int priority) async {
    _AudioContextWrapper wrapper = _pool[poolId]!;
    return await wrapper.loadUri(uri);
  }

  @override
  Future<void> dispose(int poolId) async {
    _AudioContextWrapper wrapper = _pool.remove(poolId)!;
    await wrapper.dispose();
  }

  @override
  Future<void> release(int poolId) async {
    _AudioContextWrapper wrapper = _pool[poolId]!;
    await wrapper.release();
  }

  @override
  Future<int> play(int poolId, int soundId, int repeat, double rate) async {
    _AudioContextWrapper wrapper = _pool[poolId]!;
    return await wrapper.play(soundId, rate: rate, repeat: repeat);
  }

  @override
  Future<void> stop(int poolId, int streamId) async {
    _AudioContextWrapper wrapper = _pool[poolId]!;
    return await wrapper.stop(streamId);
  }

  @override
  Future<void> setVolume(int poolId, int? soundId, int? streamId,
      double? volumeLeft, double? volumeRight) async {
    _AudioContextWrapper wrapper = _pool[poolId]!;
    if (streamId == null) {
      await wrapper.setVolume(soundId!, volumeLeft, volumeRight);
    } else {
      await wrapper.setStreamVolume(streamId, volumeLeft, volumeRight);
    }
  }

  @override
  Future<void> setRate(int poolId, int streamId,
      [double playbackRate = 1.0]) async {
    _AudioContextWrapper wrapper = _pool[poolId]!;
    wrapper.setStreamRate(streamId, playbackRate);
  }

  @override
  Future<void> pause(int poolId, int streamId) => stop(poolId, streamId);
}

class _AudioContextWrapper {
  late AudioContext audioContext;
  void _initContext() {
    audioContext = AudioContext();
  }

  Map<int, _CachedAudioSettings> _cache = {};
  Map<int, _PlayingAudioWrapper> _playedAudioCache = {};
  int _lastPlayedStreamId = 0;

  Future<int> load(ByteBuffer buffer) async {
    _initContext();
    AudioBuffer audioBuffer =
        await audioContext.decodeAudioData(buffer.toJS).toDart;
    int currentSize = _cache.length;
    _cache[currentSize + 1] = _CachedAudioSettings(buffer: audioBuffer);
    return currentSize + 1;
  }

  Future<int> loadUri(String uri) async {
    var response = await http.get(Uri.parse(uri));
    Uint8List buffer = response.bodyBytes;
    return await load(buffer.buffer);
  }

  Future<int> play(int soundId, {double rate = 1.0, int repeat = 0}) async {
    _CachedAudioSettings cachedAudio = _cache[soundId]!;
    AudioBuffer audioBuffer = cachedAudio.buffer;
    var playbackRate = rate;

    var sampleSource = audioContext.createBufferSource();
    sampleSource.buffer = audioBuffer;
    // updating playback rate
    sampleSource.playbackRate.value = playbackRate;
    // gain node for setting volume level
    var gainNode = audioContext.createGain();
    gainNode.gain.value = cachedAudio.volumeLeft;

    sampleSource.connect(gainNode);
    final destination = audioContext.destination;
    gainNode.connect(destination);
    _lastPlayedStreamId = _lastPlayedStreamId + 1;
    var streamId = _lastPlayedStreamId;
    var subscription = sampleSource.onEnded.listen((_) {
      var audioWrapper = _playedAudioCache.remove(streamId);
      audioWrapper?.subscription?.cancel();
    });
    _playedAudioCache[streamId] = _PlayingAudioWrapper(
      sourceNode: sampleSource,
      gainNode: gainNode,
      subscription: subscription,
      soundId: soundId,
    );
    // repeat setup: loop sound when repeat is a non-zero value, -1 means infinite loop, positive number means number of extra repeats
    sampleSource.loop = repeat != 0;

    sampleSource.start();

    if (repeat > 0) {
      sampleSource.stop(
          (audioContext.currentTime) + (audioBuffer.duration) * (repeat + 1));
    }
    return streamId;
  }

  Future<void> stop(int streamId) async {
    _PlayingAudioWrapper? audioWrapper = _playedAudioCache.remove(streamId);
    audioWrapper?.subscription?.cancel();
    audioWrapper?.sourceNode.stop();
  }

  Future<void> setVolume(
      int soundId, double? volumeLeft, double? volumeRight) async {
    _CachedAudioSettings? cachedAudio = _cache[soundId];
    if (volumeLeft != null) cachedAudio?.volumeLeft = volumeLeft;
    if (volumeRight != null) cachedAudio?.volumeRight = volumeRight;
    _playedAudioCache.values
        .where((pw) => pw.soundId == soundId)
        .forEach((playingWrapper) {
      if (volumeRight != null)
        playingWrapper.gainNode.gain.value = volumeLeft! as num;
    });
  }

  Future<void> setStreamVolume(
      int streamId, double? volumeLeft, double? volumeRight) async {
    _PlayingAudioWrapper? playingWrapper = _playedAudioCache[streamId];
    if (playingWrapper != null) {
      playingWrapper.gainNode.gain.value = volumeLeft as num;
      _CachedAudioSettings? cachedAudio = _cache[playingWrapper.soundId];
      if (volumeLeft != null) cachedAudio?.volumeLeft = volumeLeft;
      if (volumeRight != null) cachedAudio?.volumeRight = volumeRight;
    }
  }

  Future<void> setStreamRate(int streamId, double rate) async {
    _PlayingAudioWrapper? playingWrapper = _playedAudioCache[streamId];
    if (playingWrapper != null) {
      playingWrapper.sourceNode.playbackRate.value = rate;
    }
  }

  Future<void> release() async {
    _cache.clear();
  }

  Future<void> dispose() async {
    await release();
    audioContext.close();
  }
}

class _CachedAudioSettings {
  final AudioBuffer buffer;
  double volumeLeft;
  double volumeRight;
  _CachedAudioSettings({
    required this.buffer,
    this.volumeLeft = 1.0,
    this.volumeRight = 1.0,
  });
}

class _PlayingAudioWrapper {
  final AudioBufferSourceNode sourceNode;
  final GainNode gainNode;
  final StreamSubscription? subscription;
  final int soundId;
  const _PlayingAudioWrapper(
      {required this.sourceNode,
      required this.gainNode,
      this.subscription,
      required this.soundId});
}
