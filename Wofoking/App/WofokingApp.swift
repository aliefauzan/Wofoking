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
        }
        .onChange(of: scenePhase) { _, phase in
            // Keep the screen awake while the app is in front; restore the
            // normal auto-lock when backgrounded/inactive.
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }
}
