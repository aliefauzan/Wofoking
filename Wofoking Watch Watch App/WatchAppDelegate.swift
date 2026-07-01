//
//  WatchAppDelegate.swift
//  Wofoking Watch App (watchOS companion)
//
//  The entry point for REMOTE launch. When the iPhone calls
//  HKHealthStore.startWatchApp(with:), watchOS wakes this app in the background
//  and calls handle(_ workoutConfiguration:). Nothing else fires (no UI, so
//  WatchContentView.onAppear does NOT run) — starting the workout here is what
//  makes BPM stream and brings the app to the foreground.
//
//  Requires the watch target's "Background Modes → Workout Processing"
//  capability (WKBackgroundModes = workout-processing) for the background wake.
//

import SwiftUI
import HealthKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// Remote launch from the paired iPhone (startWatchApp). Start the workout
    /// with the phone-supplied configuration on the shared manager.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WatchHeartRateManager.shared.start(with: workoutConfiguration)
        }
    }
}
