package com.reactnativertmppublisher.modules;

import android.os.Handler;
import android.os.Looper;

import com.pedro.rtplibrary.rtmp.RtmpCamera1;

/**
 * Adaptive bitrate control loop for Android.
 *
 * rtmp-rtsp-stream-client-java has no built-in adaptive bitrate, only the
 * primitives hasCongestion() and setVideoBitrateOnFly(). This class drives a
 * small "down fast, up slow" loop on top of them, matching the behavior of
 * HaishinKit's built-in strategy on iOS so the two platforms stay consistent.
 *
 * The ceiling bitrate (the value the stream was prepared with) is the maximum;
 * the loop drops below it under congestion and climbs back toward it when the
 * network is stable.
 */
public class AdaptiveBitrate {
  private static final long TICK_INTERVAL_MS = 2000;
  private static final long STABLE_BEFORE_UP_MS = 18000;
  private static final int MIN_BITRATE = 300 * 1000;
  private static final double DOWN_FACTOR = 0.8;

  private final RtmpCamera1 _camera;
  private final Handler _handler = new Handler(Looper.getMainLooper());

  private int _ceilingBitrate;
  private int _currentBitrate;
  private long _stableSinceMs = 0;
  private boolean _running = false;

  public AdaptiveBitrate(RtmpCamera1 camera) {
    _camera = camera;
  }

  /** Starts the loop. ceilingBitrate is the maximum (the prepared bitrate). */
  public void start(int ceilingBitrate) {
    _ceilingBitrate = ceilingBitrate;
    _currentBitrate = ceilingBitrate;
    _stableSinceMs = System.currentTimeMillis();
    _running = true;
    _handler.postDelayed(_tick, TICK_INTERVAL_MS);
  }

  /** Stops the loop. Safe to call when not running. */
  public void stop() {
    _running = false;
    _handler.removeCallbacks(_tick);
  }

  /** Updates the ceiling when the requested video settings change. */
  public void setCeiling(int ceilingBitrate) {
    _ceilingBitrate = ceilingBitrate;
    if (_currentBitrate > ceilingBitrate) {
      _currentBitrate = ceilingBitrate;
      applyBitrate();
    }
  }

  private final Runnable _tick = new Runnable() {
    @Override
    public void run() {
      if (!_running) {
        return;
      }
      try {
        evaluate();
      } catch (Exception e) {
        // Degrade in place: never let the loop crash the stream.
      }
      if (_running) {
        _handler.postDelayed(this, TICK_INTERVAL_MS);
      }
    }
  };

  private void evaluate() {
    boolean congested = _camera.hasCongestion();
    long now = System.currentTimeMillis();

    if (congested) {
      // Down fast: drop immediately, reset the stability window.
      _stableSinceMs = now;
      int next = Math.max((int) (_currentBitrate * DOWN_FACTOR), MIN_BITRATE);
      if (next < _currentBitrate) {
        _currentBitrate = next;
        applyBitrate();
      }
      return;
    }

    // Up slow: only after sustained stability, and one increment at a time.
    if (_currentBitrate < _ceilingBitrate
        && now - _stableSinceMs >= STABLE_BEFORE_UP_MS) {
      int increment = Math.max(_ceilingBitrate / 4, 1);
      _currentBitrate = Math.min(_currentBitrate + increment, _ceilingBitrate);
      applyBitrate();
      _stableSinceMs = now;
    }
  }

  private void applyBitrate() {
    _camera.setVideoBitrateOnFly(_currentBitrate);
  }
}
