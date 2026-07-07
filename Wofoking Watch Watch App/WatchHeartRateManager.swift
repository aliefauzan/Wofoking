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
@preconcurrency import HealthKit
import WatchConnectivity

@MainActor
final class WatchHeartRateManager: NSObject, ObservableObject {

    // Shared so the WKApplicationDelegate's handle(_:) (background launch via
    // startWatchApp) and WatchContentView (manual open) drive one instance.
    static let shared = WatchHeartRateManager()

    @Published private(set) var bpm: Int?
    @Published private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    // Synchronous latch: `isRunning` only flips true *after* the async auth
    // callback, so two start() calls in the auth window both pass `!isRunning`
    // and build a second HKWorkoutSession → the builders collide into HK's
    // Error(7) wedged state. This closes that window immediately.
    private var isStarting = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Control

    /// `config` is supplied when launched remotely via `startWatchApp` (passed
    /// to the WKApplicationDelegate's `handle(_:)`); nil on manual open.
    /// Config from the most recent start request. Stashed on the (MainActor)
    /// instance so the non-Sendable HKWorkoutConfiguration never crosses into
    /// the @Sendable auth completion (Swift 6 error).
    private var pendingConfig: HKWorkoutConfiguration?

    func start(with config: HKWorkoutConfiguration? = nil) {
        guard !isRunning, !isStarting, HKHealthStore.isHealthDataAvailable() else { return }
        isStarting = true
        pendingConfig = config
        let hrType = HKQuantityType(.heartRate)
        healthStore.requestAuthorization(toShare: [HKQuantityType.workoutType()],
                                         read: [hrType]) { ok, _ in
            // [weak self] on the Task (not the outer closure) avoids capturing
            // a mutable var across the concurrent hop (Swift 6 error).
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard ok else { self.isStarting = false; return }
                self.beginWorkout(config: self.pendingConfig)
            }
        }
    }

    private func beginWorkout(config incoming: HKWorkoutConfiguration? = nil) {
        // Reuse the remote config if provided, else build a default. Either way
        // starting the session foregrounds the app after a startWatchApp launch.
        let config: HKWorkoutConfiguration
        if let incoming { config = incoming } else {
            config = HKWorkoutConfiguration()
            config.activityType = .other
            config.locationType = .unknown
        }
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
            builder.beginCollection(withStart: start) { [weak self] ok, _ in
                // A failed begin leaves a builder in HK's Error(7) state; if we
                // kept it, the next start() would build a second one on top of
                // the wedge. Discard so a fresh session can be built next time.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isStarting = false
                    if ok { self.isRunning = true } else { self.teardown() }
                }
            }
        } catch {
            teardown()
        }
    }

    /// Release the session/builder so the next start() builds fresh instead of
    /// stacking a new builder on a wedged one.
    private func teardown() {
        session = nil
        builder = nil
        isRunning = false
        isStarting = false
    }

    func stop() {
        guard isRunning else { return }
        // Grab the HK objects locally, then release our refs immediately so the
        // next start() is clean. Drain via the async API on the MainActor —
        // avoids the @Sendable completion closures (captured-self error) and the
        // "use asynchronous alternative" warning of the completion-handler form.
        let session = self.session
        let builder = self.builder
        teardown()
        send(streaming: false)
        session?.end()
        Task { @MainActor in
            try? await builder?.endCollection(at: Date())
            _ = try? await builder?.finishWorkout()
        }
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
        // Session failed → its builder is wedged (Error(7)). Drop both so the
        // next start() rebuilds instead of no-oping on a dead session.
        Task { @MainActor in self.teardown() }
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

    /// Queued phone commands. sendMessage is dropped while unreachable, so the
    /// phone mirrors start/stop into application context — without this handler
    /// a stop issued out of range never arrived and the workout ran forever.
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let stream = applicationContext[HRKey.streaming] as? Bool else { return }
        Task { @MainActor in stream ? self.start() : self.stop() }
    }
}
