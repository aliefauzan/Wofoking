//
//  LevelVM.swift
//  Wofoking — Load Away
//
//  Level Select logic (PRD §10.2, §10.6). L3 is the fake "always loading"
//  level whose percentage is re-randomised every time the screen opens.
//

import Foundation
import SwiftUI
import Combine

struct LevelRow: Identifiable {
    var id: Int { level.rawValue }
    let level: Level
    let unlocked: Bool
    let fakePercent: Int?   // only L3
}

@MainActor
final class LevelVM: ObservableObject {
    @Published private(set) var rows: [LevelRow] = []
    @Published var jokeMessage: String?

    private let store = PersistenceStore.shared

    func refresh() {
        rows = Level.allCases.map { level in
            LevelRow(level: level,
                     unlocked: store.isUnlocked(level),
                     fakePercent: level == .three ? Int.random(in: 1...99) : nil)
        }
    }

    /// Tapping L3 only ever shows a joke (FR-L3-3).
    func tapLevelThree() {
        jokeMessage = PhraseBank.line(.level3Tap)
    }
}
