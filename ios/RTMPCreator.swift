//
//  RTMPCreator.swift
//  rtmpPackageExample
//
//  Created by Ezran Bayantemur on 15.01.2022.
//
import HaishinKit
import Foundation
import AVFoundation
import VideoToolbox

struct VideoSettingsType {
    var width: Int
    var height: Int
    var bitrate: Int
    var audioBitrate: Int
    var fps: Int
}

@MainActor
class RTMPCreator {
    public static let connection: RTMPConnection = RTMPConnection()
    public static let stream: RTMPStream = RTMPStream(connection: connection)
    public static let mixer: MediaMixer = MediaMixer()
    private static let session = AVAudioSession.sharedInstance()
    private static var _streamUrl: String = ""
    private static var _streamName: String = ""
    public static var isStreaming: Bool = false
    public static var isMuted: Bool = false
    public static var isTorchEnabled: Bool = false
    public static var isAudioAttached: Bool = false
    public static var isVideoAttached: Bool = false
    public static var videoSettings: VideoSettingsType = VideoSettingsType(
        width: 720,
        height: 1280,
        bitrate: 3000 * 1024,
        audioBitrate: 128 * 1000,
        fps: 30
    )

    public static func setStreamUrl(url: String){
        _streamUrl = url
    }

    public static func setStreamName(name: String){
        _streamName = name
    }

    public static func getPublishURL() -> String {
        return "\(_streamUrl)/\(_streamName)"
    }

    public static func startPublish(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        Task {
            do {
                // Configure the encoder from the stored settings BEFORE
                // publishing. The stream is never mutated while idle, so this
                // is the single point where each session's encoder state is
                // established — every publish starts deterministic.
                await applyVideoSettingsToStream()
                _ = try await connection.connect(_streamUrl)
                _ = try await stream.publish(_streamName)
                isStreaming = true
                await applyBitrateStrategy()
                resolve(nil)
            } catch {
                NSLog("RTMPCreator: publish failed: %@", error.localizedDescription)
                reject("STREAM_ERROR", "Failed to start stream: \(error.localizedDescription)", error)
            }
        }
    }

    /// Installs HaishinKit's built-in adaptive bitrate strategy. The current
    /// `videoSettings.bitrate` is the ceiling; HaishinKit's NetworkMonitor
    /// (driven by RTMPConnection) adapts downward under congestion and climbs
    /// back toward the ceiling when bandwidth recovers. Re-installed whenever
    /// the ceiling changes so the maximum tracks the requested video settings.
    private static func applyBitrateStrategy() async {
        let strategy = HKStreamVideoAdaptiveBitRateStrategy(
            mamimumVideoBitrate: videoSettings.bitrate
        )
        await stream.setBitrateStorategy(strategy)
    }

    /// Records the desired video settings without touching the stream. Used by
    /// the idle path (a quality change made while not streaming). The encoder
    /// is configured later, from these stored values, inside `startPublish`.
    public static func storeVideoSettings(_ newVideoSettings: VideoSettingsType) {
        videoSettings = newVideoSettings
    }

    /// Applies the currently stored `videoSettings` to the stream's encoder.
    /// Called by `startPublish` (always, before publishing) and by the
    /// live-streaming path when settings change mid-stream.
    private static func applyVideoSettingsToStream() async {
        await mixer.setFrameRate(Float64(videoSettings.fps))

        await stream.setVideoSettings(VideoCodecSettings(
            videoSize: CGSize(width: videoSettings.width, height: videoSettings.height),
            bitRate: videoSettings.bitrate,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            scalingMode: .cropSourceToCleanAperture
        ))

        await stream.setAudioSettings(AudioCodecSettings(
            bitRate: videoSettings.audioBitrate
        ))
    }

    /// Stores new video settings and, if a stream is currently active, applies
    /// them to the live encoder and re-syncs the adaptive-bitrate ceiling.
    /// While idle this only stores — the stream must not be mutated between
    /// sessions, or the next publish is rejected by the RTMP server.
    public static func setVideoSettings(_ newVideoSettings: VideoSettingsType) {
        storeVideoSettings(newVideoSettings)
        guard isStreaming else { return }
        Task {
            // Re-check after the async hop — the stream may have stopped
            // between the guard above and this Task body executing.
            guard isStreaming else { return }
            await applyVideoSettingsToStream()
            await applyBitrateStrategy()
        }
    }

    public static func stopPublish(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        Task {
            do {
                _ = try await stream.close()
                try await connection.close()
            } catch {
                NSLog("RTMPCreator: stop failed: %@", error.localizedDescription)
            }
            isStreaming = false
            resolve(nil)
        }
    }

    public static func stopPublish(){
        Task {
            do {
                _ = try await stream.close()
                try await connection.close()
            } catch {
                NSLog("RTMPCreator: stop failed: %@", error.localizedDescription)
            }
            isStreaming = false
        }
    }

    public static func setAudioInput(audioInput: Int){
        switch audioInput {
        case 0:
            switchToBluetooth()
        case 1:
            switchToSpeaker()
        case 2:
            switchToHeadset()
        default:
            return
        }
    }

    private static func switchToSpeaker(){
        guard let inputs = session.availableInputs, !inputs.isEmpty else {
            NSLog("RTMPCreator: No available audio inputs for speaker switch.")
            return
        }

        if let selectedDesc = inputs.first(where: { (desc) -> Bool in
            return desc.portType == AVAudioSession.Port.builtInMic
        }){
            do{
                let selectedDataSource = selectedDesc.dataSources?.first(where: { (source) -> Bool in
                    return source.orientation == AVAudioSession.Orientation.front
                })

                try session.setPreferredInput(selectedDesc)
                try session.setInputDataSource(selectedDataSource)
            } catch let error{
                print(error)
            }
        }
    }

    private static func switchToHeadset(){
        guard let inputs = session.availableInputs, !inputs.isEmpty else {
            NSLog("RTMPCreator: No available audio inputs for headset switch.")
            return
        }

        if let selectedDesc = inputs.first(where: { (desc) -> Bool in
            return desc.portType == AVAudioSession.Port.headsetMic
        }){
            do{
                try session.setPreferredInput(selectedDesc)
            } catch let error{
                print(error)
            }
        }
    }

    private static func switchToBluetooth(){
        guard let inputs = session.availableInputs, !inputs.isEmpty else {
            NSLog("RTMPCreator: No available audio inputs for bluetooth switch.")
            return
        }

        if let selectedDesc = inputs.first(where: { (desc) -> Bool in
            return desc.portType == AVAudioSession.Port.bluetoothHFP
        }){
            do{
                try session.setPreferredInput(selectedDesc)
            } catch let error{
                print(error)
            }
        }
    }

}
