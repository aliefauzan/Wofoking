//
//  FakeNotificationService.swift
//  Wofoking — Load Away
//
//  Springs a fake push banner (see FakeNotification) while the player is
//  looking AWAY from the phone — bar loading, head turned — so the chime +
//  haptic + banner bait them into glancing back. Glancing back pauses the bar
//  and usually trips an early-look-back, which is the whole point: it makes
//  the player betray their own run. Posts nothing to the OS; the banner is
//  drawn by GameContainerView from `current`.
//
//  Cadence: a fast poll gates on the caller's `shouldFire` (== looking away)
//  AND a minimum look-away hold, so a banner never lands the instant the head
//  turns (which would read as scripted) and only ever appears mid-load.
//

import Foundation
import Combine
import AudioToolbox

@MainActor
final class FakeNotificationService: ObservableObject {

    /// The banner currently on screen, or nil. Views animate on this.
    @Published private(set) var current: FakeNotification?

    private let config = ConfigService.shared
    private let haptics = HapticService.shared

    private var poll: Timer?
    private var dismissTask: Task<Void, Never>?
    private var language: AppLanguage = .english
    /// Returns true while the player is looking away (bar advancing) and the
    /// game is actively playing — the only window a bait may fire.
    private var shouldFire: () -> Bool = { false }

    /// When the current look-away streak began; nil while facing the screen.
    private var lookAwaySince: Date?
    /// Earliest time the next bait may spring (random gap between attempts).
    private var nextFireAt = Date.distantFuture

    /// SMS-received tri-tone — the stock iOS notification chime, no bundled
    /// asset needed. The sound is the real lure: it works with the head turned.
    private let chimeID: SystemSoundID = 1007

    // MARK: Lifecycle

    func start(language: AppLanguage, shouldFire: @escaping () -> Bool) {
        guard config.fakeNotifEnabled else { return }
        self.language = language
        self.shouldFire = shouldFire
        lookAwaySince = nil
        armNextFire()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        dismissTask?.cancel()
        dismissTask = nil
        lookAwaySince = nil
        nextFireAt = .distantFuture
        if current != nil { current = nil }
    }

    // MARK: Scheduling

    private func armNextFire() {
        nextFireAt = Date().addingTimeInterval(.random(in: config.fakeNotifIntervalRange))
    }

    private func tick() {
        let now = Date()

        // Track the look-away streak so we can require a minimum hold — the gate
        // resets the moment the player faces the screen again.
        if shouldFire() {
            if lookAwaySince == nil { lookAwaySince = now }
        } else {
            lookAwaySince = nil
            return
        }

        guard current == nil,                         // one banner at a time
              now >= nextFireAt,                      // random gap elapsed
              let since = lookAwaySince,
              now.timeIntervalSince(since) >= config.fakeNotifMinLookAwaySeconds
        else { return }

        fire()
        armNextFire()
    }

    private func fire() {
        current = FakeNotificationBank.random(language: language)
        haptics.play(.notification)
        if config.fakeNotifSoundEnabled { AudioServicesPlaySystemSound(chimeID) }

        let shownID = current?.id
        let duration = config.fakeNotifDurationSeconds
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.current?.id == shownID else { return }
            self.current = nil
        }
    }
}
