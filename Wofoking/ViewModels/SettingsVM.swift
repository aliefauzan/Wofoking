//
//  SettingsVM.swift
//  Wofoking — Load Away
//
//  Settings bindings (PRD §10.7). HealthKit permission is only requested
//  when Heart Rate is enabled (FR-SET-4) — wired in P2.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class SettingsVM: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            PersistenceStore.shared.settings = settings
            VoiceService.shared.enabled = settings.voiceMockingEnabled
            if settings.heartRateEnabled != oldValue.heartRateEnabled {
                if settings.heartRateEnabled {
                    HeartRateService.shared.enable()    // requests HealthKit + asks watch to stream
                } else {
                    HeartRateService.shared.disable()
                }
            }
        }
    }

    init() { settings = PersistenceStore.shared.settings }

    var loc: Localization { Localization(language: settings.language) }
}
