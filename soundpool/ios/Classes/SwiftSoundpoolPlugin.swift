import Foundation
import Flutter
import UIKit
import AVFoundation

public class SwiftSoundpoolPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "pl.ukaszapps/soundpool", binaryMessenger: registrar.messenger())
        let instance = SwiftSoundpoolPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    private let counter = Atomic<Int>(0)
    
    private lazy var wrappers = Dictionary<Int,SwiftSoundpoolPlugin.SoundpoolWrapper>()
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initSoundpool":
            // TODO create distinction between different types of audio playback
            let attributes = call.arguments as! NSDictionary
            
            initAudioSession(attributes)
            
            let wrapper = SoundpoolWrapper()
            let index = counter.increment()
            wrappers[index] = wrapper;
            result(index)
        case "dispose":
            let attributes = call.arguments as! NSDictionary
            let index = attributes["poolId"] as! Int
            
            guard let wrapper = wrapperById(id: index) else {
                print("Dispose attempt on not available pool (id: \(index)).")
                result(FlutterError( code: "invalidArgs",
                                     message: "Invalid poolId",
                                     details: "Pool with id \(index) not found" ))
                break
            }
            wrapper.stopAllStreams()
            wrappers.removeValue(forKey: index)
            result(nil)
        default:
            let attributes = call.arguments as! NSDictionary
            let index = attributes["poolId"] as! Int
            
            guard let wrapper = wrapperById(id: index) else {
                print("Action '\(call.method)' attempt on not available pool (id: \(index)).")
                result(FlutterError( code: "invalidArgs",
                                     message: "Invalid poolId",
                                     details: "Pool with id \(index) not found" ))
                break
            }
            wrapper.handle(call, result: result)
        }
    }
    
    private func initAudioSession(_ attributes: NSDictionary) {
        if #available(iOS 10.0, *) {
            // guard against audio_session plugin and avoid doing redundant session management
            if (NSClassFromString("AudioSessionPlugin") != nil) {
                print("AudioSession should be managed by 'audio_session' plugin")
                return
            }
            
            
            guard let categoryAttr = attributes["ios_avSessionCategory"] as? String else {
                return
            }
            let modeAttr = attributes["ios_avSessionMode"] as! String
            
            let category: AVAudioSession.Category
            switch categoryAttr {
            case "ambient":
                category = .ambient
            case "playback":
                category = .playback
            case "playAndRecord":
                category = .playAndRecord
            case "multiRoute":
                category = .multiRoute
            default:
                category = .soloAmbient
                
            }
            let mode: AVAudioSession.Mode
            switch modeAttr {
            case "moviePlayback":
                mode = .moviePlayback
            case "videoRecording":
                mode = .videoRecording
            case "voiceChat":
                mode = .voiceChat
            case "gameChat":
                mode = .gameChat
            case "videoChat":
                mode = .videoChat
            case "spokenAudio":
                mode = .spokenAudio
            case "measurement":
                mode = .measurement
            default:
                mode = .default
            }
            do {
                try AVAudioSession.sharedInstance().setCategory(category, mode: mode)
                print("Audio session updated: category = '\(category)', mode = '\(mode)'.")
            } catch (let e) {
                //do nothing
                print("Error while trying to set audio category: '\(e)'")
            }
            do {
                try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.0012)
                print("Audio session updated: preferred buffer duration")
            } catch (let e) {
                //do nothing
                print("Error while trying to set preferred buffer duration: '\(e)'")
            }
        }
    }
    
    private func wrapperById(id: Int) -> SwiftSoundpoolPlugin.SoundpoolWrapper? {
        if (id < 0){
            return nil
        }
        let wrapper = wrappers[id]
        return wrapper
    }
    
    class SoundpoolWrapper : NSObject {    

        private var starling: Starling = Starling()

        public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
            let attributes = call.arguments as! NSDictionary
            switch call.method {
            case "load":
                result(-1)
            case "loadUri":
                let soundUri = attributes["uri"] as! String
                
                guard let url = URL(string: soundUri) else {
                    result(-1)
                    return
                }

                let res = starling.load(sound: url)
                result(res)

            case "play":
                let streamId = attributes["soundId"] as! Int
                if (streamId < 0){
                    result(0)
                    return
                }
                starling.play(streamId)
                result(streamId)
            case "pause":
                let streamId = attributes["streamId"] as! Int
                starling.stop(streamId)
                result(streamId)
            case "resume":
                let streamId = attributes["streamId"] as! Int
                starling.play(streamId)
                result(streamId)
            case "stop":
                let streamId = attributes["streamId"] as! Int
                starling.stop(streamId)
                result(streamId)
            case "setVolume":
                result(-1)
            case "setRate":
                result(-1)
            case "release": // TODO this should distinguish between soundpools for different types of audio playbacks
                dispose()
                result(nil)
            default:
                result("notImplemented")
            }
        }

        func dispose() {
            starling.dispose()
        }
        
        func stopAllStreams() {
            starling.stopAll()
        }

    }
}

final class Atomic<T> {

    private let sema = DispatchSemaphore(value: 1)
    private var _value: T

    init (_ value: T) {
        _value = value
    }

    var value: T {
        get {
            sema.wait()
            defer {
                sema.signal()
            }
            return _value
        }
        set {
            sema.wait()
            _value = newValue
            sema.signal()
        }
    }

    func swap(_ value: T) -> T {
        sema.wait()
        let v = _value
        _value = value
        sema.signal()
        return v
    }
}

extension Atomic where T == Int {
    
    func increment() -> Int {
        return increment(n: 1)
    }

    func increment(n: Int) -> Int {
        sema.wait()
        let v = _value + n
        _value = v
        sema.signal()
        return v
    }
}