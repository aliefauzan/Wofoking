//
//  StorylineView.swift
//  Wofoking — Load Away
//
//  Cinematic horror-satire intro shown after a stable face is detected and
//  before the loading gameplay begins (App Flow: Face Scan → Storyline →
//  Gameplay). Plays the bundled `0708.mp4` (a ~77 s dark-forest render with a
//  full horror soundscape — door slam, breathing, heartbeat, the "X" voice,
//  jumpscare, crying girl) full-screen, and overlays timed captions of the
//  spoken lines, hand-synced to the audio (start/end in `captions`, converted
//  from the video's SS:FF timecodes). The native `BedtimeStoryBackground` sits behind
//  the video as a fallback if the asset fails to load. There is no skip — the
//  player must watch the whole cinematic; it advances only when the video plays
//  to the end. No permissions, no face data — pure playback + text.
//
//  Playback is driven through SwiftUI `.onReceive` (a Combine ticker for
//  caption sync + the item-end publisher) rather than AVFoundation's
//  block-based observers: under this project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
//  MainActor`, those `@Sendable` blocks can't touch `@State` cleanly.
//

import SwiftUI
import Combine
import AVFoundation

struct StorylineView: View {
    let loc: Localization
    /// Called when the cinematic finishes (video ends, or the user skips).
    var onContinue: () -> Void

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var finished = false

    /// Polls playback ~10×/s to advance caption timing on the main run loop.
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var config: ConfigService { .shared }

    var body: some View {
        ZStack {
            // Fallback scene behind the video (shown if the asset is missing or
            // still loading) so the screen is never blank.
            BedtimeStoryBackground()

            if let player {
                VideoLayerView(player: player)
                    .ignoresSafeArea()
            }

            caption
        }
        // No skip button, no tap-to-skip — the player must watch the whole
        // cinematic; it only advances when the video plays to the end.
        .onReceive(ticker) { _ in tick() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem, item === player?.currentItem { advance() }
        }
        .onAppear { setup() }
        .onDisappear { teardown() }
    }

    // MARK: - Caption

    /// The caption whose window contains the current playback time, if any,
    /// cross-fading as the video moves between beats.
    private var caption: some View {
        let line = Self.captions.first { currentTime >= $0.start && currentTime < $0.end }?.text
        return VStack {
            Spacer()
            Group {
                if let line {
                    Text(line)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.9), radius: 6)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .id(line)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 64)
            .animation(.easeInOut(duration: config.storyCaptionFadeSeconds), value: line)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Playback

    private func setup() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "0708", withExtension: "mp4") else {
            // No asset → the fallback scene stays up; there's no video-end
            // notification coming, so continue after a beat rather than stall
            // the whole flow forever.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(config.storyAutoContinueSeconds * 1_000_000_000))
                advance()
            }
            return
        }
        let p = AVPlayer(url: url)
        p.actionAtItemEnd = .pause
        player = p
        p.play()
    }

    /// Caption sync off the main-loop ticker.
    private func tick() {
        guard let player, player.currentItem != nil else { return }
        let t = player.currentTime().seconds
        if t.isFinite { currentTime = t }
    }

    private func teardown() {
        player?.pause()
        player = nil
    }

    /// Idempotent: the end notification and the skip button can't both fire.
    private func advance() {
        guard !finished else { return }
        finished = true
        player?.pause()
        onContinue()
    }

    // MARK: - Caption track

    /// One caption per spoken line in `0708.mp4`, hand-timed to the audio.
    /// Start/end are in seconds, converted from the video's `SS:FF` timecodes
    /// (30 fps → frames/30). Gaps are intentional silence between lines.
    private struct Caption { let start: Double; let end: Double; let text: String }
    private static let captions: [Caption] = [
        Caption(start: 0.47,  end: 3.80,  text: "Hello?"),                       // 0:14–3:24
        Caption(start: 4.47,  end: 7.80,  text: "Where am I?"),                  // 4:14–7:24
        Caption(start: 8.30,  end: 9.27,  text: "Shit…"),                        // 8:09–9:08
        Caption(start: 9.40,  end: 10.87, text: "My flashlight—where is it?"),   // 9:12–10:26
        Caption(start: 15.93, end: 17.37, text: "What the FUCK…?"),              // 15:28–17:11
        Caption(start: 17.43, end: 19.07, text: "Who is there?!"),              // 17:13–19:02
        Caption(start: 20.67, end: 23.03, text: "Why doesn't it work?!!"),       // 20:20–23:01
        Caption(start: 28.03, end: 29.27, text: "SHIT!!"),                       // 28:01–29:08
        Caption(start: 29.83, end: 32.20, text: "Who are you!!"),                // 29:25–32:06
    ]
}

// MARK: - Video layer

/// Full-screen `AVPlayerLayer` with `.resizeAspectFill` (the video is 2346×1080
/// ≈ modern iPhone landscape, so fill crops almost nothing) and no transport
/// controls — a bare cinematic surface, unlike AVKit's `VideoPlayer`.
private struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
