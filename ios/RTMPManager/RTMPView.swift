//
//  RTMPView.swift
//  rtmpPackageExample
//
//  Created by Ezran Bayantemur on 15.01.2022.
//

import UIKit
import HaishinKit
import AVFoundation
import VideoToolbox

class RTMPView: UIView {
  private var hkView: MTHKView!
  private var pendingAudioUpdateAttempts = 0
  private let maxAudioUpdateAttempts = 10
  private var hasAppliedInitialSettings = false
  private var hasAttachedStream = false
  private var connectionStatusTask: Task<Void, Never>?
  private var streamStatusTask: Task<Void, Never>?
  private var bitrateReportTask: Task<Void, Never>?
  private var hasCleanedUp = false

  @objc var onDisconnect: RCTDirectEventBlock?
  @objc var onConnectionFailed: RCTDirectEventBlock?
  @objc var onConnectionStarted: RCTDirectEventBlock?
  @objc var onConnectionSuccess: RCTDirectEventBlock?
  @objc var onNewBitrateReceived: RCTDirectEventBlock?
  @objc var onStreamStateChanged: RCTDirectEventBlock?

  @objc var streamURL: NSString = "" {
    didSet {
      RTMPCreator.setStreamUrl(url: streamURL as String)
    }
  }

  @objc var streamName: NSString = "" {
    didSet {
      RTMPCreator.setStreamName(name: streamName as String)
    }
  }

  @objc var enableAudio: Bool = true {
    didSet {
      guard hasAttachedStream else { return }
      updateAudioAttachment()
    }
  }

  // Defaults are LANDSCAPE (1280x720). If the JS prop hasn't been written
  // yet when performInitialSetup runs, the encoder is configured with these
  // landscape dimensions. Otherwise the encoder would default to portrait
  // (720x1280) and the camera's landscape frames would be cropped to portrait
  // before reaching the player.
  @objc var videoSettings: NSDictionary = NSDictionary(
      dictionary: [
        "width": 1280,
        "height": 720,
        "bitrate": 3000 * 1000,
        "audioBitrate": 128 * 1000,
        "fps": 30
      ]
  ){
    didSet {
        guard hasAttachedStream else { return }
        applyVideoSettings()
    }
  }

  private func applyVideoSettings() {
      // Defaults match the @objc var videoSettings landscape defaults above.
      let width = videoSettings["width"] as? Int ?? 1280
      let height = videoSettings["height"] as? Int ?? 720
      let bitrate = videoSettings["bitrate"] as? Int ?? (3000 * 1000)
      let audioBitrate = videoSettings["audioBitrate"] as? Int ?? (128 * 1000)
      let fps = videoSettings["fps"] as? Int ?? 30

      let preset = selectCapturePreset(for: width, height: height)
      Task {
        await RTMPCreator.mixer.setSessionPreset(preset)
      }

      RTMPCreator.setVideoSettings(VideoSettingsType(width: width, height: height, bitrate: bitrate, audioBitrate: audioBitrate, fps: fps))
  }

  @objc var videoOrientation: NSString = "portrait" {
    didSet {
      NSLog("📡 [RTMPView] videoOrientation didSet: \"%@\" -> \"%@\" hasAttachedStream=%@",
            oldValue as String, videoOrientation as String, hasAttachedStream ? "true" : "false")
      guard hasAttachedStream else { return }
      applyVideoOrientation()
    }
  }

  private func applyVideoOrientation() {
    NSLog("📡 [RTMPView] applyVideoOrientation called with \"%@\"", self.videoOrientation as String)
    Task {
      switch self.videoOrientation {
      case "landscape":
        await RTMPCreator.mixer.setVideoOrientation(AVCaptureVideoOrientation.landscapeRight)
        NSLog("📡 [RTMPView] setVideoOrientation(.landscapeRight) completed")
      default:
        await RTMPCreator.mixer.setVideoOrientation(AVCaptureVideoOrientation.portrait)
        NSLog("📡 [RTMPView] setVideoOrientation(.portrait) completed")
      }
    }
  }

  private func cleanup() {
    guard !hasCleanedUp else { return }
    hasCleanedUp = true

    // Stop streaming if active
    if RTMPCreator.isStreaming {
      RTMPCreator.stopPublish()
    }

    // Cancel status listeners
    connectionStatusTask?.cancel()
    connectionStatusTask = nil
    streamStatusTask?.cancel()
    streamStatusTask = nil
    bitrateReportTask?.cancel()
    bitrateReportTask = nil

    // Capture view reference before potential deallocation
    let view = hkView!

    // Detach view from mixer and stream
    if hasAttachedStream {
      Task {
        await RTMPCreator.mixer.removeOutput(view)
        await RTMPCreator.stream.removeOutput(view)
      }
      hasAttachedStream = false
    }

    // Detach camera and audio
    Task {
      try? await RTMPCreator.mixer.attachVideo(nil)
      try? await RTMPCreator.mixer.attachAudio(nil)
      await MainActor.run {
        RTMPCreator.isVideoAttached = false
        RTMPCreator.isAudioAttached = false
      }
    }

    // Re-enable idle timer
    UIApplication.shared.isIdleTimerDisabled = false
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()

    do {
      try session.setCategory(
        .playAndRecord,
        mode: .videoChat,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try session.setPreferredSampleRate(44100)
      try session.setPreferredIOBufferDuration(0.005)

      if let input = session.availableInputs?.first(where: { input in
        return input.portType == .builtInMic
      }) {
        try session.setPreferredInput(input)
      }

      try session.setActive(true)
    } catch {
      NSLog("RTMPView: Failed to configure AVAudioSession: %@", error.localizedDescription)
    }
  }

  private func updateAudioAttachment() {
    if RTMPCreator.isStreaming {
      if pendingAudioUpdateAttempts >= maxAudioUpdateAttempts {
        NSLog("RTMPView: Skipping audio update; stream still active.")
        return
      }

      pendingAudioUpdateAttempts += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.updateAudioAttachment()
      }
      return
    }

    pendingAudioUpdateAttempts = 0
    if enableAudio {
      configureAudioSession()
      Task {
        try? await RTMPCreator.mixer.attachAudio(AVCaptureDevice.default(for: .audio))
      }
    } else {
      Task {
        try? await RTMPCreator.mixer.attachAudio(nil)
      }
    }
  }

  private func selectCapturePreset(for width: Int, height: Int) -> AVCaptureSession.Preset {
      let maxDimension = max(width, height)
      if maxDimension <= 640 {
          return .vga640x480
      } else if maxDimension <= 1280 {
          return .hd1280x720
      } else {
          return .hd1920x1080
      }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    UIApplication.shared.isIdleTimerDisabled = true

    hkView = MTHKView(frame: UIScreen.main.bounds)
    hkView.videoGravity = .resizeAspectFill

    startListeningForStatus()

    self.addSubview(hkView)
  }

  private func startListeningForStatus() {
    connectionStatusTask = Task { [weak self] in
      for await status in await RTMPCreator.connection.status {
        guard let self = self else { break }
        await MainActor.run {
          self.handleConnectionStatus(status)
        }
      }
    }

    streamStatusTask = Task { [weak self] in
      for await status in await RTMPCreator.stream.status {
        guard let self = self else { break }
        await MainActor.run {
          self.handleStreamStatus(status)
        }
      }
    }
  }

  /// Polls the RTMP stream's outbound throughput and emits it as the
  /// onNewBitrateReceived event (~1.5s cadence). iOS-only — Android already
  /// emits this event via ConnectionChecker.
  private func startBitrateReporting() {
    bitrateReportTask?.cancel()
    bitrateReportTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self = self else { break }
        let bytesPerSecond = await RTMPCreator.stream.info.currentBytesPerSecond
        let bitsPerSecond = bytesPerSecond * 8
        // The encoder's actual configured video bitrate — what the native
        // adaptive-bitrate strategy has currently settled on.
        let encoderBitrate = await RTMPCreator.stream.videoSettings.bitRate
        await MainActor.run {
          // JS reads e.nativeEvent.data — the key MUST be "data" to match
          // the wrapper and the other events (e.g. onStreamStateChanged).
          self.onNewBitrateReceived?([
            "data": bitsPerSecond,
            "encoderBitrate": encoderBitrate,
          ])
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
      }
    }
  }

  private func handleConnectionStatus(_ status: RTMPStatus) {
    switch status.code {
    case RTMPConnection.Code.connectSuccess.rawValue:
      onConnectionSuccess?(nil)
      changeStreamState(status: "CONNECTING")

    case RTMPConnection.Code.connectFailed.rawValue:
      onConnectionFailed?(nil)
      changeStreamState(status: "FAILED")

    case RTMPConnection.Code.connectClosed.rawValue:
      onDisconnect?(nil)
      changeStreamState(status: "CLOSED")

    default:
      break
    }
  }

  private func handleStreamStatus(_ status: RTMPStatus) {
    switch status.code {
    case RTMPStream.Code.publishStart.rawValue:
      onConnectionStarted?(nil)
      changeStreamState(status: "CONNECTED")
      startBitrateReporting()

    default:
      break
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hkView.frame = self.bounds

    if !hasAppliedInitialSettings {
      hasAppliedInitialSettings = true
      performInitialSetup()
    }
  }

  private func performInitialSetup() {
    // Defaults match the @objc var videoSettings landscape defaults above.
    let width = videoSettings["width"] as? Int ?? 1280
    let height = videoSettings["height"] as? Int ?? 720
    let bitrate = videoSettings["bitrate"] as? Int ?? (3000 * 1000)
    let audioBitrate = videoSettings["audioBitrate"] as? Int ?? (128 * 1000)
    let fps = videoSettings["fps"] as? Int ?? 30
    let preset = selectCapturePreset(for: width, height: height)
    let orientation = videoOrientation

    NSLog("📡 [RTMPView] performInitialSetup START orientation=\"%@\" width=%d height=%d preset=%@",
          orientation as String, width, height, preset.rawValue)

    Task {
      // Configure audio session and attach audio
      configureAudioSession()
      if enableAudio {
        try? await RTMPCreator.mixer.attachAudio(AVCaptureDevice.default(for: .audio))
        await MainActor.run { RTMPCreator.isAudioAttached = true }
      }

      // Attach camera
      let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
      try? await RTMPCreator.mixer.attachVideo(camera)
      await MainActor.run { RTMPCreator.isVideoAttached = true }
      NSLog("📡 [RTMPView] performInitialSetup: attachVideo done")

      // Apply capture settings
      await RTMPCreator.mixer.setSessionPreset(preset)
      await RTMPCreator.mixer.setFrameRate(Float64(fps))
      NSLog("📡 [RTMPView] performInitialSetup: setSessionPreset(%@) setFrameRate(%d) done", preset.rawValue, fps)

      // Apply video orientation
      switch orientation {
      case "landscape":
        await RTMPCreator.mixer.setVideoOrientation(.landscapeRight)
        NSLog("📡 [RTMPView] performInitialSetup: setVideoOrientation(.landscapeRight) done")
      default:
        await RTMPCreator.mixer.setVideoOrientation(.portrait)
        NSLog("📡 [RTMPView] performInitialSetup: setVideoOrientation(.portrait) done — bug? orientation was \"%@\"", orientation as String)
      }

      // Readback to verify orientation actually applied to the mixer
      let appliedOrientation = await RTMPCreator.mixer.videoOrientation
      NSLog("📡 [RTMPView] performInitialSetup: mixer.videoOrientation readback = %d (1=portrait,2=portraitUpsideDown,3=landscapeRight,4=landscapeLeft)", appliedOrientation.rawValue)

      // Apply encoding settings
      NSLog("📡 [RTMPView] performInitialSetup: setting encoder videoSize=%dx%d bitrate=%d", width, height, bitrate)
      await RTMPCreator.stream.setVideoSettings(VideoCodecSettings(
        videoSize: CGSize(width: width, height: height),
        bitRate: bitrate,
        profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
        scalingMode: .cropSourceToCleanAperture
      ))

      await RTMPCreator.stream.setAudioSettings(AudioCodecSettings(
        bitRate: audioBitrate
      ))

      // Connect mixer to stream (mixer feeds encoded data to stream)
      await RTMPCreator.mixer.addOutput(RTMPCreator.stream)

      // Connect stream to view (stream feeds video to preview)
      await RTMPCreator.stream.addOutput(hkView)

      await MainActor.run { [weak self] in
        self?.hasAttachedStream = true
      }
    }
  }

    required init?(coder aDecoder: NSCoder) {
       fatalError("init(coder:) has not been implemented")
     }

    override func removeFromSuperview() {
        cleanup()
        super.removeFromSuperview()
    }

    deinit {
        cleanup()
    }

    public func changeStreamState(status: String){
      if onStreamStateChanged != nil {
        onStreamStateChanged!(["data": status])
       }
    }
}
