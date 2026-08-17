import type { ViewStyle } from 'react-native';

export interface RTMPPublisherRefProps {
  /**
   * Starts stream operation
   */
  startStream: () => Promise<void>;
  /**
   * Stops stream operation
   */
  stopStream: () => Promise<void>;
  /**
   * Checks stream status
   */
  isStreaming: () => Promise<boolean>;
  /**
   * Checks if camera on mount
   */
  isCameraOnPreview: () => Promise<boolean>;
  /**
   * Gets settled publish url
   */
  getPublishURL: () => Promise<string>;
  /**
   * Checks congestion status
   */
  hasCongestion: () => Promise<boolean>;
  /**
   * Checks audio status
   */
  isAudioPrepared: () => Promise<boolean>;
  /**
   * Checks video status
   */
  isVideoPrepared: () => Promise<boolean>;
  /**
   * Checks if mic closed
   */
  isMuted: () => Promise<boolean>;
  /**
   * Mutes the mic
   */
  mute: () => Promise<void>;
  /**
   * Unmutes the mic
   */
  unmute: () => Promise<void>;
  /**
   * Switches the camera
   */
  switchCamera: () => Promise<void>;
  /**
   * Toggles the flash
   */
  toggleFlash: () => Promise<void>;
  /**
   * Sets the audio input (microphone type)
   */
  setAudioInput: (audioInput: AudioInputType) => Promise<void>;
  /**
   * Sets video settings (resolution, bitrate)
   */
  setVideoSettings: (videoSettings: VideoSettingsType) => Promise<void>;
  /**
   * Sets the camera zoom level
   * @param zoomLevel - The desired zoom level (use getMinZoom/getMaxZoom to determine valid range)
   * @returns The actual zoom level that was set (may be clamped to valid range)
   */
  setZoom: (zoomLevel: number) => Promise<number>;
  /**
   * Gets the maximum zoom level supported by the current camera
   * @returns Maximum zoom level (iOS: CGFloat ~1.0-10.0, Android: int varies by device)
   */
  getMaxZoom: () => Promise<number>;
  /**
   * Gets the minimum zoom level supported by the current camera
   * @returns Minimum zoom level (typically 1.0 on iOS, varies on Android)
   */
  getMinZoom: () => Promise<number>;
}

export interface RTMPPublisherProps {
  style?: ViewStyle;
  streamURL: string;
  streamName: string;
  enableAudio?: boolean;
  videoSettings?: VideoSettingsType;
  onConnectionFailed?: (e: null) => void;
  onConnectionStarted?: (e: null) => void;
  onConnectionSuccess?: (e: null) => void;
  onDisconnect?: (e: null) => void;
  onNewBitrateReceived?: (e: number) => void;
  onStreamStateChanged?: (e: StreamState) => void;
}
export type StreamStatus =
  | 'CONNECTING'
  | 'CONNECTED'
  | 'DISCONNECTED'
  | 'CLOSED'
  | 'FAILED';

export enum StreamState {
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  DISCONNECTED = 'DISCONNECTED',
  CLOSED = 'CLOSED',
  FAILED = 'FAILED',
}
export enum BluetoothDeviceStatuses {
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  DISCONNECTED = 'DISCONNECTED',
}

export enum AudioInputType {
  BLUETOOTH_HEADSET = 0,
  SPEAKER = 1,
  WIRED_HEADSET = 2,
}

export interface VideoSettingsType {
  width: number;
  height: number;
  /**
   * Initial encoder bitrate target. The native adaptive strategy can
   * move the live encoder bitrate between an internal floor (200 Kbps)
   * and `maxBitrate` based on observed outbound throughput.
   */
  bitrate: number;
  /**
   * Absolute ceiling the adaptive strategy may step the encoder up to.
   * When omitted, defaults to `bitrate` — i.e. no step-up, encoder
   * effectively static at `bitrate`. Consumers that want auto-step-up
   * beyond their starting preset should pass the highest-preset
   * bitrate here (e.g. 4_500_000 for 1080p quality).
   */
  maxBitrate?: number;
  audioBitrate?: number;
  /**
   * Frames per second for the stream
   * @default 30
   */
  fps?: number;
}

export type VideoOrientation = 'portrait' | 'landscape';

/**
 * Data passed to lifecycle event callbacks (Android only)
 */
export interface LifecycleEventData {
  /**
   * Whether the app was streaming before going to background
   */
  wasStreaming: boolean;
}
