//
//  AdaptiveBitRateStrategy.swift
//
//  Throughput-driven adaptive bitrate for mobile RTMP uplink.
//
//  HaishinKit's built-in HKStreamVideoAdaptiveBitRateStrategy reacts to
//  queue growth, which works for slow degradations but misses sharp
//  cellular drops where the network drops from Mbps to Kbps in a single
//  second — the socket dies before three consecutive queue-growing
//  samples are observed.
//
//  This strategy reacts to actual outbound throughput vs the current
//  encoder target. Drops the target promptly when throughput falls below
//  70% of target for 2 consecutive samples (~3 s at 1.5 s cadence), and
//  climbs slowly back up only after 20 consecutive headroom samples
//  (~30 s) to prevent oscillation.
//
//  The protocol's `mamimumVideoBitRate` represents the ABSOLUTE ceiling
//  the strategy is allowed to climb to — typically the highest preset's
//  bitrate (e.g., 4.5 Mbps for 1080p). The starting target is supplied
//  separately and is normally the user's chosen preset bitrate (e.g.,
//  1.2 Mbps for medium). The encoder bitrate can move between `floorBps`
//  and `mamimumVideoBitRate` dynamically without resolution changes.
//

import HaishinKit
import Foundation

public final actor AdaptiveBitRateStrategy: HKStreamBitRateStrategy {
    // MARK: - Protocol contract

    /// The absolute upper bound the strategy may step the encoder up to.
    public let mamimumVideoBitRate: Int
    public let mamimumAudioBitRate: Int = 0

    // MARK: - Configuration

    /// The hard floor below which the encoder will not be dropped.
    /// Below this video is effectively unusable; the broadcast should
    /// honestly fail rather than push garbage that the server will reject.
    private let floorBps: Int

    /// Required consecutive sub-threshold samples before a step-down fires.
    /// At HaishinKit's ~1 s NetworkMonitor cadence this is the reaction time.
    private static let stepDownConsecutiveSamples = 2

    /// Required consecutive in-headroom samples before a step-up fires.
    /// Larger than the step-down requirement to prevent oscillation on a
    /// network that's borderline (good for 5 s, bad for 5 s, ...).
    private static let stepUpConsecutiveSamples = 20

    /// Throughput must drop below this fraction of the current target
    /// to count as a sub-threshold sample.
    private static let stepDownThresholdRatio: Double = 0.70

    /// Throughput must reach this fraction of the current target to count
    /// as an in-headroom sample.
    private static let stepUpThresholdRatio: Double = 0.85

    /// On step-down, drop to this fraction of the current target.
    private static let stepDownFactor: Double = 0.70

    /// On step-up, climb to this fraction of the current target.
    private static let stepUpFactor: Double = 1.15

    // MARK: - State

    private var currentTargetBps: Int
    private var stepDownCount = 0
    private var stepUpCount = 0

    // MARK: - Init

    public init(
        absoluteCeilingBps: Int,
        initialTargetBps: Int,
        floorBps: Int
    ) {
        self.mamimumVideoBitRate = absoluteCeilingBps
        self.floorBps = floorBps
        self.currentTargetBps = max(min(initialTargetBps, absoluteCeilingBps), floorBps)
    }

    // MARK: - Protocol method

    public func adjustBitrate(
        _ event: NetworkMonitorEvent,
        stream: some HKStream
    ) async {
        switch event {
        case .status(let report), .publishInsufficientBWOccured(let report):
            let throughputBps = report.currentBytesOutPerSecond * 8
            await processThroughput(throughputBps, stream: stream)
        case .reset:
            // Reset is fired by HaishinKit on republish — keep the
            // current target as-is so we don't lose the network-quality
            // information learned during the prior session.
            stepDownCount = 0
            stepUpCount = 0
        }
    }

    // MARK: - Throughput processing

    private func processThroughput(
        _ throughputBps: Int,
        stream: some HKStream
    ) async {
        let downThresholdBps = Int(Double(currentTargetBps) * Self.stepDownThresholdRatio)
        let upThresholdBps = Int(Double(currentTargetBps) * Self.stepUpThresholdRatio)

        if throughputBps < downThresholdBps {
            stepDownCount += 1
            stepUpCount = 0
            if stepDownCount >= Self.stepDownConsecutiveSamples {
                await applyStepDown(stream: stream)
                stepDownCount = 0
            }
        } else if throughputBps >= upThresholdBps {
            stepUpCount += 1
            stepDownCount = 0
            if stepUpCount >= Self.stepUpConsecutiveSamples {
                await applyStepUp(stream: stream)
                stepUpCount = 0
            }
        } else {
            // Throughput in the neutral zone: not low enough to be a
            // stall, not high enough to claim headroom. Reset both
            // counters so a sequence of mixed samples can't accumulate
            // into a false trigger.
            stepDownCount = 0
            stepUpCount = 0
        }
    }

    // MARK: - Step actions

    private func applyStepDown(stream: some HKStream) async {
        let proposedBps = Int(Double(currentTargetBps) * Self.stepDownFactor)
        let newTargetBps = max(proposedBps, floorBps)
        guard newTargetBps != currentTargetBps else { return }
        currentTargetBps = newTargetBps
        await applyTargetToStream(stream)
    }

    private func applyStepUp(stream: some HKStream) async {
        let proposedBps = Int(Double(currentTargetBps) * Self.stepUpFactor)
        let newTargetBps = min(proposedBps, mamimumVideoBitRate)
        guard newTargetBps != currentTargetBps else { return }
        currentTargetBps = newTargetBps
        await applyTargetToStream(stream)
    }

    private func applyTargetToStream(_ stream: some HKStream) async {
        var settings = await stream.videoSettings
        settings.bitRate = currentTargetBps
        await stream.setVideoSettings(settings)
    }
}
