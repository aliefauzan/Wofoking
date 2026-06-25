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
            if Double.random(in: 0...1) < config.unstableDropChance {
                // Taunting dip (L2 can decrease).
                delta = -Double.random(in: config.unstableDropAmount) * volatility
            } else {
                let mult = Double.random(in: config.unstableFillRange) * volatility
                delta *= mult
            }
        }
        progress = min(100, max(0, progress + delta))
    }

    /// Bar falls during the over-loading penalty (rendered when player looks back).
    func dropPenalty(_ dt: TimeInterval) {
        progress = max(lastCheckpoint, progress - config.penaltyDropPerSecond * dt)
    }

    /// Record progress as a checkpoint on look-away (L2 only).
    func makeCheckpoint() {
        lastCheckpoint = progress
    }

    /// Snap back after a failed L2 window: random point between checkpoint and 99.
    func snapBackToCheckpoint() {
        let upper = max(lastCheckpoint, 99)
        progress = Double.random(in: lastCheckpoint...upper).rounded()
    }

    var isComplete: Bool { progress >= 100 }
}
