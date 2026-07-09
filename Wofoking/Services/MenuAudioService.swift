//
//  MenuAudioService.swift
//  Wofoking — Load Away
//
//  Home-menu audio: a looping background track and the one-shot door-open
//  sound effect. Kept separate from VoiceService (which owns a single voice
//  player) so the backsound, the door SFX, and any voice taunt can overlap
//  without cutting each other. Clips live in Audio/Menu; a synced group may
//  flatten them to the bundle root, so we try the subdirectory then a flat
//  lookup — same pattern as VoiceService.
//
//  Session is .playback + .mixWithOthers: audio plays over the ringer/silent
//  switch (matching VoiceService, so the whole app is one consistent policy)
//  and never stomps other apps' audio. Silence it via the in-app `enabled`
//  gate, not the hardware switch.
//

import Foundation
import AVFoundation

final class MenuAudioService {
    static let shared = MenuAudioService()
    private init() {}

    // Separate retained players — an unretained AVAudioPlayer goes silent
    // mid-clip. Distinct players so the loop keeps running under the SFX.
    private var bgmPlayer: AVAudioPlayer?
    private var doorPlayer: AVAudioPlayer?
    private var splashPlayer: AVAudioPlayer?

    /// Muteable from Settings (same gate the voice/effects honour).
    var enabled: Bool = true

    private func clipURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio/Menu")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Background music

    /// Start (or restart) the looping menu backsound. Idempotent — a no-op if
    /// it's already playing so re-entering the menu doesn't restart the track.
    func startBackground() {
        guard enabled else { return }
        if bgmPlayer?.isPlaying == true { return }
        guard let url = clipURL("homepageFinal") else { return }
        activateSession()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1          // loop forever
            p.volume = 0.6
            bgmPlayer = p
            p.prepareToPlay()
            p.play()
        } catch {
            bgmPlayer = nil
        }
    }

    /// Fade the backsound out over `duration`, then stop. Used when the door
    /// opens and the scene rushes into the game.
    func fadeOutBackground(duration: TimeInterval = 0.8) {
        guard let p = bgmPlayer, p.isPlaying else { return }
        p.setVolume(0, fadeDuration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.bgmPlayer?.stop()
            self?.bgmPlayer = nil
        }
    }

    func stopBackground() {
        bgmPlayer?.stop()
        bgmPlayer = nil
    }

    // MARK: - Splash hum

    /// Start the looping electrical hum that plays under the warning splashes,
    /// from the first frame until the last warning is dismissed. Idempotent.
    func startSplashHum() {
        guard enabled else { return }
        if splashPlayer?.isPlaying == true { return }
        guard let url = clipURL("SplashHum") else { return }
        activateSession()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1          // loop under the whole splash sequence
            p.volume = 0.8
            splashPlayer = p
            p.prepareToPlay()
            p.play()
        } catch {
            splashPlayer = nil
        }
    }

    /// Fade the hum out, then stop — called as the last warning hands off to
    /// HomeView so the menu backsound comes in cleanly.
    func stopSplashHum(fadeDuration: TimeInterval = 0.4) {
        guard let p = splashPlayer else { return }
        p.setVolume(0, fadeDuration: fadeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak self] in
            self?.splashPlayer?.stop()
            self?.splashPlayer = nil
        }
    }

    // MARK: - Door SFX

    /// One-shot door-open sound, fired the instant the door starts swinging.
    func playDoorOpen() {
        guard enabled, let url = clipURL("doorOpen") else { return }
        activateSession()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            doorPlayer = p
            p.prepareToPlay()
            p.play()
        } catch {
            doorPlayer = nil
        }
    }
}
