//
//  JumpscareService.swift
//  Wofoking — Load Away
//
//  The endgame gotcha: the instant the player "wins" (bar hits 100% / the win
//  window resolves) they get a full-screen jumpscare face + scream, then a
//  parting insult, then they're kicked back to the main menu. This owns the
//  two-clip audio chain; JumpscareView owns the image and the routing.
//
//  Clips live in Audio/ (jumpscare.wav → jumpscareOutro.wav). A synced group
//  may flatten them to the bundle root, so we try the subdirectory then a flat
//  lookup — same pattern as VoiceService / MenuAudioService.
//
//  Deliberately NOT gated by the voice-mocking `enabled` setting: the jumpscare
//  is the payoff of the whole troll, not a taunt you can mute. Uses .playback
//  so the scream lands even with the silent switch on (matches the app's audio
//  policy) — but does NOT set .mixWithOthers, so it briefly owns the output for
//  maximum effect, then the completion hand-off restores the menu audio.
//

import Foundation
import AVFoundation

final class JumpscareService: NSObject, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?     // retained — an unretained player goes silent mid-clip
    private var onFinished: (() -> Void)?

    private func clipURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
    }

    /// Play the scream, then the parting insult, then call `completion`. If a
    /// clip is missing the chain still advances (via a timed fallback) so the
    /// player is never stranded on the jumpscare screen.
    func run(completion: @escaping () -> Void) {
        onFinished = completion
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        playScream()
    }

    private func playScream() {
        guard play("jumpscare") else {
            // No scream clip — hold the face a beat, then go to the outro.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.playOutro()
            }
            return
        }
    }

    private func playOutro() {
        guard play("jumpscareOutro") else {
            finish()
            return
        }
    }

    private func finish() {
        player?.stop()
        player = nil
        let cb = onFinished
        onFinished = nil
        cb?()
    }

    /// Start a clip. Returns false (so the caller can fall back) if it can't load.
    private func play(_ name: String) -> Bool {
        guard let url = clipURL(name) else { return false }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = 1.0
            player = p
            p.prepareToPlay()
            return p.play()
        } catch {
            player = nil
            return false
        }
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        // Advance the chain on the main actor: scream → outro → done.
        Task { @MainActor [weak self] in
            guard let self, p === self.player else { return }
            // Which clip just ended? If it was the scream, roll the outro;
            // otherwise the outro finished → hand back to the view.
            if self.isScream { self.playOutro() } else { self.finish() }
        }
    }

    /// True while the currently-loaded clip is the scream (vs the outro).
    private var isScream: Bool {
        player?.url?.lastPathComponent == "jumpscare.wav"
    }
}
