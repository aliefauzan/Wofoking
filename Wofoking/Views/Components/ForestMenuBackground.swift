//
//  ForestMenuBackground.swift
//  Wofoking — Load Away
//
//  Home-menu scenery: the actual Figma "PINTU KEBUKA" forest art, baked to
//  the `MenuForest` asset (leaves, door, buttons and captions stripped from
//  the export so they can live as native, animatable SwiftUI on top).
//  The LOAD AWAY logo is part of the art. Ambient falling leaves — the only
//  motion in the prototype video (four leaves tumbling down-left on a
//  staggered ~20 s loop) — are re-created natively here.
//

import SwiftUI

/// Layers *behind* the door: forest, fog, red glow, doorway interior.
struct ForestMenuBackground: View {
    var body: some View {
        ZStack {
            Color.black
            Image("MenuForest")
                .resizable()
                .scaledToFill()
        }
        .ignoresSafeArea()
    }
}

/// Layers *in front of* the door — split at the door's z-index in the export:
/// front mist, the jagged ground the door stands behind, the grain texture
/// (which grains the door too, as in Figma), the LOAD AWAY logo, and the
/// falling leaves on top.
struct ForestMenuForeground: View {
    var body: some View {
        ZStack {
            Image("MenuForestFront")
                .resizable()
                .scaledToFill()
            FallingLeaves()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Leaves

/// Ambient falling leaves matching the export's motion: near-black leaves,
/// staggered across a ~20 s loop, each drifting down-left while tumbling.
private struct FallingLeaves: View {
    private struct Leaf {
        let phase: Double        // offset into the shared loop (0…1)
        let startX: CGFloat      // fraction of width
        let startY: CGFloat      // fraction of height
        let driftX: CGFloat      // fraction of width travelled (negative = left)
        let driftY: CGFloat      // fraction of height travelled
        let spin: Double         // total tumble, radians
    }

    private static let leaves: [Leaf] = [
        Leaf(phase: 0.00, startX: 0.62, startY: 0.10, driftX: -0.45, driftY: 0.70, spin: 3.4),
        Leaf(phase: 0.28, startX: 0.75, startY: -0.05, driftX: -0.40, driftY: 0.85, spin: -2.6),
        Leaf(phase: 0.52, startX: 0.48, startY: 0.02, driftX: -0.35, driftY: 0.75, spin: 2.9),
        Leaf(phase: 0.76, startX: 0.85, startY: 0.15, driftX: -0.50, driftY: 0.65, spin: -3.1),
    ]

    private static let leafPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -1, y: 8))                                   // stem tip
        p.addQuadCurve(to: CGPoint(x: 12, y: -7), control: CGPoint(x: 0, y: -9))
        p.addQuadCurve(to: CGPoint(x: -1, y: 8), control: CGPoint(x: 13, y: 6))
        return p
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let cycle = 20.0
                let now = timeline.date.timeIntervalSinceReferenceDate
                for leaf in Self.leaves {
                    let p = ((now / cycle) + leaf.phase).truncatingRemainder(dividingBy: 1)
                    // Each leaf is airborne for ~45% of the loop, parked otherwise
                    // (matches the export: long idle gaps between passes).
                    guard p < 0.45 else { continue }
                    let u = p / 0.45
                    let x = size.width * (leaf.startX + leaf.driftX * u) + sin(u * .pi * 3) * 14
                    let y = size.height * (leaf.startY + leaf.driftY * u) + sin(u * .pi * 2) * 6
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(u * leaf.spin + sin(u * .pi * 2) * 0.4))
                    c.fill(Self.leafPath, with: .color(Color(white: 0.086)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview(traits: .landscapeLeft) {
    ForestMenuBackground()
}
