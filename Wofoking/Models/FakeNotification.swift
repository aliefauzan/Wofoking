//
//  FakeNotification.swift
//  Wofoking — Load Away
//
//  A fake iOS-style push banner shown during gameplay. It has no real payload
//  and posts nothing to the system — it is a pure on-screen decoy that fires
//  while the player is looking AWAY, baiting them to glance back at the phone
//  (which pauses the bar and usually costs an early-look-back). Content is
//  deliberately mundane and believable so the lure works; the moment the
//  player turns to read it, they've already lost the tick.
//

import SwiftUI

struct FakeNotification: Identifiable, Equatable {
    let id = UUID()
    /// App name shown bold in the banner header (e.g. "Messages").
    let appName: String
    /// SF Symbol standing in for the app icon, on a tinted rounded square.
    let iconSystemName: String
    /// Icon background tint — picks the colour the real app uses so it reads
    /// as authentic at a glance.
    let tint: Color
    /// Notification title (bold, first line).
    let title: String
    /// Body preview (second line).
    let message: String
    /// Relative timestamp on the header, localized ("now" / "baru saja").
    let time: String
}

/// Bank of believable decoy notifications, localized EN/ID. Kept mundane on
/// purpose — a real-looking push is a far stronger lure than an obvious joke.
enum FakeNotificationBank {

    static func random(language: AppLanguage) -> FakeNotification {
        let now = language == .indonesian ? "baru saja" : "now"
        let bank = language == .indonesian ? id : en
        let t = bank.randomElement()!
        return FakeNotification(appName: t.app, iconSystemName: t.icon,
                                tint: t.tint, title: t.title, message: t.message,
                                time: now)
    }

    private typealias Row = (app: String, icon: String, tint: Color,
                             title: String, message: String)

    private static let en: [Row] = [
        ("Messages", "message.fill", .green, "Mom", "Are you home? Call me when you can."),
        ("Messages", "message.fill", .green, "Unknown", "hey are you free rn?"),
        ("WhatsApp", "phone.fill", .green, "Family group", "3 new messages"),
        ("Instagram", "camera.fill", .pink, "instagram", "someone you know just posted for the first time in a while"),
        ("Mail", "envelope.fill", .blue, "1 New Message", "Re: your order has shipped"),
        ("Bank", "creditcard.fill", .indigo, "Transaction Alert", "A payment was made on your card. Tap to review."),
        ("Photos", "photo.fill", .orange, "On This Day", "Look back on this memory from 2 years ago"),
        ("Calendar", "calendar", .red, "In 10 minutes", "Meeting — you said you'd be there"),
        ("Load Away", "hourglass", .purple, "Almost done", "Your bar is at 99%. Come take a look 👀"),
        ("Phone", "phone.fill", .green, "Missed Call", "1 missed call — tap to call back"),
        ("Wallet", "wallet.pass.fill", .black, "Payment Received", "You received money. See details."),
    ]

    private static let id: [Row] = [
        ("Pesan", "message.fill", .green, "Ibu", "Kamu di rumah? Telepon ibu ya."),
        ("Pesan", "message.fill", .green, "Tidak dikenal", "halo lagi sibuk gak?"),
        ("WhatsApp", "phone.fill", .green, "Grup Keluarga", "3 pesan baru"),
        ("Instagram", "camera.fill", .pink, "instagram", "seseorang yang kamu kenal baru saja posting"),
        ("Email", "envelope.fill", .blue, "1 Pesan Baru", "Re: pesananmu sudah dikirim"),
        ("Bank", "creditcard.fill", .indigo, "Notifikasi Transaksi", "Ada transaksi di kartumu. Ketuk untuk cek."),
        ("Foto", "photo.fill", .orange, "Kenangan Hari Ini", "Lihat kenangan dari 2 tahun lalu"),
        ("Kalender", "calendar", .red, "10 menit lagi", "Rapat — katanya kamu mau datang"),
        ("Load Away", "hourglass", .purple, "Hampir selesai", "Bar-mu sudah 99%. Sini lihat 👀"),
        ("Telepon", "phone.fill", .green, "Panggilan Tak Terjawab", "1 panggilan tak terjawab — ketuk untuk telepon balik"),
        ("Dompet", "wallet.pass.fill", .black, "Uang Masuk", "Kamu menerima uang. Lihat detail."),
    ]
}
