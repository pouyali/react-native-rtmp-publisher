package com.reactnativertmppublisher.modules;

import androidx.annotation.NonNull;

import com.pedro.rtmp.utils.ConnectCheckerRtmp;
import com.reactnativertmppublisher.interfaces.ConnectionListener;

import java.util.ArrayList;
import java.util.List;

public class ConnectionChecker implements ConnectCheckerRtmp {
  private final List<ConnectionListener> listeners = new ArrayList<>();

  public void addListener(ConnectionListener listener) {
    listeners.add(listener);
  }

  public void clearListeners() {
    listeners.clear();
  }

  @Override
  public void onAuthErrorRtmp() {
    for (ConnectionListener l : listeners) {
      l.onChange("onAuthError", null);
    }
  }

  @Override
  public void onAuthSuccessRtmp() {
    for (ConnectionListener l : listeners) {
      l.onChange("onAuthSuccess", null);
    }
  }

  // TODO: Parameters will be send after onChange method updated
  @Override
  public void onConnectionFailedRtmp(@NonNull String s) {
    for (ConnectionListener l : listeners) {
      l.onChange("onConnectionFailed", s);
    }
  }

  // TODO: Parameters will be send after onChange method updated
  @Override
  public void onConnectionStartedRtmp(@NonNull String s) {
    for (ConnectionListener l : listeners) {
      l.onChange("onConnectionStarted", s);
    }
  }

  @Override
  public void onConnectionSuccessRtmp() {
    for (ConnectionListener l : listeners) {
      l.onChange("onConnectionSuccess", null);
    }
  }

  @Override
  public void onDisconnectRtmp() {
    for (ConnectionListener l : listeners) {
      l.onChange("onDisconnect", null);
    }
  }

  // Emits the value the rtmp-rtsp-stream library reports from its own
  // adaptive-bitrate controller as the encoder bitrate. The JS bridge
  // wraps this into a BitrateReport with only `encoderBitrate` populated;
  // throughput is iOS-only (HaishinKit exposes the outbound byte count
  // separately from the encoder budget — the Android library does not).
  @Override
  public void onNewBitrateRtmp(long b) {
    for (ConnectionListener l : listeners) {
      l.onChange("onNewBitrateReceived", new BitrateReport(b));
    }
  }

  /**
   * Marker payload type so the JS bridge serializer can emit the
   * `{ encoderBitrate }` shape that the cross-platform JS wrapper expects,
   * instead of the legacy `{ data: <number> }` shape produced by
   * ObjectCaster for raw Longs.
   */
  public static class BitrateReport {
    public final long encoderBitrate;

    public BitrateReport(long encoderBitrate) {
      this.encoderBitrate = encoderBitrate;
    }
  }
}
