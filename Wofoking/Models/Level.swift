//
//  Level.swift
//  Wofoking — Load Away
//
//  Level identity + per-level loading rules. See PRD §10.4-§10.6.
//

import Foundation

/// The three levels. L3 is a meta-joke that never completes.
enum Level: Int, CaseIterable, Identifiable, Codable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .one:   return "Level 1"
        case .two:   return "Level 2"
        case .three: return "Level 3"
        }
    }

    var subtitle: String {
        switch self {
        case .one:   return "Basic Loading"
        case .two:   return "Unstable Loading"
        case .three: return "The Impossible Level"
        }
    }

    /// Only L2 is playable: L1 is retired (play starts straight at Unstable
    /// Loading) and L3 is the meta-joke that never completes.
    var isPlayable: Bool { self == .two }
}

/// Tunable per-level behaviour. Values come from `ConfigService` so nothing
/// is hardcoded in the engine (PRD §8.2 requires these to be calibratable).
struct LevelRules {
    /// Lives shown in UI. `nil` = unlimited (Level 2 has no permanent loss).
    let lives: Int?
    /// Base fill % per second of accumulated look-away time.
    let baseFillPerSecond: Double
    /// If true, fill rate jitters randomly each tick (Level 2).
    let unstable: Bool
    /// If true, look-away creates checkpoints the bar can snap back to.
    let usesCheckpoints: Bool
    /// Seconds the bar holds at 100% before the over-loading penalty.
    let winWindow: TimeInterval
}
