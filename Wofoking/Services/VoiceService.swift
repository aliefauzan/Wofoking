//
//  VoiceService.swift
//  Wofoking — Load Away
//
//  Voice taunts (Use Case "Voice Mocking"). Primary voice = pre-generated
//  "Tes voice" (Voicebox) clips bundled in Audio/Tes; each static PhraseBank
//  line has a clip keyed by sha256(text), so playback is instant and on-device
//  (the device can't reach the Mac's Voicebox engine at runtime). Any line
//  without a clip — a Foundation Models refinement, or Indonesian, which has no
//  Tes clips — falls back to AVSpeechSynthesizer so nothing is ever fully silent.
//  Uses the .playback category so taunts are audible even when the ringer/silent
//  switch is on (voice mocking is the core gag) — muting is the in-app setting
//  (`enabled`), not the hardware switch. .mixWithOthers keeps other apps' audio.
//

import Foundation
import AVFoundation
import CryptoKit

final class VoiceService {
    static let shared = VoiceService()
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?   // retained — an unretained player goes silent mid-clip

    private init() {
        // .playback so voice taunts sound even with the silent switch on, +
        // .mixWithOthers so other apps' audio keeps playing under us. Configured
        // ONCE — re-activating the session on every utterance hitched the main
        // thread (the same thread as the 30 Hz game tick). The app also sets
        // this at launch (WofokingApp) so the session is deterministic before
        // any subsystem plays; this is a redundant, idempotent reinforcement.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Muteable from Settings (PRD: voiceMockingEnabled).
    var enabled: Bool = true

    /// Bundled-clip key for a phrase. MUST match scripts/generate_tes_voice.py:
    /// `"tes_" + sha256(text_utf8).hexdigest()[:16]`.
    static func clipKey(for text: String) -> String {
        let hex = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "tes_" + String(hex.prefix(16))
    }

    func speak(_ text: String, language: AppLanguage) {
        guard enabled, !text.isEmpty else { return }
        if let url = clipURL(for: text), playClip(at: url) {
            return
        }
        speakWithSynthesizer(text, language: language)
    }

    // MARK: - Tes voice clips

    private func clipURL(for text: String) -> URL? {
        let key = Self.clipKey(for: text)
        // Synced groups may bundle the WAVs under Audio/Tes or flattened into the
        // bundle root — try the subdirectory first, then a flat lookup.
        return Bundle.main.url(forResource: key, withExtension: "wav", subdirectory: "Audio/Tes")
            ?? Bundle.main.url(forResource: key, withExtension: "wav")
    }

    @discardableResult
    private func playClip(at url: URL) -> Bool {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            player = p
            p.prepareToPlay()
            return p.play()
        } catch {
            return false
        }
    }

    // MARK: - Fallback

    private func speakWithSynthesizer(_ text: String, language: AppLanguage) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language == .indonesian ? "id-ID" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
