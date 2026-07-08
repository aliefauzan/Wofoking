//
//  SplashSequenceView.swift
//  Wofoking — Load Away
//
//  Pre-home warning splashes shown on every app open, in order:
//  Headphones → Flash warning → Flash warning 2 → HomeView.
//  Each frame is a baked 874×402 Figma export (black bg + grain), shown
//  full-screen. Auto-advances on a timer; a tap skips to the next frame.
//

import SwiftUI

struct SplashSequenceView: View {
    /// Called once the last frame is dismissed — hands control to HomeView.
    let onFinished: () -> Void

    /// Ordered splash art + how long each stays before auto-advancing.
    private struct Frame {
        let asset: String
        let seconds: Double
    }
    private let frames: [Frame] = [
        Frame(asset: "SplashHeadphones", seconds: 3.5),
        Frame(asset: "SplashFlashWarning", seconds: 4.5),
        Frame(asset: "SplashFlashWarning2", seconds: 4.5),
    ]

    @State private var index = 0
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(frames[index].asset)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .id(index) // force a fresh view per frame so the transition fires
                .transition(.opacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .animation(.easeInOut(duration: 0.35), value: index)
        .onAppear {
            MenuAudioService.shared.startSplashHum()
            scheduleAdvance()
        }
        .onDisappear {
            advanceTask?.cancel()
            MenuAudioService.shared.stopSplashHum()
        }
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        let wait = frames[index].seconds
        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
        advanceTask?.cancel()
        if index + 1 < frames.count {
            index += 1
            scheduleAdvance()
        } else {
            MenuAudioService.shared.stopSplashHum()
            onFinished()
        }
    }
}

#Preview { SplashSequenceView(onFinished: {}) }
