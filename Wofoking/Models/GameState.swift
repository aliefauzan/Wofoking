//
//  GameState.swift
//  Wofoking — Load Away
//
//  App + gameplay state machine. Mirrors PRD §11 and the
//  "Gameplay State Machine" diagram.
//

import Foundation

/// High-level gameplay states driven by `GameEngine`.
enum GameState: Equatable {
    case idle
    case requestingPermission
    case faceCalibration
    case noFace
    case faceDetected
    case locked            // active player's face captured as anchor
    case lookingAtScreen   // bar paused
    case lookingAway       // bar advances
    case reached100        // 2s win window open
    case win
    case fail              // wrong-time look-back
    case overLoadPenalty   // stayed away past 100% → bar drops
    case retry             // lives exhausted (L1)
    case levelCompleted
    case faceLost          // safe pause, not a win
    case gaveUp            // player tapped Give Up → mock + main menu
}

/// Real-time gaze classification from `GazeTracker`.
enum GazeState: Equatable {
    case noFace
    case lookingAtScreen
    case lookingAway
    case eyesClosed   // both eyes shut → bar advances (can't peek blind)
    case faceLost     // locked player left frame too long
}
