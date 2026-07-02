//
//  FaceScanView.swift
//  Wofoking — Load Away
//
//  The Face Detection / Face Scan screen (App Flow: Start → Face Scan → …).
//  Sits on top of the live camera feed rendered by GameContainerView. Shows the
//  single-face instruction, an optional "too many faces" warning, and a
//  detection reticle.
//
//  IMPORTANT: the "buggy face location" glitch here is VISUAL ONLY. It nudges a
//  SwiftUI overlay to random offsets a few times after a stable face is locked,
//  then settles and advances to the storyline. It never reads or mutates the
//  GazeTracker / ARKit detection state — the real locked face stays the source
//  of truth. All timings live in ConfigService (glitch* constants).
//

import SwiftUI

struct FaceScanView: View {
    @ObservedObject var vm: GameVM
    let loc: Localization
    /// Called once the glitch has run and settled.
    var onFinished: () -> Void

    @State private var glitchOffset: CGSize = .zero
    @State private var ghostOffset: CGSize = .zero
    @State private var showGhost = false
    @State private var statusText: String?
    @State private var detected = false
    @State private var started = false

    private var config: ConfigService { .shared }

    var body: some View {
        VStack(spacing: 12) {
            instructions
            Spacer()
            reticle
            Text(statusText ?? loc.t(.faceCalibrating))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(detected ? .green : .white)
                .animation(.easeInOut, value: statusText)
                .padding(.top, 20)
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .onChange(of: vm.faceLocked) { _, locked in if locked { startGlitch() } }
        .onAppear { if vm.faceLocked { startGlitch() } }
    }

    // MARK: Copy

    private var instructions: some View {
        VStack(spacing: 6) {
            Text(loc.t(.faceScanInstruction))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            Text(loc.t(.faceScanInstructionSecondary))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            // Multi-face warning. The session already tracks up to 3 faces, so
            // this is a real read — but it only warns, never blocks (per spec).
            if vm.faceCount > 1 && !started {
                Text(loc.t(.faceScanTooMany))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .animation(.easeInOut, value: vm.faceCount)
    }

    // MARK: Reticle + ghost

    private var reticle: some View {
        ZStack {
            if showGhost {
                FaceReticle()
                    .stroke(Color.red.opacity(0.55), lineWidth: 3)
                    .frame(width: 220, height: 300)
                    .offset(ghostOffset)
            }
            FaceReticle()
                .stroke(detected ? Color.green : Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 220, height: 300)
                .offset(glitchOffset)
                .shadow(color: (detected ? Color.green : .cyan).opacity(0.6), radius: 8)
        }
    }

    // MARK: Glitch (visual only)

    private func startGlitch() {
        guard !started else { return }
        started = true
        Task { await runGlitch() }
    }

    private func runGlitch() async {
        let m = config.glitchMaxOffset
        let hold = UInt64(config.glitchJumpSeconds * 1_000_000_000)

        statusText = loc.t(.glitchWait)
        for i in 0..<max(2, config.glitchJumpCount) {
            withAnimation(.easeInOut(duration: 0.07)) {
                glitchOffset = randomOffset(m)
                ghostOffset = randomOffset(m)
                showGhost = true
            }
            if i == config.glitchJumpCount - 1 { statusText = loc.t(.glitchNotYou) }
            try? await Task.sleep(nanoseconds: hold)
        }

        withAnimation(.easeOut(duration: 0.25)) {
            glitchOffset = .zero
            showGhost = false
            detected = true
        }
        statusText = loc.t(.glitchDetected)
        try? await Task.sleep(nanoseconds: UInt64(config.glitchSettleSeconds * 1_000_000_000))
        onFinished()
    }

    private func randomOffset(_ m: Double) -> CGSize {
        CGSize(width: .random(in: -m...m), height: .random(in: -m...m))
    }
}

/// Classic face-detection corner brackets drawn inside the view's rect.
private struct FaceReticle: Shape {
    var cornerLength: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = cornerLength
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        return p
    }
}
