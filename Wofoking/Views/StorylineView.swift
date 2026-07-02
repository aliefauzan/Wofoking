//
//  StorylineView.swift
//  Wofoking — Load Away
//
//  Static horror-satire intro shown after a stable face is detected and before
//  the loading gameplay begins (App Flow: Face Scan → Storyline → Gameplay).
//  Lines reveal one-by-one, then it auto-continues; a Continue button is always
//  available so navigation never depends on the animation finishing (stability
//  over polish). No permissions, no face data — pure text.
//

import SwiftUI

struct StorylineView: View {
    let loc: Localization
    /// Called when the story is done (auto after the last line, or on tap).
    var onContinue: () -> Void

    @State private var visibleCount = 0
    @State private var finished = false

    private var lines: [String] { loc.storyLines }
    private var config: ConfigService { .shared }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ForEach(0..<visibleCount, id: \.self) { i in
                Text(lines[i])
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Spacer()

            if visibleCount >= lines.count {
                Button(loc.t(.continueGame)) { advance() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25)))
                    .transition(.opacity)
                    .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 48)
        .animation(.easeInOut(duration: 0.4), value: visibleCount)
        .task { await reveal() }
    }

    private func reveal() async {
        for i in 0..<lines.count {
            visibleCount = i + 1
            try? await Task.sleep(nanoseconds: UInt64(config.storyLineInterval * 1_000_000_000))
        }
        try? await Task.sleep(nanoseconds: UInt64(config.storyAutoContinueSeconds * 1_000_000_000))
        advance()
    }

    /// Idempotent: auto-continue and the button can't both fire onContinue.
    private func advance() {
        guard !finished else { return }
        finished = true
        onContinue()
    }
}
