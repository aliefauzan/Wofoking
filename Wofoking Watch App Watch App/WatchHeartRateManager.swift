//
//  WatchHeartRateManager.swift
//  Wofoking Watch App (watchOS companion)
//
//  Runs an HKWorkoutSession + HKLiveWorkoutBuilder to obtain realtime heart
//  rate, then streams each sample to the iPhone over WatchConnectivity
//  (Use Case "Heart-Rate Driven Difficulty"). Uses the shared HRKey contract
//  (HRMessage.swift — add that file to this target too).
//

import Foundation
import Combine
import HealthKit
import WatchConnectivity

@MainActor
final class WatchHeartRateManager: NSObject, ObservableObject {

    @Published private(set) var bpm: Int?
    @Published private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Control

    func start() {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        healthStore.requestAuthorization(toShare: [HKQuantityType.workoutType()],
                                         read: [hrType]) { [weak self] ok, _ in
            guard ok else { return }
            Task { @MainActor in self?.beginWorkout() }
        }
    }

    private func beginWorkout() {
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        isRunning = false
        send(streaming: false)
    }

    // MARK: Send to phone

    private func push(_ value: Double) {
        bpm = Int(value.rounded())
        let payload: [String: Any] = [HRKey.bpm: value,
                                      HRKey.timestamp: Date().timeIntervalSince1970,
                                      HRKey.streaming: true]
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? s.updateApplicationContext(payload)   // coalesced latest value
        }
    }

    private func send(streaming: Bool) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        try? s.updateApplicationContext([HRKey.streaming: streaming])
    }
}

// MARK: - Workout collection

extension WatchHeartRateManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let quantity = stats.mostRecentQuantity() else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let value = quantity.doubleValue(for: unit)
        Task { @MainActor in self.push(value) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchHeartRateManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in self.isRunning = false }
    }
}

// MARK: - Connectivity (phone → watch start/stop commands)

extension WatchHeartRateManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let stream = message[HRKey.streaming] as? Bool else { return }
        Task { @MainActor in stream ? self.start() : self.stop() }
    }
}
