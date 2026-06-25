//
//  VoiceService.swift
//  Wofoking — Load Away
//
//  On-device TTS taunts (Use Case "Voice Mocking"). MVP = AVSpeechSynthesizer
//  reading the static bank. Respects the mute setting; honours silent switch.
//

import Foundation
import AVFoundation

final class VoiceService {
    static let shared = VoiceService()
    private let synthesizer = AVSpeechSynthesizer()
    private init() {}

    /// Muteable from Settings (PRD: voiceMockingEnabled).
    var enabled: Bool = true

    func speak(_ text: String, language: AppLanguage) {
        guard enabled, !text.isEmpty else { return }
        // Mix politely with other audio; respects the ringer/silent switch
        // because we don't override the ambient category.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language == .indonesian ? "id-ID" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
