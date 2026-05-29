//
//  RTMPManager.swift
//  rtmpPackageExample
//
//  Created by Ezran Bayantemur on 15.01.2022.
//

import AudioToolbox
import AVFoundation
import HaishinKit

@MainActor
@objc(RTMPPublisher)
class RTMPModule: NSObject {
    private var cameraPosition: AVCaptureDevice.Position = .back

    @objc
    func startStream(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        RTMPCreator.startPublish(resolve: resolve, reject: reject)
    }

    @objc
    func stopStream(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        RTMPCreator.stopPublish(resolve: resolve, reject: reject)
    }

    @objc
    func mute(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        Task {
            await RTMPCreator.mixer.setAudioMixerSettings(AudioMixerSettings(isMuted: true))
            RTMPCreator.isMuted = true
            resolve(nil)
        }
    }

    @objc
    func unmute(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        Task {
            await RTMPCreator.mixer.setAudioMixerSettings(AudioMixerSettings(isMuted: false))
            RTMPCreator.isMuted = false
            resolve(nil)
        }
    }

    @objc
    func switchCamera(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        cameraPosition = cameraPosition == .back ? .front : .back
        Task {
            do {
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
                try await RTMPCreator.mixer.attachVideo(device)
                resolve(nil)
            } catch {
                reject("CAMERA_ERROR", "Failed to switch camera: \(error.localizedDescription)", error)
            }
        }
    }

    @objc
    func getPublishURL(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock){
        resolve(RTMPCreator.getPublishURL())
    }

    @objc
    func isMuted(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock){
        resolve(RTMPCreator.isMuted)
    }

    @objc
    func isStreaming(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock){
        resolve(RTMPCreator.isStreaming)
    }

    @objc
    func isAudioPrepared(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        resolve(RTMPCreator.isAudioAttached)
    }

    @objc
    func isVideoPrepared(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        resolve(RTMPCreator.isVideoAttached)
    }

    @objc
    func toggleFlash(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock){
        Task {
            RTMPCreator.isTorchEnabled = !RTMPCreator.isTorchEnabled
            await RTMPCreator.mixer.setTorchEnabled(RTMPCreator.isTorchEnabled)
            resolve(RTMPCreator.isTorchEnabled)
        }
    }

    @objc
    func setAudioInput(_ audioInput: NSInteger, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock){
        RTMPCreator.setAudioInput(audioInput: audioInput)
        resolve(nil)
    }

    @objc
    func setVideoSettings(_ videoSettingsDict: NSDictionary, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let width = videoSettingsDict["width"] as? Int,
              let height = videoSettingsDict["height"] as? Int,
              let bitrate = videoSettingsDict["bitrate"] as? Int else {
            reject("INVALID_ARGUMENTS", "Invalid video settings", nil)
            return
        }
        let maxBitrate = videoSettingsDict["maxBitrate"] as? Int ?? bitrate
        let audioBitrate = videoSettingsDict["audioBitrate"] as? Int ?? 128000
        let fps = videoSettingsDict["fps"] as? Int ?? 30
        let videoSettings = VideoSettingsType(width: width, height: height, bitrate: bitrate, maxBitrate: maxBitrate, audioBitrate: audioBitrate, fps: fps)

        RTMPCreator.setVideoSettings(videoSettings)
        resolve(nil)
    }

    @objc
    func setZoom(_ zoomLevel: Double, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
            reject("CAMERA_ERROR", "Camera device not available", nil)
            return
        }

        do {
            try device.lockForConfiguration()

            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let minZoom = device.minAvailableVideoZoomFactor
            let clampedZoom = max(minZoom, min(CGFloat(zoomLevel), maxZoom))

            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()

            resolve(clampedZoom)
        } catch {
            reject("ZOOM_ERROR", "Failed to set zoom: \(error.localizedDescription)", error)
        }
    }

    @objc
    func getMaxZoom(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
            reject("CAMERA_ERROR", "Camera device not available", nil)
            return
        }

        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        resolve(maxZoom)
    }

    @objc
    func getMinZoom(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
            reject("CAMERA_ERROR", "Camera device not available", nil)
            return
        }

        resolve(device.minAvailableVideoZoomFactor)
    }
}
