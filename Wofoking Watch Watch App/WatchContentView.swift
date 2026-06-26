//
//  WatchContentView.swift
//  Wofoking Watch App (watchOS companion)
//
//  Not a real app — just a passive HR streamer. No controls: streaming
//  auto-starts on launch (a workout session needs the app running) and pushes
//  live BPM to the iPhone. Shows a minimal status only.
//

import SwiftUI

struct WatchContentView: View {
    @ObservedObject var hr: WatchHeartRateManager

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating, isActive: hr.isRunning)
            Text(hr.bpm.map { "\($0)" } ?? "—")
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
            Text(hr.isRunning ? "streaming" : "—")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { hr.start() }   // auto-stream, no button
    }
}
