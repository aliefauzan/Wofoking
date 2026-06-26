//
//  WofokingApp.swift
//  Wofoking — Load Away
//

import SwiftUI
import UIKit

@main
struct WofokingApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // Activate WCSession at launch so watch samples are not lost
                // before the game screen first touches the singleton.
                .task { _ = HeartRateService.shared }
        }
        .onChange(of: scenePhase) { _, phase in
            // Keep the screen awake while the app is in front; restore the
            // normal auto-lock when backgrounded/inactive.
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }
}
