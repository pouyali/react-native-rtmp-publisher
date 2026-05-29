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
    /// Initial encoder bitrate target. The adaptive strategy can move
    /// the live encoder bitrate between `floorBps` (see strategy) and
    /// `maxBitrate` based on observed throughput.
    var bitrate: Int
    /// Absolute ceiling the adaptive strategy may step the encoder up
    /// to. Defaults to `bitrate` (no step-up) when the consumer does not
    /// explicitly opt into a higher cap; consumers that want
    /// auto-step-up beyond their starting preset should pass the
    /// highest-preset bitrate here.
    var maxBitrate: Int
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
    /// Last encoder bitrate the adaptive strategy settled on, written
    /// back from AdaptiveBitRateStrategy on every change. Used as the
    /// initial target when installing a new strategy on republish so
    /// the encoder doesn't redo the discovery climb from preset
    /// bitrate (e.g. 1.2 Mbps) down to whatever the network actually
    /// sustains (e.g. 200 Kbps). Reset to 0 on stopPublish so the
    /// next broadcast starts fresh.
    ///
    /// 0 = "no prior knowledge" — fall back to videoSettings.bitrate.
    public static var lastEncoderBitrateBps: Int = 0
    public static var videoSettings: VideoSettingsType = VideoSettingsType(
        width: 720,
        height: 1280,
        bitrate: 3000 * 1024,
        maxBitrate: 3000 * 1024,
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
                // Re-apply the encoder settings the app has configured before
                // every publish. HaishinKit's `RTMPStream.close()` resets the
                // outgoing.videoSettings back to its hardcoded default — so
                // after a disconnect/republish cycle, without this re-apply
                // the encoder ends up at the wrong bitrate (typically higher
                // than the app requested, which is exactly the wrong
                // direction on a bad network).
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

    /// Applies the currently-stored `videoSettings` to the live encoder.
    /// Shared between `startPublish` (every publish lifecycle, so the encoder
    /// survives close+republish with the right config) and `setVideoSettings`
    /// (when the app changes settings mid-stream or at view-attach time).
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

    /// Installs the custom throughput-driven adaptive bitrate strategy.
    /// The strategy can move the encoder bitrate between `floorBps`
    /// (100 Kbps) and `videoSettings.maxBitrate` based on observed
    /// outbound throughput.
    ///
    /// Initial target carries over from the previous publish session:
    /// if `lastEncoderBitrateBps > 0` (we have prior network knowledge),
    /// start at min(last, preset) — never above the preset's bitrate,
    /// but if the network was bad last time, don't redo the discovery
    /// climb from preset down to the actual sustainable rate.
    ///
    /// Without this carryover, every reconnect would re-attempt
    /// `videoSettings.bitrate` (e.g. 1.2 Mbps) on a network that
    /// previously demonstrated it could only sustain 200 Kbps —
    /// causing a 20-second step-down sequence and a high risk of
    /// re-disconnect during that climb.
    ///
    /// Replaces HaishinKit's HKStreamVideoAdaptiveBitRateStrategy whose
    /// queue-growth detection cannot see sharp cellular drops in time —
    /// the socket disconnects before three consecutive growing samples
    /// are observed. The custom strategy reacts to throughput directly.
    ///
    /// Floor of 100 Kbps: device data on bad-3G profiles showed network
    /// throughput frequently dipping below 200 Kbps on its worst dips,
    /// causing socket disconnects when the encoder couldn't drop low
    /// enough to match. 100 Kbps gives the encoder headroom to ride
    /// through brief deep dips. Video at this bitrate is heavily
    /// degraded but the broadcast stays alive — preferable to a
    /// disconnect for a sports broadcaster.
    private static func applyBitrateStrategy() async {
        let initialTarget: Int
        if lastEncoderBitrateBps > 0 {
            initialTarget = min(lastEncoderBitrateBps, videoSettings.bitrate)
        } else {
            initialTarget = videoSettings.bitrate
        }
        let strategy = AdaptiveBitRateStrategy(
            absoluteCeilingBps: videoSettings.maxBitrate,
            initialTargetBps: initialTarget,
            floorBps: 100_000
        )
        await stream.setBitrateStorategy(strategy)
    }

    public static func setVideoSettings(_ newVideoSettings: VideoSettingsType) {
        videoSettings = newVideoSettings
        Task {
            await applyVideoSettingsToStream()

            // Keep the adaptive-bitrate ceiling in sync with the new settings
            // while a stream is active.
            if isStreaming {
                await applyBitrateStrategy()
            }
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
            // User stopped — the next broadcast is a fresh attempt, so
            // discard learned encoder bitrate from this session.
            lastEncoderBitrateBps = 0
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
            // User stopped — the next broadcast is a fresh attempt, so
            // discard learned encoder bitrate from this session.
            lastEncoderBitrateBps = 0
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
