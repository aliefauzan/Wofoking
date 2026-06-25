//
//  PersistenceStore.swift
//  Wofoking — Load Away
//
//  Local persistence: unlocked levels, last level, settings (PRD §12.3, NFR-5).
//  No face/biometric data is ever stored (NFR-4).
//

import Foundation
import Combine

final class PersistenceStore: ObservableObject {
    static let shared = PersistenceStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let unlocked = "la.unlockedLevels"
        static let lastLevel = "la.lastLevel"
        static let settings = "la.settings"
        static let hasOnboarded = "la.hasOnboarded"
    }

    @Published private(set) var unlockedLevels: Set<Int>
    @Published var settings: AppSettings { didSet { saveSettings() } }

    private init() {
        // Level 1 always unlocked (FR-LVL-1).
        if let raw = defaults.array(forKey: Key.unlocked) as? [Int], !raw.isEmpty {
            unlockedLevels = Set(raw)
        } else {
            unlockedLevels = [Level.one.rawValue]
        }
        if let data = defaults.data(forKey: Key.settings),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    // MARK: Unlocks

    func isUnlocked(_ level: Level) -> Bool {
        level == .one || unlockedLevels.contains(level.rawValue)
    }

    func unlock(_ level: Level) {
        guard level.isPlayable else { return }
        unlockedLevels.insert(level.rawValue)
        defaults.set(Array(unlockedLevels), forKey: Key.unlocked)
    }

    /// Fake "Delete App" reset → bounce player back to Level 1 (PRD §12.3).
    func resetToLevelOne() {
        lastLevel = .one
    }

    // MARK: Last level

    var lastLevel: Level {
        get { Level(rawValue: defaults.integer(forKey: Key.lastLevel)) ?? .one }
        set { defaults.set(newValue.rawValue, forKey: Key.lastLevel) }
    }

    // MARK: Onboarding

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    // MARK: Settings

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Key.settings)
        }
    }
}
