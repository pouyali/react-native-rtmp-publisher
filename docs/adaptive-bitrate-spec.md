# Adaptive Bitrate — Design Spec

**Branch:** `feat/bitrate-telemetry`
**Date:** 2026-05-17

## Problem

The publisher streams at a fixed bitrate chosen once at start. On weak or
variable uplinks (low 3G, congested venue Wi-Fi) the encoder pushes more than
the network can carry; the RTMP send buffer backs up and the connection is
dropped. The library exposes no live bitrate adaptation.

The JS layer declares `onNewBitrateReceived`, `hasCongestion()`, and
`setVideoSettings()`, but on iOS `onNewBitrateReceived` is never emitted and
`hasCongestion()` has no native implementation — so any JS-driven adaptive
bitrate cannot function.

## Decision

Adaptive bitrate is **always-on**: enabled unconditionally whenever streaming
starts. The bitrate passed via `videoSettings` is the *maximum* (ceiling);
adaptation drops below it under congestion and climbs back when bandwidth
recovers. Adaptation is implemented **natively on each platform** — no
JS-driven control loop.

The two platforms differ in what their underlying library provides:

- **iOS** — HaishinKit 2.0.9 ships a complete built-in strategy
  (`HKStreamVideoAdaptiveBitRateStrategy`) and already runs a `NetworkMonitor`.
  `RTMPConnection` consumes the monitor's events and forwards them via
  `Task { await stream.dispatch(event) }` (`RTMPConnection.swift:509`), which
  calls `bitrateStorategy?.adjustBitrate(...)`. The whole control loop exists —
  nothing currently *installs* a strategy. Fix = install one.
- **Android** — `rtmp-rtsp-stream-client-java` 2.2.2 has **no** built-in
  adaptive-bitrate loop. It exposes only the primitives: `hasCongestion()`
  (is the send queue backing up?) and `setVideoBitrateOnFly(int)` (change the
  encoder bitrate live). Fix = add a small native control loop in the fork
  that uses these primitives.

## Non-Goals

- No new public prop. ABR is always-on; no opt-out.
- No JS-side control loop. Adaptation happens natively.
- No custom adaptation algorithm — the platform built-ins are used as-is.

## Changes

### iOS — `ios/RTMPCreator.swift`

In `startPublish`, after `stream.publish(...)` succeeds, install the strategy:

```swift
let strategy = HKStreamVideoAdaptiveBitRateStrategy(
    mamimumVideoBitrate: videoSettings.bitrate
)
await stream.setBitrateStorategy(strategy)
```

Notes:
- `mamimumVideoBitrate` must track the current `videoSettings.bitrate`. When
  `setVideoSettings()` is called mid-stream (e.g. the user changes quality),
  re-install the strategy with the new ceiling so the maximum follows the
  user's selection.
- `setBitrateStorategy` is a public method on `RTMPStream` (and the `HKStream`
  protocol). No other wiring is needed — `RTMPConnection` already drives the
  `NetworkMonitor` and dispatches events into the stream.

### Android — new `modules/AdaptiveBitrate.java` + hook in `Publisher.java`

`rtplibrary` 2.2.2 has no built-in ABR, so the fork adds a small control loop.

New class `AdaptiveBitrate` owns the loop:
- Holds a reference to the `RtmpCamera1` and the ceiling bitrate.
- A handler-driven tick (~every 2s) while streaming:
  - `camera.hasCongestion()` true → step **down fast**: drop bitrate to ~80%
    of current, floored at a minimum (e.g. 300 kbps), via
    `setVideoBitrateOnFly()`.
  - Not congested for a sustained period (~18s) → step **up slow**: raise
    bitrate by one increment (ceiling/4), capped at the ceiling.
- `start(ceilingBitrate)` / `stop()` lifecycle, mirroring iOS semantics.

`Publisher.startStream()` constructs/starts the loop after `startStream(url)`;
`stopStream()` stops it. `setVideoSettings()` updates the ceiling.

`ConnectionChecker.onNewBitrateRtmp()` already forwards `onNewBitrateReceived`
to JS — kept for observability, not used to drive adaptation.

"Down fast, up slow" intentionally matches the behavior of HaishinKit's iOS
strategy so the two platforms behave consistently.

## Behavior After Change

- The encoder bitrate drops automatically when the RTMP socket reports
  insufficient bandwidth, and recovers toward the `videoSettings` ceiling when
  the network stabilizes.
- `videoSettings.bitrate` is reinterpreted as the **ceiling**, not a fixed
  target. Consumers that pick a tier (e.g. a quality selector) set the ceiling.
- `onNewBitrateReceived` continues to fire on Android for observability; iOS
  does not emit it (HaishinKit handles adaptation internally) and consumers
  must not depend on it for ABR.

## Testing

Manual, on physical devices, both platforms, using a network conditioner:
1. Start a stream on a good network — confirm it runs at/near the ceiling.
2. Degrade the uplink (Network Link Conditioner "Very Bad Network" on iOS; a
   throttled network on Android) — confirm the stream stays connected and the
   bitrate drops instead of the connection dying.
3. Restore the network — confirm the bitrate climbs back toward the ceiling.
4. Confirm a normal start/stop cycle is unaffected.

## Open Questions

- iOS: `HKStreamVideoAdaptiveBitRateStrategy` lowers `bitRate` and adjusts
  `frameInterval` but does not change capture resolution. Acceptable for now —
  resolution is fixed per stream; only bitrate/fps adapt.
