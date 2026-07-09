//
//  FaceScanView.swift
//  Wofoking — Load Away
//
//  The Face Detection / Face Scan screen (App Flow: Start → Face Scan → …).
//  Sits on top of the live camera feed rendered by GameContainerView. Shows the
//  single-face instruction, a BLOCKING "too many faces" state, and a small
//  corner-bracket detection box.
//
//  Flow (matches the spec):
//    1. Exactly one face must be in frame. More than one → the box turns yellow
//       and the status line blocks; GameVM won't lock (waitForStableFace gates
//       on visibleFaceCount == 1).
//    2. Once one face is locked, the box picks ONE top corner (left OR right)
//       and jumps face → corner → face 4–6×, lingering at each end so the move
//       reads clearly, then ALWAYS ends back on the face (a final clean tear
//       home), with an RGB-split/slice glitch on each tear.
//    3. It settles back on the player's face, then advances to the storyline.
//
//  IMPORTANT: the glitch is VISUAL ONLY. It nudges a SwiftUI overlay and never
//  reads or mutates the GazeTracker / ARKit detection state — the real locked
//  face stays the source of truth. All timings live in ConfigService (glitch*).
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
    // Glitch aesthetic drivers (visual only). rgbSplit = chromatic-aberration
    // spread, sliceOffset = horizontal tear, maskOpacity = flicker.
    @State private var rgbSplit: CGFloat = 0
    @State private var sliceOffset: CGFloat = 0
    @State private var maskOpacity: Double = 1

    private var config: ConfigService { .shared }

    /// Blocked: more than one face in frame and the glitch hasn't started. The
    /// lock in GameVM won't fire in this state, so the screen just waits here.
    private var tooManyFaces: Bool { vm.faceCount > 1 && !started }

    var body: some View {
        VStack(spacing: 12) {
            instructions
            Spacer()
            reticle
            Text(tooManyFaces ? loc.t(.faceScanTooMany) : (statusText ?? loc.t(.faceCalibrating)))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(tooManyFaces ? .yellow : (detected ? .green : .white))
                .animation(.easeInOut, value: statusText)
                .animation(.easeInOut, value: vm.faceCount)
                .padding(.top, 16)   // sit clearly BELOW the reticle box, not inside it
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
            // The "too many faces" block is surfaced on the status line below
            // the reticle (see `tooManyFaces`); it now HALTS the lock, not just
            // warns — GameVM won't lock until exactly one face remains.
        }
        .multilineTextAlignment(.center)
        .animation(.easeInOut, value: vm.faceCount)
    }

    // MARK: Face mask + ghost

    private var maskColor: Color {
        if detected { return .green }
        if tooManyFaces { return .yellow }
        return .white.opacity(0.9)
    }

    private var reticle: some View {
        ZStack {
            // Faint red "ghost" box parked on the wrong (top) spot the whole glitch.
            if showGhost {
                BoxReticle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 2)
                    .frame(width: 150, height: 150)
                    .offset(ghostOffset)
                    .blur(radius: 0.5)
            }
            // The live box: RGB-split copies + a crisp top layer. During the
            // glitch these tear apart; settled, they collapse to one clean box.
            GlitchBox(color: maskColor, rgbSplit: rgbSplit, sliceOffset: sliceOffset)
                .frame(width: 150, height: 150)
                .opacity(maskOpacity)
                .offset(glitchOffset)
                .shadow(color: (detected ? Color.green : (tooManyFaces ? .yellow : .cyan)).opacity(0.6), radius: 8)
        }
    }

    // MARK: Glitch (visual only)

    private func startGlitch() {
        guard !started else { return }
        started = true
        Task { await runGlitch() }
    }

    private func runGlitch() async {
        // Pick ONE top corner for the whole sequence — top-left OR top-right.
        let y = -config.glitchTopOffset
        let corner = CGSize(width: Bool.random() ? -config.glitchSideOffset
                                                 : config.glitchSideOffset,
                            height: y)
        let jumps = max(2, Int.random(in: config.glitchJumpCountMin...config.glitchJumpCountMax))

        statusText = loc.t(.glitchWait)
        // A faint red ghost box marks the corner for the whole sequence.
        withAnimation(.easeIn(duration: 0.12)) {
            ghostOffset = corner
            showGhost = true
        }

        for i in 0..<jumps {
            if i == jumps - 1 { statusText = loc.t(.glitchNotYou) }
            // Drift the corner a touch each jump + randomise every duration, so
            // the motion feels organic, not a constant back-and-forth.
            let d = config.glitchCornerDrift
            let spot = CGSize(width: corner.width + .random(in: -d...d),
                              height: corner.height + .random(in: -d...d))
            await glitchTo(spot, over: randMove())      // tear onto the corner
            await hold(at: spot, for: randHold())       // linger — legible
            await glitchTo(.zero, over: randMove())     // tear back onto the face
            await hold(at: .zero, for: randHold())
        }

        // ALWAYS end on the face: one final clean tear home, no drift, so the
        // box never settles at a corner.
        await glitchTo(.zero, over: randMove())

        // Collapse the split and settle firmly back on the player's face.
        withAnimation(.easeOut(duration: 0.28)) {
            glitchOffset = .zero
            ghostOffset = .zero
            showGhost = false
            detected = true
            rgbSplit = 0
            sliceOffset = 0
            maskOpacity = 1
        }
        statusText = loc.t(.glitchDetected)
        try? await Task.sleep(nanoseconds: UInt64(config.glitchSettleSeconds * 1_000_000_000))
        onFinished()
    }

    private func randMove() -> Double {
        .random(in: config.glitchMoveMinSeconds...config.glitchMoveMaxSeconds)
    }
    private func randHold() -> Double {
        .random(in: config.glitchHoldMinSeconds...config.glitchHoldMaxSeconds)
    }

    /// Tear the box toward `dest` as a few fast, jittery steps — RGB split flares
    /// and the box shears sideways, so the move reads as a hard digital glitch.
    private func glitchTo(_ dest: CGSize, over seconds: Double) async {
        let steps = max(3, Int(seconds / 0.045))
        let stepNs = UInt64((seconds / Double(steps)) * 1_000_000_000)
        for _ in 0..<steps {
            withAnimation(.linear(duration: 0.045)) {
                glitchOffset = CGSize(width: dest.width + .random(in: -6...6),
                                      height: dest.height + .random(in: -6...6))
                rgbSplit = .random(in: 4...12)
                sliceOffset = .random(in: -9...9)
                maskOpacity = .random(in: 0.7...1)
            }
            try? await Task.sleep(nanoseconds: stepNs)
        }
        glitchOffset = dest   // land exactly on the point
    }

    /// Settle the box cleanly at `pos` and hold, so its position is legible
    /// before the next tear — the split/shear relax to a crisp box.
    private func hold(at pos: CGSize, for seconds: Double) async {
        withAnimation(.easeOut(duration: 0.12)) {
            glitchOffset = pos
            rgbSplit = 0
            sliceOffset = 0
            maskOpacity = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Detection box (corner brackets) with optional RGB split + slice tear for the
/// glitch. Visual only.
private struct GlitchBox: View {
    var color: Color
    var rgbSplit: CGFloat
    var sliceOffset: CGFloat

    var body: some View {
        ZStack {
            if rgbSplit > 0.5 {
                BoxReticle()
                    .stroke(Color.red.opacity(0.9), lineWidth: 2)
                    .offset(x: -rgbSplit, y: rgbSplit * 0.25)
                    .blendMode(.screen)
                BoxReticle()
                    .stroke(Color.cyan.opacity(0.9), lineWidth: 2)
                    .offset(x: rgbSplit, y: -rgbSplit * 0.25)
                    .blendMode(.screen)
            }
            BoxReticle()
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        }
        .offset(x: sliceOffset)
    }
}

/// Classic face-detection corner brackets drawn inside the view's rect.
private struct BoxReticle: Shape {
    var cornerLength: CGFloat = 26

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

#Preview(traits: .landscapeLeft) {
    ZStack {
        LoadAwayBackground()
        FaceScanView(vm: GameVM(level: .two),
                     loc: Localization(language: .english),
                     onFinished: {})
    }
}
