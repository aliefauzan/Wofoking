//
//  WatchContentView.swift
//  Wofoking Watch App (watchOS companion)
//
//  Minimal watch UI: shows live BPM and lets the player start/stop streaming.
//  Streaming also auto-starts when the iPhone game requests it.
//

import SwiftUI

struct WatchContentView: View {
    @ObservedObject var hr: WatchHeartRateManager

    var body: some View {
        VStack(spacing: 12) {
            Text("LOAD AWAY").font(.caption2).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating, isActive: hr.isRunning)
                Text(hr.bpm.map { "\($0)" } ?? "—")
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
            }

            Button(hr.isRunning ? "Stop" : "Start") {
                hr.isRunning ? hr.stop() : hr.start()
            }
            .tint(hr.isRunning ? .red : .green)
        }
        .padding()
    }
}
