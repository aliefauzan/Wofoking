//
//  AppSettings.swift
//  Wofoking — Load Away
//
//  User-facing settings (PRD §10.7). Persisted by PersistenceStore.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case indonesian = "id"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .english:    return "English"
        case .indonesian: return "Indonesia"
        }
    }
}

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System Default"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

struct AppSettings: Codable, Equatable {
    var language: AppLanguage
    var theme: AppTheme
    var heartRateEnabled: Bool
    var voiceMockingEnabled: Bool
    /// Debug: overlay the live ARKit face mesh during gameplay.
    var debugFaceMesh: Bool

    init(language: AppLanguage, theme: AppTheme,
         heartRateEnabled: Bool, voiceMockingEnabled: Bool,
         debugFaceMesh: Bool = false) {
        self.language = language
        self.theme = theme
        self.heartRateEnabled = heartRateEnabled
        self.voiceMockingEnabled = voiceMockingEnabled
        self.debugFaceMesh = debugFaceMesh
    }

    // Default-tolerant decode so adding new fields never wipes saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? d.language
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? d.theme
        heartRateEnabled = try c.decodeIfPresent(Bool.self, forKey: .heartRateEnabled) ?? d.heartRateEnabled
        voiceMockingEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceMockingEnabled) ?? d.voiceMockingEnabled
        debugFaceMesh = try c.decodeIfPresent(Bool.self, forKey: .debugFaceMesh) ?? false
    }

    static var `default`: AppSettings {
        let deviceLang = Locale.current.language.languageCode?.identifier == "id"
            ? AppLanguage.indonesian : .english
        return AppSettings(language: deviceLang,
                           theme: .system,
                           heartRateEnabled: false,
                           voiceMockingEnabled: true)
    }
}
