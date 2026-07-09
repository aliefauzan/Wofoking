//
//  LevelSelectView.swift
//  Wofoking — Load Away
//
//  Level screen, restyled to the Figma "level" export: a split red/black
//  scene with a mirrored dead tree. Level 1 (left) is the entry — tapping
//  the "tap to start" caption drops the player straight into the game.
//  Level 2 (right) is baked as the perpetually "loading…" side, with a
//  random download percentage overlaid on the baked bar (re-rolled every
//  time the screen opens, like the old select screen). The heavy art is
//  baked into the `LevelBackground` imageset — same pipeline as the home
//  menu — with only the back button, the caption and the % drawn natively.
//

import SwiftUI

struct LevelSelectView: View {
    @Binding var path: [Route]

    @State private var captionPulse = false
    @State private var starting = false
    @State private var downloadPct = Int.random(in: 1...99)

    var body: some View {
        GeometryReader { geo in
            // Map art coordinates (874×402) through the .scaledToFill transform
            // so overlays lock to the baked art on any aspect (same math as HomeView).
            let s = max(geo.size.width / 874, geo.size.height / 402)
            let ox = (geo.size.width - 874 * s) / 2
            let oy = (geo.size.height - 402 * s) / 2

            ZStack {
                Image("LevelBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // Random download % on the Level 2 (right) side, sitting at the
                // left end of the baked loading bar — the perpetual-download joke.
                Text("\(downloadPct)%")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .position(x: ox + 600 * s, y: oy + 205 * s)

                // "tap to start" caption, bottom of the LEFT (Level 1) half.
                tapToStart
                    .position(x: geo.size.width * 0.25, y: geo.size.height * 0.85)

                // Left (Level 1) half is the start zone; the right (Level 2 /
                // "loading…") half stays inert.
                Color.clear
                    .frame(width: geo.size.width / 2, height: geo.size.height)
                    .contentShape(Rectangle())
                    .position(x: geo.size.width * 0.25, y: geo.size.height * 0.5)
                    .onTapGesture { startGame() }

                // Back to the home menu. Last in the ZStack so it wins the tap
                // over the left-half start zone it sits on top of.
                backButton
                    .position(x: ox + 44 * s, y: oy + 40 * s)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        // Menu backsound carries into the level screen. Reset `starting` here so
        // popping back from the camera scan doesn't leave the tap zone dead, and
        // re-roll the download % so it changes every time the screen opens.
        .onAppear {
            starting = false
            downloadPct = Int.random(in: 1...99)
            MenuAudioService.shared.startBackground()
        }
        .onDisappear { MenuAudioService.shared.stopBackground() }
    }

    private var backButton: some View {
        Button {
            if !path.isEmpty { path.removeLast() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.25), in: Circle())
        }
    }

    private var tapToStart: some View {
        Text("tap to start")
            .font(.system(size: 17, weight: .medium, design: .monospaced))
            .tracking(6)
            .foregroundStyle(.white)
            .opacity(captionPulse ? 1 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    captionPulse = true
                }
            }
    }

    private func startGame() {
        guard !starting else { return }
        starting = true
        // Fade the menu backsound as we drop into the game (L2 is the only
        // playable level — L1 is retired).
        MenuAudioService.shared.fadeOutBackground(duration: 0.6)
        path.append(.game(.two))
    }
}
