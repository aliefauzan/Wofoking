//
//  LoadingController.swift
//  Wofoking — Load Away
//
//  Owns the loading-bar value and its per-level math: constant vs unstable
//  fill, checkpoints, random fair-jitter, and the over-loading drop
//  (PRD §10.4-§10.5, Use Cases "Level-Based Loading Rate", "Over-Loading Penalty").
//

import Foundation

final class LoadingController {
    private let config = ConfigService.shared

    private(set) var progress: Double = 0      // 0...100
    private(set) var lastCheckpoint: Double = 0

    /// P2: when the player's heart rate is elevated, L2 gets more volatile.
    var heartRateHigh = false

    func reset() {
        progress = 0
        lastCheckpoint = 0
    }

    /// Advance the bar for `dt` seconds of look-away time.
    func advance(_ dt: TimeInterval, rules: LevelRules) {
        guard progress < 100 else { return }
        var delta = rules.baseFillPerSecond * dt
        if rules.unstable {
            let volatility = heartRateHigh ? config.heartRateVolatilityBoost : 1.0
            // Drop chance is per-SECOND, scaled to this tick so it is frame-rate
            // independent (the per-tick form fired every frame and stalled the bar).
            if Double.random(in: 0...1) < config.unstableDropChance * dt {
                // Taunting dip (L2 can decrease) — a RATE (%/s) scaled by dt,
                // matching the fill, so it no longer overpowers it.
                delta = -Double.random(in: config.unstableDropAmount) * volatility * dt
            } else {
                let mult = Double.random(in: config.unstableFillRange) * volatility
                delta *= mult
            }
        }
        progress = min(100, max(0, progress + delta))
    }

    /// Startup intro: a plain, gaze-independent loading ramp toward `target`,
    /// paced to reach it after `seconds` of grace, so the opening reads as a
    /// genuine loading bar before the real look-away mechanic takes over.
    func fakeLoad(_ dt: TimeInterval, to target: Double, over seconds: TimeInterval) {
        guard seconds > 0 else { progress = target; return }
        progress = min(target, progress + (target / seconds) * dt)
        lastCheckpoint = progress
    }

    // MARK: Fake-out (L2 rage bait)

    /// Pin the bar to the cusp of completion for a dramatic "you made it!" beat.
    func freezeNearComplete() { progress = 99 }

    /// Betrayal: yank the bar back down after the fake-out freeze.
    func fakeDrop(to value: Double) {
        progress = max(0, min(progress, value))
        lastCheckpoint = min(lastCheckpoint, progress)
    }

    /// Punitive drop when the player is caught peeking.
    func applyPeekTax(_ amount: Double) {
        progress = max(0, progress - amount)
        lastCheckpoint = min(lastCheckpoint, progress)
    }

    /// Bar falls during the over-loading penalty (rendered when player looks back).
    func dropPenalty(_ dt: TimeInterval) {
        progress = max(lastCheckpoint, progress - config.penaltyDropPerSecond * dt)
    }

    /// Record progress as a checkpoint on look-away (L2 only).
    func makeCheckpoint() {
        lastCheckpoint = progress
    }

    /// Snap back after a failed L2 window: random point between the checkpoint
    /// and CURRENT progress. Capped at the current value — the old random-to-99
    /// could move the bar UP on a fail, making missing the window profitable.
    func snapBackToCheckpoint() {
        let upper = max(lastCheckpoint, min(progress, 99))
        progress = Double.random(in: lastCheckpoint...upper).rounded()
    }

    var isComplete: Bool { progress >= 100 }
}
