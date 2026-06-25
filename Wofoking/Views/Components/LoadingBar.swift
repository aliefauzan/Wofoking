//
//  LoadingBar.swift
//  Wofoking — Load Away
//
//  The hostile loading bar. Colour shifts as it nears 100%.
//

import SwiftUI

struct LoadingBar: View {
    let progress: Double   // 0...100
    var atWindow: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(fillColor)
                        .frame(width: geo.size.width * CGFloat(progress / 100))
                        .animation(.linear(duration: 0.05), value: progress)
                }
            }
            .frame(height: 22)

            Text("\(Int(progress))%")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .scaleEffect(atWindow ? 1.12 : 1)
                .animation(.spring(duration: 0.25), value: atWindow)
        }
    }

    private var fillColor: Color {
        switch progress {
        case ..<75:  return Color(red: 0.55, green: 0.45, blue: 0.85)
        case ..<90:  return Color(red: 0.95, green: 0.75, blue: 0.35)
        default:     return Color(red: 0.95, green: 0.40, blue: 0.45)
        }
    }
}
