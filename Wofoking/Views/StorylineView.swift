//
//  StorylineView.swift
//  Wofoking — Load Away
//
//  Static horror-satire intro shown after a stable face is detected and before
//  the loading gameplay begins (App Flow: Face Scan → Storyline → Gameplay).
//  Sits on the home-menu forest theme (ForestMenuBackground) so the story reads
//  as part of the same haunted world. One sentence per "page": each line types
//  out like a typewriter, holds, then the page cross-fades to the next sentence
//  — sentences never stack or overwrite. A Continue button is always available
//  so navigation never depends on the animation finishing (stability over
//  polish). No permissions, no face data — pure text.
//

import SwiftUI

struct StorylineView: View {
    let loc: Localization
    /// Called when the story is done (auto after the last line, or on tap).
    var onContinue: () -> Void

    @State private var pageIndex = 0     // which sentence is on screen
    @State private var typed = ""        // portion of the current sentence typed so far
    @State private var typing = false    // cursor shows while a page is live
    @State private var showContinue = false
    @State private var finished = false

    private var lines: [String] { loc.storyLines }
    private var config: ConfigService { .shared }

    var body: some View {
        ZStack {
            // Plain black storyline background.
            Color.black.ignoresSafeArea()

            // Exactly one sentence, centered on screen. `.id(pageIndex)` gives
            // each page its own identity so the old sentence fades OUT and the
            // new one fades IN — they never overlap or stack.
            currentPage
                .id(pageIndex)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .offset(y: -14))))
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.smooth(duration: config.storyPageFadeSeconds), value: pageIndex)
        }
        .overlay(alignment: .bottom) {
            if showContinue {
                Button(loc.t(.continueGame)) { advance() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25)))
                    .transition(.opacity)
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.5), value: showContinue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if showContinue { advance() } }
        .task { await reveal() }
    }

    // MARK: Page

    /// The current sentence with a blinking typewriter cursor.
    private var currentPage: some View {
        TimelineView(.animation) { tl in
            let blink = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            (Text(typed).foregroundColor(.white)
             + Text(typing && blink ? "▌" : " ")
                .foregroundColor(.white.opacity(0.8)))
                .font(.system(.title2, design: .serif))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.7), radius: 6)
        }
    }

    // MARK: Reveal

    private func reveal() async {
        for i in 0..<lines.count {
            // Turn the page: swap identity (old sentence fades out) and start empty.
            pageIndex = i
            typed = ""
            typing = true
            // Let the cross-fade settle before typing the new sentence in.
            try? await Task.sleep(nanoseconds: nanos(config.storyPageFadeSeconds))

            // Typewriter: reveal one character at a time.
            for ch in lines[i] {
                typed.append(ch)
                try? await Task.sleep(nanoseconds: nanos(config.storyTypeCharSeconds))
            }

            // Hold the finished sentence so it can be read before the page turns.
            try? await Task.sleep(nanoseconds: nanos(config.storyLineInterval))
        }

        typing = false
        showContinue = true
        try? await Task.sleep(nanoseconds: nanos(config.storyAutoContinueSeconds))
        advance()
    }

    private func nanos(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// Idempotent: auto-continue and the button can't both fire onContinue.
    private func advance() {
        guard !finished else { return }
        finished = true
        onContinue()
    }
}
