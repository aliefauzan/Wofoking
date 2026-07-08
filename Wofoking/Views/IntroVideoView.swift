//
//  IntroVideoView.swift
//  Wofoking — Load Away
//
//  Full-screen intro animation shown after the storyline and before the
//  loading gameplay begins (App Flow: Face Scan → Storyline → Intro Video →
//  Gameplay). Plays the pre-rendered "ANIMATION WXH BENER" clip (a 16 s
//  forest → logo reveal, the SVG's rendered form) once, edge-to-edge, then
//  hands control back via `onFinish`.
//
//  Robustness over polish (mirrors StorylineView): the clip is muted, plays on
//  the `.ambient` mix so it never ducks other audio, and tapping anywhere skips
//  straight to gameplay — navigation never depends on playback completing. If
//  the asset is missing we finish immediately rather than dead-ending.
//

import SwiftUI
import AVFoundation
import Combine

struct IntroVideoView: View {
    /// Called when the clip finishes, on tap-to-skip, or if the asset is absent.
    var onFinish: () -> Void

    @StateObject private var player = IntroPlayer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let avPlayer = player.avPlayer {
                IntroPlayerLayer(player: avPlayer)
                    .ignoresSafeArea()
            }

            // Invisible skip layer over the whole screen.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { finishOnce() }
        }
        .onAppear {
            player.onEnd = { finishOnce() }
            if !player.load(resource: "IntroAnimation", ext: "mp4") {
                finishOnce()          // no asset → don't dead-end the flow
            } else {
                player.play()
            }
        }
        .onDisappear { player.stop() }
    }

    @State private var didFinish = false
    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        player.stop()
        onFinish()
    }
}

/// Owns the `AVPlayer`, wires the end-of-clip notification, and finds the asset
/// whether the synced group kept the `Video/` subfolder or flattened it to the
/// bundle root (same lookup strategy as `VoiceService`).
final class IntroPlayer: ObservableObject {
    @Published private(set) var avPlayer: AVPlayer?
    var onEnd: (() -> Void)?

    private var endObserver: NSObjectProtocol?

    @discardableResult
    func load(resource: String, ext: String) -> Bool {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Video")
            ?? Bundle.main.url(forResource: resource, withExtension: ext)
        else { return false }

        // `.ambient` + mixWithOthers so the muted clip never interrupts the
        // Tes voice / system audio (matches VoiceService's session policy).
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.actionAtItemEnd = .pause
        avPlayer = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onEnd?()
        }
        return true
    }

    func play() { avPlayer?.play() }

    func stop() {
        avPlayer?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    deinit { if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }
}

/// Bare `AVPlayerLayer` host — no transport controls (unlike `VideoPlayer`),
/// `resizeAspectFill` so the 874×402 landscape clip covers the screen.
private struct IntroPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
