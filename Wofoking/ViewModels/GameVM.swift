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
        case storyline     // static horror-satire intro after a stable face
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
    /// Flips true once a stable face is locked, so the Face Scan screen can run
    /// its (visual-only) glitch before advancing to the storyline.
    @Published private(set) var faceLocked = false
    /// Live count of visible faces, mirrored from the tracker for the
    /// "too many faces" warning on the Face Scan screen.
    @Published private(set) var faceCount = 0

    let gaze: GazeTracker
    let engine: GameEngine
    let level: Level

    private var bag = Set<AnyCancellable>()
    private var calibrationTimer: Timer?
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
        tracker.$visibleFaceCount.assign(to: &$faceCount)
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

    /// Hold a stable face for `calibrationStableSeconds`, then lock + play.
    private func waitForStableFace() {
        var stableSince: Date?
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                let g = self.gaze.gaze
                if g == .lookingAtScreen || g == .lookingAway {
                    if stableSince == nil { stableSince = Date() }
                    if let s = stableSince,
                       Date().timeIntervalSince(s) >= ConfigService.shared.calibrationStableSeconds,
                       self.gaze.lockCurrentFace() {   // retry next frame if mid-blink
                        t.invalidate()
                        // Stay on the Face Scan screen; the glitch runs off
                        // `faceLocked`, then the view advances to the storyline.
                        self.faceLocked = true
                    }
                } else {
                    stableSince = nil
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

    /// Called by the storyline screen when the last line has been read.
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
