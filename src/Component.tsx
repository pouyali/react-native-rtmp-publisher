import {
  NativeSyntheticEvent,
  requireNativeComponent,
  ViewStyle,
} from 'react-native';
import type {
  StreamState,
  BluetoothDeviceStatuses,
  VideoSettingsType,
  VideoOrientation,
} from './types';

type RTMPData<T> = { data: T };

/**
 * Payload for the onNewBitrateReceived event. Both fields are optional and
 * platform-specific:
 *   - iOS reports `throughput` (actual outbound bytes/s × 8) AND
 *     `encoderBitrate` (the H.264 bit budget HaishinKit's adaptive strategy
 *     has settled on).
 *   - Android reports only `encoderBitrate` (the value the rtmp-rtsp-stream
 *     library's internal ABR has set).
 *
 * Consumers should treat each field as optional and interpret accordingly.
 */
export type BitrateReport = {
  throughput?: number;
  encoderBitrate?: number;
};

export type ConnectionFailedType = NativeSyntheticEvent<RTMPData<string>>;
export type ConnectionStartedType = NativeSyntheticEvent<RTMPData<string>>;
export type ConnectionSuccessType = NativeSyntheticEvent<RTMPData<null>>;
export type DisconnectType = NativeSyntheticEvent<RTMPData<null>>;
export type NewBitrateReceivedType = NativeSyntheticEvent<BitrateReport>;
export type StreamStateChangedType = NativeSyntheticEvent<
  RTMPData<StreamState>
>;
export type BluetoothDeviceStatusChangedType = NativeSyntheticEvent<
  RTMPData<BluetoothDeviceStatuses>
>;
export interface NativeRTMPPublisherProps {
  style?: ViewStyle;
  streamURL: string;
  streamName: string;
  enableAudio?: boolean;
  videoSettings?: VideoSettingsType;
  videoOrientation?: VideoOrientation;
  onConnectionFailed?: (e: ConnectionFailedType) => void;
  onConnectionStarted?: (e: ConnectionStartedType) => void;
  onConnectionSuccess?: (e: ConnectionSuccessType) => void;
  onDisconnect?: (e: DisconnectType) => void;
  onNewBitrateReceived?: (e: NewBitrateReceivedType) => void;
  onStreamStateChanged?: (e: StreamStateChangedType) => void;
  onBluetoothDeviceStatusChanged?: (
    e: BluetoothDeviceStatusChangedType
  ) => void;
}
export default requireNativeComponent<NativeRTMPPublisherProps>(
  'RTMPPublisher'
);
