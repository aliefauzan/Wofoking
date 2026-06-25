//
//  ConfigService.swift
//  Wofoking — Load Away
//
//  Single source of truth for tunable thresholds. PRD §8.2 forbids
//  hardcoding gaze/timing values inside the engine — they live here.
//

import Foundation

final class ConfigService {
    static let shared = ConfigService()
    private init() {}

    // MARK: Gaze gating (PRD §8.2)

    /// Inner neutral cone (deg). Within this the head is clearly facing the
    /// screen. Kept for debug/telemetry; the look-away decision is gated by
    /// the wider `lookAway*ThresholdDeg` below — the gap between the two is the
    /// "peek" dead zone that counts as NOT looking away (bar stays paused).
    var lookYawThresholdDeg: Double = 18
    var lookPitchThresholdDeg: Double = 18

    /// Head must turn at least this far (deg) to the SIDE off the calibrated
    /// neutral before it counts as a real look-away. Well past the 18° neutral
    /// cone so a glance can't advance the bar, but kept inside TrueDepth's
    /// reliable tracking range (~45°) — beyond that the face half-occludes and
    /// reports faceLost instead of lookingAway, so a genuine turn never reads.
    /// No-peek is enforced by the eye-gaze guard below, not by a huge angle.
    var lookAwayYawThresholdDeg: Double = 40
    /// Up/down equivalent of the yaw away-gate (looking down also = no peek).
    var lookAwayPitchThresholdDeg: Double = 30
    /// Past this yaw the screen physically can't be seen → accept look-away
    /// regardless of the (noisy at large angles) eye-gaze peek guard.
    var hardLookAwayYawThresholdDeg: Double = 55

    /// Eye-gaze peek guard. Even with the head turned past the away-gate, if
    /// the eyes (ARFaceAnchor.lookAtPoint) are still aimed back at the screen
    /// the player is peeking → treated as looking AT the screen, no progress.
    var peekGuardEnabled = true
    /// Combined head+eye gaze within this many deg of the calibrated baseline
    /// is judged "eyes on screen" (peeking). Fails open: if device eye-gaze
    /// sign differs, the guard simply won't fire and the game stays playable.
    var eyeOnScreenToleranceDeg: Double = 22
    /// Eyes-closed gating. Closing BOTH eyes advances the bar (alt to looking
    /// away). Blind = can't peek, so this path needs no eye-gaze guard.
    var eyesClosedEnabled = true
    /// Both-eye blink blendShape (0..1, min of left/right) at/above this counts
    /// as eyes shut. Min = the MORE-OPEN eye, so a one-eye peek never registers.
    var eyeClosedThreshold: Double = 0.55
    /// Stable duration before a gaze state flips (anti-flicker / blink grace).
    /// Also separates a quick involuntary blink from an intentional eyes-shut.
    var debounceSeconds: TimeInterval = 0.30
    /// How long the locked face may be absent before we declare faceLost.
    var faceLostGraceSeconds: TimeInterval = 1.2
    /// Seconds of stable face required during calibration before lock.
    var calibrationStableSeconds: TimeInterval = 1.0
    /// Continuous look-at-screen time before the Give Up button reveals.
    var giveUpRevealSeconds: TimeInterval = 5.0

    // MARK: Per-level rules

    func rules(for level: Level) -> LevelRules {
        switch level {
        case .one:
            // 0→100% in ~15s of accumulated look-away (PRD FR-L1-3).
            return LevelRules(lives: 3,
                              baseFillPerSecond: 100.0 / 15.0,
                              unstable: false,
                              usesCheckpoints: false,
                              winWindow: 2.0)
        case .two:
            return LevelRules(lives: nil,            // no permanent loss
                              baseFillPerSecond: 100.0 / 22.0,
                              unstable: true,
                              usesCheckpoints: true,
                              winWindow: 2.0)
        case .three:
            // Never playable; values unused.
            return LevelRules(lives: nil,
                              baseFillPerSecond: 0,
                              unstable: true,
                              usesCheckpoints: false,
                              winWindow: 2.0)
        }
    }

    // MARK: Level 2 unstable tuning

    /// Random fill multiplier range applied per tick when `unstable`.
    var unstableFillRange: ClosedRange<Double> = 0.4...1.8
    /// Chance per tick the bar drops a little instead of rising (L2 taunt).
    var unstableDropChance: Double = 0.12
    /// % dropped on an unstable drop tick.
    var unstableDropAmount: ClosedRange<Double> = 3...9
    /// Heart-rate volatility multiplier when BPM is high (P2).
    var heartRateVolatilityBoost: Double = 1.5

    // MARK: Penalty

    /// % per second the bar falls during the over-loading penalty.
    var penaltyDropPerSecond: Double = 14
}
