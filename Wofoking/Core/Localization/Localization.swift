//
//  Localization.swift
//  Wofoking — Load Away
//
//  Lightweight in-code EN/ID localization (PRD §16, NFR-7). All UI copy
//  is translatable. Mocking copy lives in PhraseBank.
//

import Foundation

enum L10nKey: String {
    case start, level, deleteApp, settings, back, retry, continueGame
    case language, theme, heartRate, voiceMocking
    case deleteConfirmTitle, yes, no
    case faceLookAway, faceLookBack, faceCalibrating, faceLost, noFace
    case cameraDeniedTitle, cameraDeniedBody, openSettings
    case unsupportedDevice
    case lives, win, levelLocked
    case onboardTitle, onboardBody, grantCamera
    case giveUp, mainMenu
    case debug, debugFaceMesh, debugFaceMeshFooter
}

struct Localization {
    let language: AppLanguage

    func t(_ key: L10nKey) -> String {
        let table = language == .indonesian ? Self.id : Self.en
        return table[key] ?? Self.en[key] ?? key.rawValue
    }

    private static let en: [L10nKey: String] = [
        .start: "Start", .level: "Level", .deleteApp: "Delete App",
        .settings: "Settings", .back: "Back", .retry: "Retry",
        .continueGame: "Continue",
        .language: "Language", .theme: "Appearance",
        .heartRate: "Enable Heart Rate", .voiceMocking: "Voice Mocking",
        .deleteConfirmTitle: "Are you sure you want to delete Load Away?",
        .yes: "Yes", .no: "No",
        .faceLookAway: "Good. Now look away.",
        .faceLookBack: "Look back when it's 100%.",
        .faceCalibrating: "Hold still…",
        .faceLost: "Come back to the camera.",
        .noFace: "I can't annoy you if I can't see you.",
        .cameraDeniedTitle: "Camera Needed",
        .cameraDeniedBody: "Load Away uses your camera only to detect whether you are looking at the screen during gameplay. No face data is stored.",
        .openSettings: "Open Settings",
        .unsupportedDevice: "This device doesn't support face tracking.",
        .lives: "Lives", .win: "You won. Reluctantly.",
        .levelLocked: "Locked",
        .onboardTitle: "LOAD AWAY",
        .onboardBody: "A loading bar that hates being watched. Look away to make it load.",
        .grantCamera: "Allow Camera",
        .giveUp: "Give Up", .mainMenu: "Main Menu",
        .debug: "Debug",
        .debugFaceMesh: "Show Face Mesh",
        .debugFaceMeshFooter: "Overlays the live ARKit face mesh on your face during gameplay. Only on TrueDepth devices.",
    ]

    private static let id: [L10nKey: String] = [
        .start: "Mulai", .level: "Level", .deleteApp: "Hapus Aplikasi",
        .settings: "Pengaturan", .back: "Kembali", .retry: "Coba Lagi",
        .continueGame: "Lanjut",
        .language: "Bahasa", .theme: "Tampilan",
        .heartRate: "Aktifkan Detak Jantung", .voiceMocking: "Suara Ejekan",
        .deleteConfirmTitle: "Yakin mau menghapus Load Away?",
        .yes: "Ya", .no: "Tidak",
        .faceLookAway: "Bagus. Sekarang menoleh.",
        .faceLookBack: "Menoleh kembali saat 100%.",
        .faceCalibrating: "Diam dulu…",
        .faceLost: "Kembali ke kamera.",
        .noFace: "Aku tak bisa mengganggumu kalau tak melihatmu.",
        .cameraDeniedTitle: "Butuh Kamera",
        .cameraDeniedBody: "Load Away memakai kamera hanya untuk mendeteksi apakah kamu melihat layar saat bermain. Tidak ada data wajah yang disimpan.",
        .openSettings: "Buka Pengaturan",
        .unsupportedDevice: "Perangkat ini tidak mendukung face tracking.",
        .lives: "Nyawa", .win: "Kamu menang. Dengan berat hati.",
        .levelLocked: "Terkunci",
        .onboardTitle: "LOAD AWAY",
        .onboardBody: "Loading bar yang benci ditonton. Menoleh agar ia memuat.",
        .grantCamera: "Izinkan Kamera",
        .giveUp: "Menyerah", .mainMenu: "Menu Utama",
        .debug: "Debug",
        .debugFaceMesh: "Tampilkan Face Mesh",
        .debugFaceMeshFooter: "Menampilkan face mesh ARKit di wajahmu saat bermain. Hanya di perangkat TrueDepth.",
    ]
}
