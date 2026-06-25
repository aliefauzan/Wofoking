//
//  WofokingWatchApp.swift
//  Wofoking Watch App (watchOS companion)
//
//  Add this folder to a new "Watch App" target in Xcode (see README). Streams
//  live heart rate to the iPhone via WatchConnectivity during gameplay.
//

import SwiftUI

@main
struct WofokingWatchApp: App {
    @StateObject private var hr = WatchHeartRateManager()
    var body: some Scene {
        WindowGroup {
            WatchContentView(hr: hr)
        }
    }
}
