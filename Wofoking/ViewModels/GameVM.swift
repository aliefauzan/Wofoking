//
//  GameVM.swift
//  Wofoking — Load Away
//
//  Coordinates permission → calibration → gameplay for a level. Owns the
//  GazeTracker and GameEngine and re-publishes their state for the views.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class GameVM: ObservableObject {

    enum Phase: Equatable {
        case permission
        case denied
        case unsupported
        case calibrating   // Face Detection / Face Scan screen
        case storyline     // horror-satire video cinematic after a stable face
        case playing
    }

    @Published private(set) var phase: Phase = .permission
    @Published private(set) var engineState: GameState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var lives: Int = 3
    @Published private(set) var mockLine: String = ""
    @Published private(set) var canGiveUp = false
    @Published private(set) var gazeState: GazeState = .noFace
    @Published private(set) var peekCount = 0
    /// True when a face other than the locked player is in frame after lock,
    /// so the HUD can warn "different face". Mirrored from the tracker.
    @Published private(set) var identityRejected = false
    /// Flips true once a stable face is locked, so the Face Scan screen can run
    /// its (visual-only) glitch before advancing to the storyline.
    @Published private(set) var faceLocked = false
    /// Live count of visible faces, mirrored from the tracker for the
    /// "too many faces" warning on the Face Scan screen.
    @Published private(set) var faceCount = 0
    /// Guard readouts mirrored for the debug badge (eye-ray-to-camera angle,
    /// last identity shape err) — on-device threshold validation/tuning.
    @Published private(set) var debugConeDeg: Double = 180
    @Published private(set) var debugShapeErr: Double = 0
    @Published private(set) var debugYawDeg: Double = 0

    let gaze: GazeTracker
    let engine: GameEngine
    let level: Level

    private var bag = Set<AnyCancellable>()
    private var calibrationTimer: Timer?
    private var stableSince: Date?
    private var didBegin = false

    init(level: Level) {
        self.level = level
        let tracker = GazeTracker()
        self.gaze = tracker
        self.engine = GameEngine(gaze: tracker)

        engine.$state.assign(to: &$engineState)
        engine.$progress.assign(to: &$progress)
        engine.$lives.assign(to: &$lives)
        engine.$canGiveUp.assign(to: &$canGiveUp)
        engine.$peekCount.assign(to: &$peekCount)
        engine.mocking.$currentLine.assign(to: &$mockLine)
        tracker.$gaze.assign(to: &$gazeState)
        tracker.$identityRejected.assign(to: &$identityRejected)
        tracker.$visibleFaceCount.assign(to: &$faceCount)
        tracker.$debugConeDeg.assign(to: &$debugConeDeg)
        tracker.$debugShapeErr.assign(to: &$debugShapeErr)
        tracker.$debugYawDeg.assign(to: &$debugYawDeg)
    }

    // MARK: Flow

    func begin() {
        guard !didBegin else { gaze.requestPermission(); return }
        didBegin = true
        gaze.requestPermission()
        gaze.$permission
            .receive(on: RunLoop.main)
            .sink { [weak self] perm in self?.handlePermission(perm) }
            .store(in: &bag)
    }

    private func handlePermission(_ perm: GazeTracker.Permission) {
        switch perm {
        case .unknown: phase = .permission
        case .denied:  phase = .denied
        case .granted:
            guard gaze.isSupported else {
                // Simulator / non-TrueDepth → no face scan/glitch, but the
                // storyline still plays so the flow stays testable, then manual.
                gaze.manualCalibrate()
                phase = .storyline
                return
            }
            phase = .calibrating
            gaze.start()
            waitForStableFace()
        }
    }

    /// Require EXACTLY one face, held stable for `calibrationStableSeconds`,
    /// then lock + advance. More than one visible face (or none) resets the
    /// timer so the lock can't fire while a bystander is in frame — the Face
    /// Scan screen shows the "too many faces" block until the frame is clean.
    private func waitForStableFace() {
        stableSince = nil
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Re-capture weak self; mutable state lives on the (MainActor)
            // instance and the timer is invalidated via its property — a
            // captured local var / non-Sendable Timer are Swift 6 errors.
            Task { @MainActor [weak self] in
                guard let self else { return }
                let g = self.gaze.gaze
                let single = self.gaze.visibleFaceCount == 1
                if single && (g == .lookingAtScreen || g == .lookingAway) {
                    if self.stableSince == nil { self.stableSince = Date() }
                    if let s = self.stableSince,
                       Date().timeIntervalSince(s) >= ConfigService.shared.calibrationStableSeconds,
                       self.gaze.lockCurrentFace() {   // retry next frame if mid-blink
                        self.calibrationTimer?.invalidate()
                        // Stay on the Face Scan screen; the glitch runs off
                        // `faceLocked`, then the view advances to the storyline.
                        self.faceLocked = true
                    }
                } else {
                    self.stableSince = nil
                }
            }
        }
    }

    private func startPlaying() {
        phase = .playing
        engine.startLevel(level)
    }

    /// Called by the Face Scan screen once its glitch effect finishes.
    func finishFaceScan() {
        guard phase == .calibrating else { return }
        phase = .storyline
    }

    /// Called by the storyline cinematic when the video reaches the end.
    func finishStoryline() {
        guard phase == .storyline else { return }
        startPlaying()
    }

    // MARK: Manual fallback control

    var isManual: Bool { !gaze.isSupported }
    func manualLookAway(_ away: Bool) { engine.manualLookAway(away) }
    func giveUp() { engine.giveUp() }

    func retry() {
        gaze.lockCurrentFace()   // re-baseline; player may have moved since first lock
        engine.startLevel(level)
        phase = .playing
    }

    func teardown() {
        calibrationTimer?.invalidate()
        engine.stop()
        gaze.pause()
    }
}
