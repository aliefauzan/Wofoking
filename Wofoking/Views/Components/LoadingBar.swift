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
            Text("\(Int(progress))%")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.numericText())
                .scaleEffect(atWindow ? 1.12 : 1)
                .animation(.spring(duration: 0.25), value: atWindow)

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
        }
    }

    private var fillColor: Color {
        .white
    }
}

#Preview("Loading", traits: .landscapeLeft) {
    ZStack {
        Color.black.ignoresSafeArea()
        LoadingBar(progress: 63, atWindow: false)
            .frame(maxWidth: 520)
            .padding(40)
    }
}

#Preview("At window", traits: .landscapeLeft) {
    ZStack {
        Color.black.ignoresSafeArea()
        LoadingBar(progress: 100, atWindow: true)
            .frame(maxWidth: 520)
            .padding(40)
    }
}
