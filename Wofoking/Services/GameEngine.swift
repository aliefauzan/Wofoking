//
//  GameEngine.swift
//  Wofoking — Load Away
//
//  The gameplay state machine (PRD §11, Gameplay State Machine diagram).
//  Consumes gaze from GazeTracker each tick, drives LoadingController, and
//  emits mocking text, haptics, and voice taunts at the right moments.
//

import Foundation
import Combine

@MainActor
final class GameEngine: ObservableObject {

    @Published private(set) var state: GameState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var lives: Int = 3
    /// Revealed once the player stares at the screen long enough to quit.
    @Published private(set) var canGiveUp = false
    /// Peeks caught and taxed this run (drives the on-screen shame counter).
    @Published private(set) var peekCount = 0

    let mocking: MockingService

    private let gaze: GazeTracker
    private let loader = LoadingController()
    private let haptics = HapticService.shared
    private let config = ConfigService.shared
    private let persistence = PersistenceStore.shared

    private var level: Level = .two
    private var rules: LevelRules = ConfigService.shared.rules(for: .two)

    private var timer: Timer?
    private let tick: TimeInterval = 1.0 / 30.0
    private var lastTickAt = Date()

    private var previousGaze: GazeState = .noFace
    private var lookingAtScreenSince: Date?
    private var windowStart: Date?
    /// Win-window time already spent before a face-loss froze the clock —
    /// carried across the loss so hiding the face at 100% can't reset the
    /// 2 s window into an unlimited one.
    private var windowConsumed: TimeInterval = 0
    private var failCount = 0
    private var lastInviteAt = Date.distantPast
    private var pausedForBackground = false

    // Fake-out (L2): armed once, springs near the top.
    private var fakeOutUsed = false
    private var fakeOutFreezeUntil: Date?
    // Edge tracking for peek tax / HR spike / frustration taunts.
    private var lastPeekCount = 0
    private var wasElevated = false
    private var wasFrustrated = false

    // Startup intro (FR: fake-loading grace, then two scripted look-away prompts).
    private var levelStartAt = Date()
    private var hasEverLookedAway = false
    private var startupNudgeDone = false
    private var startupDemandDone = false

    private var language: AppLanguage { persistence.settings.language }

    init(gaze: GazeTracker, mocking: MockingService? = nil) {
        self.gaze = gaze
        self.mocking = mocking ?? MockingService()   // built in MainActor init
    }

    // MARK: Lifecycle

    func startLevel(_ level: Level) {
        guard level.isPlayable else { return }
        self.level = level
        self.rules = config.rules(for: level)
        loader.reset()
        progress = 0
        failCount = 0
        lives = rules.lives ?? Int.max
        windowStart = nil
        windowConsumed = 0
        lookingAtScreenSince = nil
        canGiveUp = false
        peekCount = 0
        lastPeekCount = gaze.peekCount
        fakeOutUsed = false
        fakeOutFreezeUntil = nil
        wasElevated = false
        wasFrustrated = false
        levelStartAt = Date()
        hasEverLookedAway = false
        startupNudgeDone = false
        startupDemandDone = false
        previousGaze = gaze.gaze
        state = .lookingAtScreen
        mocking.clear()   // no leftover caption during the clean startup grace
        VoiceService.shared.enabled = persistence.settings.voiceMockingEnabled
        if persistence.settings.heartRateEnabled { HeartRateService.shared.enable() }
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Safe pause when the app leaves foreground (NFR-8). No-op if not playing.
    func pauseForBackground() {
        guard timer != nil else { return }
        stop()
        gaze.pause()
        pausedForBackground = true
        if state == .reached100, let s = windowStart {
            windowConsumed = Date().timeIntervalSince(s)   // assign — see step()
        }
        state = .faceLost
    }

    /// Resume after returning to foreground. Only acts if we paused mid-play.
    func resumeFromBackground() {
        guard pausedForBackground else { return }
        pausedForBackground = false
        gaze.start()              // restart AR session (no-op if unsupported)
        state = .lookingAtScreen
        previousGaze = gaze.gaze
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        lastTickAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            // Re-capture weak self in the Task: referencing the outer (mutable
            // weak) capture inside concurrent code is a Swift 6 error.
            Task { @MainActor [weak self] in self?.step() }
        }
    }

    // MARK: Core loop

    private func step() {
        let now = Date()
        // Clamped: a main-thread hitch (on-device AI taunt inference, thermal
        // stall) must not land seconds of fill or penalty in a single tick.
        let dt = min(now.timeIntervalSince(lastTickAt), config.maxTickDeltaSeconds)
        lastTickAt = now

        let g = gaze.gaze
        defer { previousGaze = g }

        // Startup intro: the bar fills only the real way (by looking away); we
        // just stay quiet for the first `startupGraceSeconds` — no prompt, no
        // taunts — so the opening reads as a plain loading bar before the game
        // reveals itself. `inStartupGrace` mutes every caption below.
        let sinceStart = now.timeIntervalSince(levelStartAt)
        let inStartupGrace = sinceStart < config.startupGraceSeconds

        // Reveal Give Up after a continuous stretch of looking at the screen.
        if g == .lookingAtScreen {
            if lookingAtScreenSince == nil { lookingAtScreenSince = now }
            if let s = lookingAtScreenSince,
               now.timeIntervalSince(s) >= config.giveUpRevealSeconds {
                canGiveUp = true
            }
        } else {
            lookingAtScreenSince = nil
            canGiveUp = false
        }

        // Face lost → safe pause, never a win (PRD §14). Checked BEFORE the
        // HR / frustration / peek taunts so a lost or backgrounded face can't
        // fire haptics, voice, or a bar knock.
        if g == .faceLost {
            if state != .faceLost {
                // Assign, not accumulate: windowStart is back-dated on every
                // recovery, so elapsed-since-start IS the total consumed time
                // (+= would double-count across repeated loss/recovery cycles).
                if state == .reached100, let s = windowStart {
                    windowConsumed = Date().timeIntervalSince(s)
                }
                state = .faceLost
                if !inStartupGrace {
                    mocking.emit(.inviteLookBack, speak: false, language: language)
                }
            }
            return
        }
        if state == .faceLost {
            // Recovered. If the bar was already full, restore the win window —
            // a face-loss at 100% must not silently void the win — else resume.
            if loader.progress >= 100 {
                // Resume with only the REMAINING window budget — a fresh
                // windowStart here made covering the camera at 100% an
                // infinitely extendable win window.
                state = .reached100
                windowStart = Date().addingTimeInterval(-windowConsumed)
            } else {
                state = .lookingAtScreen
            }
        }

        // Grace elapsed: mockingly nudge, then demand, the player to look away —
        // until they finally do (first look-away ends the intro). Both scripted
        // lines are spoken verbatim (refine: false) so the AI never rewrites them.
        if isAdvancing(g) { hasEverLookedAway = true }
        if !hasEverLookedAway {
            if !startupNudgeDone, sinceStart >= config.startupGraceSeconds {
                startupNudgeDone = true
                mocking.emit(.startupNudge, progress: loader.progress,
                             speak: persistence.settings.voiceMockingEnabled,
                             refine: false, language: language)
            } else if startupNudgeDone, !startupDemandDone,
                      sinceStart >= config.startupGraceSeconds + config.startupDemandDelaySeconds {
                startupDemandDone = true
                mocking.emit(.startupDemand, progress: loader.progress,
                             speak: persistence.settings.voiceMockingEnabled,
                             refine: false, language: language)
            }
        }

        // Heart-rate driven volatility (L2): elevated BPM → more chaotic bar.
        let elevated = persistence.settings.heartRateEnabled && HeartRateService.shared.isElevated
        loader.heartRateHigh = elevated
        if elevated && !wasElevated && !inStartupGrace {    // rising edge → sabotage taunt
            mocking.emit(.heartRateSpike, progress: loader.progress,
                         speak: persistence.settings.voiceMockingEnabled, language: language)
        }
        wasElevated = elevated

        // Frustration taunt: caught scowling at the screen (rising edge only).
        if gaze.isFrustrated && !wasFrustrated && !inStartupGrace {
            mocking.emit(.frustrated, progress: loader.progress,
                         speak: persistence.settings.voiceMockingEnabled, language: language)
        }
        wasFrustrated = gaze.isFrustrated

        // Peek tax: punish each newly-caught peek while actively playing.
        if config.peekTaxEnabled, !inStartupGrace, gaze.peekCount > lastPeekCount,
           state == .lookingAway || state == .lookingAtScreen {
            lastPeekCount = gaze.peekCount
            onPeek()
        } else {
            lastPeekCount = gaze.peekCount
        }

        switch state {
        case .reached100:
            handleWindow(g: g)
        case .overLoadPenalty:
            handlePenalty(g: g, dt: dt)
        default:
            handlePlay(g: g, dt: dt)
        }
    }

    /// Both ways to advance the bar: head turned away (no peek) OR eyes shut.
    private func isAdvancing(_ g: GazeState) -> Bool {
        g == .lookingAway || g == .eyesClosed
    }

    private func handlePlay(g: GazeState, dt: TimeInterval) {
        if isAdvancing(g) {
            if !isAdvancing(previousGaze) {             // just started advancing
                state = .lookingAway
                haptics.play(.loadingToggle)
                if rules.usesCheckpoints { loader.makeCheckpoint() }
                maybeInvite()
            }
            if maybeFakeOut() { syncProgress(); return }   // frozen/yanked this tick
            loader.advance(dt, rules: rules)
            syncProgress()
            if loader.isComplete { enterWindow() }
            return
        }

        switch g {
        case .lookingAtScreen:
            if isAdvancing(previousGaze) {              // looked back / opened eyes early
                state = .lookingAtScreen
                haptics.play(.loadingToggle)
                if loader.progress < 100 {
                    let ctx: MockContext = (Date().timeIntervalSince(lastInviteAt) < 3)
                        ? .betrayalLookBack : .earlyLookBack
                    mocking.emit(ctx, progress: loader.progress, failCount: failCount,
                                 speak: persistence.settings.voiceMockingEnabled,
                                 language: language)
                    registerFail()   // FR-L1-5: look back at the wrong time costs a life
                }
            }
            // Bar paused while looking (the core rule).

        case .noFace, .faceLost, .lookingAway, .eyesClosed:
            break   // advancing handled above; others are no-ops here
        }
    }

    /// Caught peeking: knock the bar back, escalate the mock, shame counter.
    private func onPeek() {
        peekCount += 1
        loader.applyPeekTax(config.peekTaxAmount)
        syncProgress()
        haptics.play(.barDrop)
        mocking.emit(.peek, progress: loader.progress, failCount: peekCount,
                     speak: persistence.settings.voiceMockingEnabled, language: language)
    }

    /// L2 rage bait: near the top, fake completion, freeze, then betray.
    /// Returns true while the bar is frozen/yanked so the normal advance is
    /// skipped this tick.
    private func maybeFakeOut() -> Bool {
        guard rules.unstable, config.fakeOutEnabled else { return false }
        let now = Date()

        // Holding the fake 99%, then dropping when the freeze elapses.
        if let until = fakeOutFreezeUntil {
            if now < until { return true }            // keep the bar pinned
            fakeOutFreezeUntil = nil
            loader.fakeDrop(to: Double.random(in: config.fakeOutDropTo))
            haptics.play(.barDrop)
            mocking.emit(.fakeOut, progress: loader.progress,
                         speak: persistence.settings.voiceMockingEnabled, language: language)
            return true
        }

        // Arm + spring once when the bar nears completion.
        if !fakeOutUsed, loader.progress >= config.fakeOutTriggerProgress,
           Double.random(in: 0...1) < config.fakeOutChance {
            fakeOutUsed = true
            loader.freezeNearComplete()
            fakeOutFreezeUntil = now.addingTimeInterval(config.fakeOutFreezeSeconds)
            haptics.play(.dramatic100)               // fake "you made it!" buzz
            return true
        }
        return false
    }

    private func enterWindow() {
        state = .reached100
        windowConsumed = 0
        windowStart = Date()
        haptics.play(rules.unstable ? .dramatic100 : .medium)
    }

    private func handleWindow(g: GazeState) {
        // Win if the player is looking during the 2s window.
        if g == .lookingAtScreen {
            win()
            return
        }
        if let start = windowStart, Date().timeIntervalSince(start) > rules.winWindow {
            // Stayed away too long → over-loading penalty.
            state = .overLoadPenalty
            mocking.emit(.penalty, progress: 100, failCount: failCount,
                         speak: persistence.settings.voiceMockingEnabled, language: language)
            haptics.play(.barDrop)
            if !rules.unstable { registerFail() }   // L1 timing fail costs a life
        }
    }

    private func handlePenalty(g: GazeState, dt: TimeInterval) {
        // Bar visibly falls; only resolves when the player looks back.
        loader.dropPenalty(dt)
        syncProgress()
        if g == .lookingAtScreen {
            if rules.usesCheckpoints { loader.snapBackToCheckpoint(); syncProgress() }
            state = .lookingAtScreen
        }
    }

    // MARK: Outcomes

    private func registerFail() {
        guard rules.lives != nil else { return }   // L2 has no permanent loss
        failCount += 1
        lives = max(0, lives - 1)
        haptics.play(.strongFail)
        mocking.emit(.fail, progress: loader.progress, failCount: failCount,
                     speak: persistence.settings.voiceMockingEnabled, language: language)
        if lives == 0 {
            state = .retry
            stop()
        }
    }

    private func win() {
        state = .win
        haptics.play(.strongWin)
        mocking.emit(.win, progress: 100, failCount: failCount,
                     speak: persistence.settings.voiceMockingEnabled, language: language)
        if let next = Level(rawValue: level.rawValue + 1) {
            persistence.unlock(next)
        }
        persistence.lastLevel = level
        state = .levelCompleted
        stop()
    }

    /// Player tapped Give Up: stop the loop, mock them, hand back to the view
    /// (which routes to the main menu).
    func giveUp() {
        guard timer != nil else { return }
        stop()
        canGiveUp = false
        state = .gaveUp
        mocking.emit(.gaveUp, progress: loader.progress, failCount: failCount,
                     speak: persistence.settings.voiceMockingEnabled, language: language)
    }

    private func maybeInvite() {
        // Silent during the startup grace — keep the plain-loading illusion.
        guard Date().timeIntervalSince(levelStartAt) >= config.startupGraceSeconds else { return }
        // Occasionally lure the player to look back early.
        guard Double.random(in: 0...1) < 0.25 else { return }
        lastInviteAt = Date()
        mocking.emit(.inviteLookBack, progress: loader.progress,
                     speak: persistence.settings.voiceMockingEnabled, language: language)
    }

    private func syncProgress() { progress = loader.progress }

    // MARK: Manual fallback passthrough (Simulator)

    var gazeIsSupported: Bool { gaze.isSupported }
    func manualLookAway(_ away: Bool) { gaze.setManualLookingAway(away) }
}
