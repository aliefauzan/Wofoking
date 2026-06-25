//
//  LoadAwayBackground.swift
//  Wofoking — Load Away
//
//  Procedural scenery matching the LOAD AWAY concept art: dusk gradient sky,
//  floating monoliths, and layered hills. Pure SwiftUI shapes (no assets).
//

import SwiftUI

struct LoadAwayBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Dusk sky gradient (purple → warm pink horizon).
                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.22, blue: 0.42),
                        Color(red: 0.55, green: 0.35, blue: 0.55),
                        Color(red: 0.85, green: 0.66, blue: 0.70),
                    ],
                    startPoint: .top, endPoint: .bottom)

                // Soft glow near the horizon.
                RadialGradient(
                    colors: [Color.white.opacity(0.35), .clear],
                    center: UnitPoint(x: 0.5, y: 0.62),
                    startRadius: 0, endRadius: w * 0.55)

                // Floating monoliths.
                ForEach(Self.monoliths, id: \.x) { m in
                    Monolith()
                        .fill(Color(red: 0.30, green: 0.22, blue: 0.38).opacity(0.9))
                        .frame(width: m.size, height: m.size * 2.4)
                        .position(x: w * m.x, y: h * m.y)
                }

                // Layered hills.
                Hills(amplitude: 0.05, baseline: 0.66)
                    .fill(Color(red: 0.52, green: 0.45, blue: 0.60))
                Hills(amplitude: 0.07, baseline: 0.74)
                    .fill(Color(red: 0.36, green: 0.30, blue: 0.46))
                Hills(amplitude: 0.06, baseline: 0.84)
                    .fill(Color(red: 0.18, green: 0.13, blue: 0.26))
            }
            .ignoresSafeArea()
        }
    }

    private struct M { let x: CGFloat; let y: CGFloat; let size: CGFloat }
    private static let monoliths: [M] = [
        M(x: 0.18, y: 0.22, size: 34),
        M(x: 0.30, y: 0.34, size: 24),
        M(x: 0.72, y: 0.30, size: 20),
        M(x: 0.82, y: 0.20, size: 30),
    ]
}

/// A blocky floating island, wider at top.
private struct Monolith: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.width * 0.18
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A smooth rolling-hills silhouette filling the bottom of the frame.
private struct Hills: Shape {
    let amplitude: CGFloat   // fraction of height
    let baseline: CGFloat    // fraction of height where the ridge sits

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = rect.height * baseline
        let amp = rect.height * amplitude
        p.move(to: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: baseY))
        let steps = 6
        for i in 0...steps {
            let x = rect.width * CGFloat(i) / CGFloat(steps)
            let y = baseY + CGFloat(sin(Double(i) * 1.3)) * amp
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}
