import React, { forwardRef, useImperativeHandle, useEffect } from 'react';
import {
  NativeModules,
  NativeEventEmitter,
  Platform,
  type ViewStyle,
} from 'react-native';
import PublisherComponent, {
  type BitrateReport,
  type DisconnectType,
  type ConnectionFailedType,
  type ConnectionStartedType,
  type ConnectionSuccessType,
  type NewBitrateReceivedType,
  type StreamStateChangedType,
  type BluetoothDeviceStatusChangedType,
} from './Component';
import type {
  RTMPPublisherRefProps,
  StreamState,
  BluetoothDeviceStatuses,
  AudioInputType,
  VideoSettingsType,
  VideoOrientation,
  LifecycleEventData,
} from './types';

const RTMPModule = NativeModules.RTMPPublisher;
export interface RTMPPublisherProps {
  testID?: string;
  style?: ViewStyle;
  streamURL: string;
  streamName: string;
  /**
   * Video settings for the stream (resolution, bitrate)
   */
  videoSettings?: VideoSettingsType;
  /**
   * Video orientation for the stream output
   * @default 'portrait'
   */
  videoOrientation?: VideoOrientation;
  /**
   * Callback for connection fails on RTMP server
   */
  onConnectionFailed?: (data: string) => void;
  /**
   * Callback for starting connection to RTMP server
   */
  onConnectionStarted?: (data: string) => void;
  /**
   * Callback for connection successfully to RTMP server
   */
  onConnectionSuccess?: (data: null) => void;
  /**
   * Callback for disconnect successfully to RTMP server
   */
  onDisconnect?: (data: null) => void;
  /**
   * Callback for bitrate telemetry from the native publisher.
   *
   * iOS payload: `{ throughput, encoderBitrate }` — throughput is the actual
   * outbound bit-rate from the RTMP socket, encoderBitrate is what the
   * adaptive-bitrate strategy has the H.264 encoder currently set to.
   *
   * Android payload: `{ encoderBitrate }` — the value the underlying
   * rtmp-rtsp-stream library reports from its own ABR.
   *
   * Both fields are optional; consumers should handle either being absent.
   */
  onNewBitrateReceived?: (data: BitrateReport) => void;
  /**
   * Alternatively callback for changing stream state
   * Returns parameter StreamState type
   */
  onStreamStateChanged?: (data: StreamState) => void;
  /**
   * Callback for bluetooth device connection changes
   */
  onBluetoothDeviceStatusChanged?: (data: BluetoothDeviceStatuses) => void;
  /**
   * Callback when app goes to background (Android only)
   * Includes wasStreaming boolean to indicate if stream was active
   */
  onAppBackgrounded?: (data: LifecycleEventData) => void;
  /**
   * Callback when app returns to foreground (Android only)
   * Includes wasStreaming boolean to indicate if stream was active before backgrounding
   */
  onAppForegrounded?: (data: LifecycleEventData) => void;
}

const RTMPPublisher = forwardRef<RTMPPublisherRefProps, RTMPPublisherProps>(
  (
    {
      onConnectionFailed,
      onConnectionStarted,
      onConnectionSuccess,
      onDisconnect,
      onNewBitrateReceived,
      onStreamStateChanged,
      onBluetoothDeviceStatusChanged,
      onAppBackgrounded,
      onAppForegrounded,
      ...props
    },
    ref
  ) => {
    // Subscribe to lifecycle events from native module (Android only)
    useEffect(() => {
      if (Platform.OS !== 'android') {
        return;
      }

      const eventEmitter = new NativeEventEmitter(RTMPModule);
      const subscriptions: Array<ReturnType<typeof eventEmitter.addListener>> =
        [];

      if (onAppBackgrounded) {
        subscriptions.push(
          eventEmitter.addListener(
            'onAppBackgrounded',
            (event: LifecycleEventData) => {
              onAppBackgrounded(event);
            }
          )
        );
      }

      if (onAppForegrounded) {
        subscriptions.push(
          eventEmitter.addListener(
            'onAppForegrounded',
            (event: LifecycleEventData) => {
              onAppForegrounded(event);
            }
          )
        );
      }

      return () => {
        subscriptions.forEach((subscription) => subscription.remove());
      };
    }, [onAppBackgrounded, onAppForegrounded]);
    const startStream = async () => await RTMPModule.startStream();

    const stopStream = async () => await RTMPModule.stopStream();

    const isStreaming = async () => RTMPModule.isStreaming();

    const isCameraOnPreview = async () => RTMPModule.isCameraOnPreview();

    const getPublishURL = async () => RTMPModule.getPublishURL();

    const hasCongestion = async () => RTMPModule.hasCongestion();

    const isAudioPrepared = async () => RTMPModule.isAudioPrepared();

    const isVideoPrepared = async () => RTMPModule.isVideoPrepared();

    const isMuted = async () => RTMPModule.isMuted();

    const mute = () => RTMPModule.mute();

    const unmute = () => RTMPModule.unmute();

    const switchCamera = () => RTMPModule.switchCamera();

    const toggleFlash = () => RTMPModule.toggleFlash();

    const setAudioInput = (audioInput: AudioInputType) =>
      RTMPModule.setAudioInput(audioInput);

    const setVideoSettings = async (videoSettings: VideoSettingsType) =>
      RTMPModule.setVideoSettings(videoSettings);

    const setZoom = async (zoomLevel: number) => RTMPModule.setZoom(zoomLevel);

    const getMaxZoom = async () => RTMPModule.getMaxZoom();

    const getMinZoom = async () => RTMPModule.getMinZoom();

    const handleOnConnectionFailed = (e: ConnectionFailedType) => {
      onConnectionFailed && onConnectionFailed(e.nativeEvent.data);
    };

    const handleOnConnectionStarted = (e: ConnectionStartedType) => {
      onConnectionStarted && onConnectionStarted(e.nativeEvent.data);
    };

    const handleOnConnectionSuccess = (e: ConnectionSuccessType) => {
      onConnectionSuccess && onConnectionSuccess(e.nativeEvent.data);
    };

    const handleOnDisconnect = (e: DisconnectType) => {
      onDisconnect && onDisconnect(e.nativeEvent.data);
    };

    const handleOnNewBitrateReceived = (e: NewBitrateReceivedType) => {
      // iOS emits both `throughput` (actual outbound) and `encoderBitrate`
      // (ABR's current encoder budget). Android emits only `encoderBitrate`.
      // Forward the raw event so consumers can read whichever fields the
      // current platform provides.
      onNewBitrateReceived && onNewBitrateReceived(e.nativeEvent);
    };

    const handleOnStreamStateChanged = (e: StreamStateChangedType) => {
      onStreamStateChanged && onStreamStateChanged(e.nativeEvent.data);
    };

    const handleBluetoothDeviceStatusChanged = (
      e: BluetoothDeviceStatusChangedType
    ) => {
      onBluetoothDeviceStatusChanged &&
        onBluetoothDeviceStatusChanged(e.nativeEvent.data);
    };

    useImperativeHandle(ref, () => ({
      startStream,
      stopStream,
      isStreaming,
      isCameraOnPreview,
      getPublishURL,
      hasCongestion,
      isAudioPrepared,
      isVideoPrepared,
      isMuted,
      mute,
      unmute,
      switchCamera,
      toggleFlash,
      setAudioInput,
      setVideoSettings,
      setZoom,
      getMaxZoom,
      getMinZoom,
    }));

    return (
      <PublisherComponent
        {...props}
        onDisconnect={handleOnDisconnect}
        onConnectionFailed={handleOnConnectionFailed}
        onConnectionStarted={handleOnConnectionStarted}
        onConnectionSuccess={handleOnConnectionSuccess}
        onNewBitrateReceived={handleOnNewBitrateReceived}
        onStreamStateChanged={handleOnStreamStateChanged}
        onBluetoothDeviceStatusChanged={handleBluetoothDeviceStatusChanged}
      />
    );
  }
);

export default RTMPPublisher;
