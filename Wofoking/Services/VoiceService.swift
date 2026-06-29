//
//  VoiceService.swift
//  Wofoking — Load Away
//
//  Mocking-taunt audio (Use Case "Voice Mocking"). Prefers a pre-baked
//  ElevenLabs clip bundled as <slug>.mp3 in the "Taunts" resource folder;
//  falls back to on-device AVSpeechSynthesizer when no clip matches the exact
//  line (dynamic Foundation Models lines, or unbaked languages). Respects the
//  mute setting and the ringer/silent switch (ambient category, no override).
//

import Foundation
import AVFoundation

final class VoiceService: NSObject {
    static let shared = VoiceService()
    private let synthesizer = AVSpeechSynthesizer()
    /// Held strong so playback isn't cut off by deallocation.
    private var player: AVAudioPlayer?
    private override init() { super.init() }

    /// Muteable from Settings (PRD: voiceMockingEnabled).
    var enabled: Bool = true

    func speak(_ text: String, language: AppLanguage) {
        guard enabled, !text.isEmpty else { return }
        // Mix politely with other audio; respects the ringer/silent switch
        // because we don't override the ambient category.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        if let url = Self.clipURL(for: text, language: language), playClip(url) {
            return
        }
        speakSynthesized(text, language: language)
    }

    // MARK: - Pre-baked clip

    /// Locates a bundled ElevenLabs clip for an exact line, if one was baked.
    /// Naming: "<lang>_<slug>.mp3" inside the "Taunts" folder reference.
    private static func clipURL(for text: String, language: AppLanguage) -> URL? {
        let name = "\(language.rawValue)_\(slug(text))"
        return Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Taunts")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3")
    }

    /// Stable filename slug for a line: lowercase ASCII, punctuation dropped,
    /// runs of non-alphanumerics collapsed to a single underscore. Must match
    /// the generation script's slug() exactly.
    static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        var out = ""
        var lastWasSep = false
        for ch in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) && ch.isASCII {
                out.unicodeScalars.append(ch)
                lastWasSep = false
            } else if !lastWasSep {
                out.append("_")
                lastWasSep = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func playClip(_ url: URL) -> Bool {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            player = p
            p.prepareToPlay()
            return p.play()
        } catch {
            return false
        }
    }

    // MARK: - TTS fallback

    private func speakSynthesized(_ text: String, language: AppLanguage) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language == .indonesian ? "id-ID" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
