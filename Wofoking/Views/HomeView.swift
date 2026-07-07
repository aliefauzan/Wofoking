//
//  HomeView.swift
//  Wofoking — Load Away
//
//  Home screen (PRD §10.1), restyled to the Figma "PINTU KEBUKA" export:
//  haunted-forest scene with a glowing red door center stage, LEVEL / DELETE
//  capsule buttons, and "tap to start" — tapping anywhere swings the door
//  open and enters the game. Settings moved to a corner gear.
//

import SwiftUI

struct HomeView: View {
    @Binding var path: [Route]
    @EnvironmentObject private var store: PersistenceStore
    @State private var showDelete = false
    @State private var doorOpen = false
    @State private var rushing = false
    @State private var captionPulse = false
    @State private var showSettings = false

    private var loc: Localization { Localization(language: store.settings.language) }

    var body: some View {
        GeometryReader { geo in
            // Where the doorway sits on screen — the vanishing point of the
            // hyperspeed rush (slightly inside the opening, past the panel).
            let s = max(geo.size.width / 874, geo.size.height / 402)
            let ox = (geo.size.width - 874 * s) / 2
            let oy = (geo.size.height - 402 * s) / 2
            let doorAnchor = UnitPoint(
                x: (ox + 437 * s) / geo.size.width,
                y: (oy + 197.5 * s) / geo.size.height)

            ZStack {
                ForestMenuBackground()

                doorway(in: geo.size)

                // Front mist, jagged ground, grain and logo — over the door,
                // matching the export's z-order.
                ForestMenuForeground()

                VStack(spacing: 0) {
                    Spacer()
                    menuRow
                    tapToStart
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            // Hyperspeed dive: the whole scene blasts THROUGH the open doorway.
            // A hard-accelerating zoom anchored at the opening, plus a forward
            // 3D tilt (perspective plunge) so it reads as diving into the dark
            // interior rather than a flat magnification. Speed blur ramps up.
            .scaleEffect(rushing ? 26 : 1, anchor: doorAnchor)
            .rotation3DEffect(
                .degrees(rushing ? 11 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: doorAnchor,
                perspective: 0.7)
            .blur(radius: rushing ? 20 : 0)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { startGame() }
        .overlay(alignment: .topTrailing) { settingsButton }
        // Blackout at the end of the rush so the route swap is invisible.
        .overlay {
            Color.black
                .opacity(rushing ? 1 : 0)
                .animation(rushing ? .easeIn(duration: 0.34).delay(0.12) : nil, value: rushing)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            doorOpen = false; rushing = false
            MenuAudioService.shared.startBackground()
        }
        .onDisappear { MenuAudioService.shared.stopBackground() }
        .overlay {
            if showDelete {
                DeleteConfirmView(
                    onNo: { showDelete = false },
                    onYes: {
                        showDelete = false
                        store.resetForDeletePrank()
                        path.append(.game(.two))   // joke: bounce straight back into the game
                    })
            }
        }
        // Settings popup — floats over the home scene, not a pushed page.
        .overlay {
            if showSettings {
                SettingsView { withAnimation(.easeOut(duration: 0.2)) { showSettings = false } }
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Door + glow

    /// The red door panel, center stage. The black doorway interior with its
    /// red rim is baked into the MenuForest art directly behind the panel, so
    /// on `doorOpen` the panel swings inward on its left hinge (matching the
    /// Figma prototype recording: ~1.1 s ease-in-out, panel falling into
    /// shadow, no glow change) and the dark interior is revealed.
    private func doorway(in size: CGSize) -> some View {
        // Export geometry: door panel 82×165 pt at (396, 115) in the 874×402
        // art; base hidden behind the jagged ground. The MenuForest image is
        // rendered .scaledToFill, so map art coordinates through the same
        // scale + centering the image gets — keeps the panel pixel-locked to
        // the baked doorway on any screen aspect.
        let s = max(size.width / 874, size.height / 402)
        let ox = (size.width - 874 * s) / 2
        let oy = (size.height - 402 * s) / 2
        return RedDoorView(open: doorOpen)
            .frame(width: 82 * s, height: 165 * s)
            .position(x: ox + (396 + 82 / 2) * s, y: oy + (115 + 165 / 2) * s)
            .allowsHitTesting(false)
    }

    private func startGame() {
        guard !doorOpen, !showDelete else { return }
        // 1. Door swings open (per the prototype recording) — fire the
        // door-open SFX at the same instant so it tracks the swing, and fade
        // the menu backsound out as the scene starts to rush in.
        MenuAudioService.shared.playDoorOpen()
        MenuAudioService.shared.fadeOutBackground(duration: 1.0)
        withAnimation(.easeInOut(duration: 1.1)) { doorOpen = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1050))
            // 2. Hyperspeed rush through the opening — a hard exponential
            // suck-in (slow lean, then a violent plunge), faster than before,
            // diving into the dark doorway interior.
            withAnimation(.timingCurve(0.7, 0, 0.98, 0.4, duration: 0.45)) { rushing = true }
            try? await Task.sleep(for: .milliseconds(500))
            // 3. Screen is black — swap to the game unseen.
            path.append(.game(.two))   // L1 retired — play starts straight at L2
        }
    }

    // MARK: - Chrome

    private var menuRow: some View {
        HStack(spacing: 28) {
            MenuPill(title: loc.t(.level)) { path.append(.levelSelect) }
            MenuPill(title: loc.t(.deleteApp)) { showDelete = true }
        }
    }

    private var tapToStart: some View {
        Text("tap to start")
            .font(.system(size: 17, weight: .medium, design: .monospaced))
            .tracking(6)
            .foregroundStyle(.white)
            .opacity(captionPulse ? 1 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    captionPulse = true
                }
            }
    }

    private var settingsButton: some View {
        Button { withAnimation(.easeIn(duration: 0.2)) { showSettings = true } } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.6))
                .padding(14)
        }
    }
}

// MARK: - Components

/// White capsule button with dark text, per the Figma export.
struct MenuPill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 26)
                .padding(.vertical, 8)
                .background(.white, in: Capsule())
        }
    }
}

/// The red door panel from the export: vertical red gradient, `-|` handle
/// (10×2 dash meeting a 4.5×20 bar, #D9D9D9) near the trailing edge, and the
/// red halo the export applies as a drop shadow (dilate 6 + blur σ≈26,
/// #DB1C16 at 55%). Swings inward on its leading (left) hinge, darkening as
/// it turns away from the light — per the prototype recording.
struct RedDoorView: View {
    var open: Bool

    private static let handleColor = Color(red: 0.85, green: 0.85, blue: 0.85) // #D9D9D9
    private static let haloColor = Color(red: 0.86, green: 0.11, blue: 0.086)  // #DB1C16

    var body: some View {
        GeometryReader { g in
            // Art-space unit: the panel is 82×165 in the export.
            let u = g.size.width / 82
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.86, green: 0.03, blue: 0.0),   // #DB0700
                                 Color(red: 0.31, green: 0.0, blue: 0.0)],   // #4F0000
                        startPoint: .top, endPoint: .bottom))
                // Handle: horizontal dash into a vertical bar (export coords
                // relative to the panel origin).
                Rectangle()
                    .fill(Self.handleColor)
                    .frame(width: 10 * u, height: 2 * u)
                    .offset(x: 65 * u, y: 81 * u)
                Rectangle()
                    .fill(Self.handleColor)
                    .frame(width: 4.5 * u, height: 20 * u)
                    .offset(x: 72 * u, y: 73 * u)
            }
            // Red halo hugging the panel (dense rim + wide falloff).
            .shadow(color: Self.haloColor.opacity(0.5), radius: 7 * u)
            .shadow(color: Self.haloColor.opacity(0.45), radius: 26 * u)
            // Panel falls into shadow as it swings away from the glow.
            .overlay(Color.black.opacity(open ? 0.55 : 0))
            .rotation3DEffect(
                .degrees(open ? -88 : 0),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.55)
        }
    }
}
