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
    // Adaptor delivers the remote startWatchApp launch to handle(_:).
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var hr = WatchHeartRateManager.shared
    var body: some Scene {
        WindowGroup {
            WatchContentView(hr: hr)
        }
    }
}
