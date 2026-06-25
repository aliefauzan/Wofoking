//
//  HeartRateService.swift
//  Wofoking — Load Away
//
//  Live heart-rate input (PRD §10.7 FR-SET-3/4, §12.1, Use Case
//  "Heart-Rate Driven Difficulty"). Receives realtime BPM streamed from the
//  paired Apple Watch via WatchConnectivity, tracks a rolling baseline, and
//  flags "elevated" so LoadingController can make Level 2 more volatile.
//
//  HealthKit authorization is only requested when the player enables Heart
//  Rate in Settings (FR-SET-4). Game runs normally if the watch is absent or
//  permission is denied (PRD §14).
//

import Foundation
import Combine
import WatchConnectivity
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class HeartRateService: NSObject, ObservableObject {
    static let shared = HeartRateService()

    /// Latest BPM, or nil when unknown (UI shows "—").
    @Published private(set) var bpm: Int?
    /// True when current BPM is meaningfully above the session baseline.
    @Published private(set) var isElevated = false
    /// True once a watch is streaming live samples.
    @Published private(set) var isStreaming = false

    /// Gate from Settings. Toggling on triggers auth + connectivity.
    var enabled = false

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    // Rolling baseline via exponential moving average.
    private var baseline: Double?
    private let emaAlpha = 0.1
    private let elevatedRatio = 1.10   // 10% over baseline = "pressure"

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Enable / authorize

    func enable() {
        enabled = true
        requestAuthorization()
        // Ask the watch app to start streaming if reachable.
        sendCommandToWatch(start: true)
    }

    func disable() {
        enabled = false
        isStreaming = false
        bpm = nil
        isElevated = false
        baseline = nil
        sendCommandToWatch(start: false)
    }

    private func requestAuthorization() {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hr = HKQuantityType(.heartRate)
        healthStore.requestAuthorization(toShare: [], read: [hr]) { _, _ in }
        #endif
    }

    // MARK: Ingest

    private func ingest(_ value: Double) {
        guard enabled, value > 0 else { return }
        bpm = Int(value.rounded())
        isStreaming = true

        if let b = baseline {
            baseline = b * (1 - emaAlpha) + value * emaAlpha
            isElevated = value > b * elevatedRatio
        } else {
            baseline = value          // first sample seeds the baseline
            isElevated = false
        }
    }

    private func sendCommandToWatch(start: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([HRKey.streaming: start], replyHandler: nil, errorHandler: nil)
    }
}

// MARK: - WatchConnectivity

extension HeartRateService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private nonisolated func handle(_ payload: [String: Any]) {
        if let value = payload[HRKey.bpm] as? Double {
            Task { @MainActor in self.ingest(value) }
        }
        if let streaming = payload[HRKey.streaming] as? Bool, !streaming {
            Task { @MainActor in self.isStreaming = false }
        }
    }
}
