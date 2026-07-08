//
//  BedtimeStoryBackground.swift
//  Wofoking — Load Away
//
//  Ambient "dongeng sebelum tidur" (bedtime-story) scene rebuilt native from
//  the Figma export `bg dongeng sebelum tidur.svg`. The export is a near-black
//  forest at night: a single soft glowing wisp/firefly drifting on a loop, a
//  few near-black reed silhouettes, and the same fractal-noise film grain the
//  menu art uses. The art is authored portrait (402×874) but the app is
//  landscape-locked, and the scene is abstract, so it renders full-screen and
//  the firefly wanders the whole frame. Used as the backdrop behind the typing
//  story text in `StorylineView` (replaces the old plain `Color.black`).
//

import SwiftUI

struct BedtimeStoryBackground: View {
    // Export palette.
    private static let base = Color(red: 0.027, green: 0.027, blue: 0.027) // #070707
    private static let wispCore = Color.white
    private static let wispEdge = Color(red: 1.0, green: 0.769, blue: 0.769) // #FFC4C4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let d = min(w, h)

            ZStack {
                Self.base

                Reeds()                    // faint near-black silhouettes, breathing
                firefly(w: w, h: h, d: d)  // the drifting glow (hero)
                Grain()                    // animated film grain

                // Soft vignette to frame the scene and keep the centered story
                // text legible.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    center: .center,
                    startRadius: d * 0.18,
                    endRadius: max(w, h) * 0.72)
                    .blendMode(.multiply)
            }
            .compositingGroup()   // resolve blend modes internally, not onto text
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - Firefly

    /// A single soft wisp drifting on a slow wandering (Lissajous) loop with a
    /// gentle brightness pulse — the export's animated `Ellipse_83`, calmed for
    /// a bedtime mood (the export loops in 2 s; here the drift is much slower).
    private func firefly(w: CGFloat, h: CGFloat, d: CGFloat) -> some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let x = 0.5 + 0.28 * sin(t * .pi * 2 / 14)
            let y = 0.44 + 0.20 * sin(t * .pi * 2 / 9 + 1.3)
            let pulse = 0.44 + 0.10 * sin(t * .pi * 2 / 3.5)

            Circle()
                .fill(RadialGradient(
                    colors: [Self.wispCore, Self.wispEdge.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: d * 0.30))
                .frame(width: d * 0.62, height: d * 0.62)
                .blur(radius: d * 0.05)
                .opacity(pulse)
                .blendMode(.plusLighter)
                .position(x: w * x, y: h * y)
        }
    }
}

// MARK: - Reeds

/// Near-black tapered blades along the bottom edge, each slowly breathing its
/// opacity — the export's `Vector_132/133/134` silhouettes that fade over the
/// loop. `#050505` is slightly darker than the `#070707` base, so they read as
/// faint shadows suggesting a forest floor.
private struct Reeds: View {
    private struct Reed { let x: CGFloat; let height: CGFloat; let width: CGFloat; let period: Double; let phase: Double; let base: Double }
    private static let reeds: [Reed] = [
        Reed(x: 0.14, height: 0.55, width: 26, period: 7.0, phase: 0.0, base: 0.9),
        Reed(x: 0.32, height: 0.42, width: 18, period: 9.0, phase: 1.4, base: 0.7),
        Reed(x: 0.68, height: 0.48, width: 20, period: 8.0, phase: 2.6, base: 0.8),
        Reed(x: 0.86, height: 0.38, width: 22, period: 6.5, phase: 3.7, base: 0.85),
    ]
    private static let blade = Color(red: 0.0196, green: 0.0196, blue: 0.0196) // #050505

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for reed in Self.reeds {
                    let breathe = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * .pi * 2 / reed.period + reed.phase))
                    let baseX = size.width * reed.x
                    let topY = size.height * (1 - reed.height)
                    var p = Path()
                    p.move(to: CGPoint(x: baseX - reed.width / 2, y: size.height))
                    p.addQuadCurve(
                        to: CGPoint(x: baseX, y: topY),
                        control: CGPoint(x: baseX - reed.width * 0.2, y: size.height * 0.6))
                    p.addQuadCurve(
                        to: CGPoint(x: baseX + reed.width / 2, y: size.height),
                        control: CGPoint(x: baseX + reed.width * 0.2, y: size.height * 0.6))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(Self.blade.opacity(reed.base * breathe)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Grain

/// Subtle animated film grain (dark speckle, `.multiply`) — the export's
/// `feTurbulence` fractal-noise overlay at `rgba(0,0,0,0.25)`. Reseeded each
/// tick at a low frame rate for a calm, cheap flicker.
private struct Grain: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { tl in
            // `tl.date` drives the redraw; the RNG reseeds naturally each frame.
            let _ = tl.date
            Canvas { ctx, size in
                for _ in 0..<260 {
                    let x = Double.random(in: 0..<max(1, size.width))
                    let y = Double.random(in: 0..<max(1, size.height))
                    let a = Double.random(in: 0...0.18)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)),
                        with: .color(.black.opacity(a)))
                }
            }
        }
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }
}

#Preview(traits: .landscapeLeft) {
    BedtimeStoryBackground()
}
