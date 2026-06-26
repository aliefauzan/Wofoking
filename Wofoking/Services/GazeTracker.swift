//
//  GazeTracker.swift
//  Wofoking — Load Away
//
//  ARKit face tracking → gaze classification (Use Cases "Lock Player Face",
//  "Track Look-Away"). Captures the active player's face anchor; only that
//  anchor controls the bar. Other faces are bystanders. Includes debounce,
//  blink grace, and face-lost handling (PRD §8.2, §14). No face data stored
//  (NFR-4). Falls back to manual control when face tracking is unsupported
//  (Simulator / non-TrueDepth) so the game stays playable.
//

import Foundation
import Combine
import AVFoundation
import simd
#if canImport(ARKit)
import ARKit
#endif

/// Sendable snapshot of a tracked face, extracted off the main actor so we
/// never hand a non-Sendable ARFaceAnchor across the actor boundary.
struct FaceSample: Sendable {
    let id: UUID
    let tracked: Bool
    let yaw: Double
    let pitch: Double
    /// Eye-gaze direction RELATIVE TO THE HEAD (deg), from ARFaceAnchor
    /// lookAtPoint. A peeking player counter-rotates the eyes against the head
    /// turn, so `yaw + eyeYaw` (the combined gaze) swings back toward neutral.
    let eyeYaw: Double
    let eyePitch: Double
    /// Both-eye blink amount (0…1) = MIN of left/right blendShape, i.e. the
    /// more-open eye. High only when BOTH eyes shut → a one-eye peek stays low.
    let eyeBlink: Double
    /// Scowl score (0…1) from brow-furrow + frown/press blendShapes. Drives the
    /// frustration taunt — free emotion signal, already on the TrueDepth anchor.
    let frustration: Double
    var offAxis: Double { abs(yaw) + abs(pitch) }
    /// Where the player is actually looking = head pose + eye offset.
    var gazeYaw: Double { yaw + eyeYaw }
    var gazePitch: Double { pitch + eyePitch }
}

/// Sendable snapshot of the live face mesh for the debug overlay. Value-type
/// arrays only — never crosses the actor hop carrying a raw ARFaceGeometry.
struct FaceMeshFrame: Sendable {
    let transform: simd_float4x4
    let vertices: [SIMD3<Float>]
    let triangleIndices: [Int16]
}

@MainActor
final class GazeTracker: NSObject, ObservableObject {

    enum Permission { case unknown, granted, denied }

    @Published private(set) var permission: Permission = .unknown
    @Published private(set) var gaze: GazeState = .noFace
    @Published private(set) var isCalibrated = false
    /// Monotonic count of caught peeks (head turned away but eyes slid back to
    /// the screen). The engine reads the delta to tax peeks. Reset on lock.
    @Published private(set) var peekCount = 0
    /// True while the player holds a frustrated scowl (browDown + frown/press).
    @Published private(set) var isFrustrated = false
    /// True only on hardware that supports ARKit face tracking.
    let isSupported: Bool

    /// Debug face-mesh stream. Only populated while `meshEnabled` is true.
    let meshFrame = PassthroughSubject<FaceMeshFrame, Never>()
    /// Set by the debug overlay; read on the (nonisolated) AR session thread.
    nonisolated(unsafe) var meshEnabled = false

    private let config = ConfigService.shared

    #if canImport(ARKit)
    private let session = ARSession()
    /// Exposed so the gameplay view can render the real camera feed.
    var arSession: ARSession { session }
    #endif
    private var lockedAnchorID: UUID?
    private var lastSeenLocked = Date()

    // Calibrated neutral pose captured at lock. Gaze is judged relative to
    // this baseline, not absolute world axes — so the player's natural
    // holding angle / landscape orientation doesn't read as "looking away".
    private var baseYaw = 0.0
    private var basePitch = 0.0
    // Neutral combined gaze (head+eye) at lock — the peek guard's "on screen"
    // reference, so a tilted/landscape hold doesn't bias eye-gaze either.
    private var baseGazeYaw = 0.0
    private var baseGazePitch = 0.0

    // Debounce bookkeeping.
    private var candidate: GazeState = .noFace
    private var candidateSince = Date()

    // Peek / frustration edge tracking.
    private var wasPeeking = false
    private var frustratedSince: Date?

    override init() {
        #if canImport(ARKit)
        isSupported = ARFaceTrackingConfiguration.isSupported
        #else
        isSupported = false
        #endif
        super.init()
        #if canImport(ARKit)
        session.delegate = self
        #endif
    }

    // MARK: Permission

    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = .granted
        case .denied, .restricted: permission = .denied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in self?.permission = granted ? .granted : .denied }
            }
        @unknown default: permission = .denied
        }
    }

    // MARK: Session lifecycle

    func start() {
        guard permission == .granted else { return }
        #if canImport(ARKit)
        guard isSupported else { return }
        let cfg = ARFaceTrackingConfiguration()
        cfg.maximumNumberOfTrackedFaces = 3   // detect bystanders too
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        #endif
    }

    func pause() {
        #if canImport(ARKit)
        session.pause()
        #endif
        commit(.faceLost)
    }

    /// Capture the active player's face as the locked anchor.
    func lockCurrentFace() {
        #if canImport(ARKit)
        let faces = (session.currentFrame?.anchors ?? []).compactMap { $0 as? ARFaceAnchor }
        let samples = faces.map { Self.sample(from: $0) }
        if let best = samples.min(by: { $0.offAxis < $1.offAxis }) {
            lockedAnchorID = best.id
            baseYaw = best.yaw          // neutral = where player looks now
            basePitch = best.pitch
            baseGazeYaw = best.gazeYaw
            baseGazePitch = best.gazePitch
            lastSeenLocked = Date()
            isCalibrated = true
            peekCount = 0
            wasPeeking = false
            isFrustrated = false
            frustratedSince = nil
        }
        #else
        isCalibrated = true
        #endif
    }

    /// Drop the lock so a new player can be captured (Use Case re-lock).
    func releaseLock() {
        lockedAnchorID = nil
        isCalibrated = false
    }

    // MARK: Manual fallback (Simulator / unsupported)

    /// Drives gaze when ARKit face tracking is unavailable so the core loop
    /// is still testable. Wired to a UI button in GameplayView.
    func setManualLookingAway(_ away: Bool) {
        guard !isSupported else { return }
        commit(away ? .lookingAway : .lookingAtScreen)
    }

    func manualCalibrate() {
        guard !isSupported else { return }
        isCalibrated = true
        commit(.lookingAtScreen)
    }

    // MARK: Classification

    #if canImport(ARKit)
    /// Pure, off-actor-safe conversion of a face anchor to a Sendable sample.
    nonisolated static func sample(from anchor: ARFaceAnchor) -> FaceSample {
        let (yaw, pitch) = yawPitch(anchor.transform)
        let (eyeYaw, eyePitch) = eyeAngles(anchor.lookAtPoint)
        return FaceSample(id: anchor.identifier, tracked: anchor.isTracked,
                          yaw: yaw, pitch: pitch, eyeYaw: eyeYaw, eyePitch: eyePitch,
                          eyeBlink: blinkAmount(anchor), frustration: frustrationScore(anchor))
    }

    /// Scowl score (0…1): furrowed brow OR a tight frown/press. Pure read of
    /// ARKit blendShapes — no extra framework, no new permission.
    nonisolated static func frustrationScore(_ anchor: ARFaceAnchor) -> Double {
        let b = anchor.blendShapes
        func v(_ k: ARFaceAnchor.BlendShapeLocation) -> Double { b[k]?.doubleValue ?? 0 }
        let brow = (v(.browDownLeft) + v(.browDownRight)) / 2
        let frown = (v(.mouthFrownLeft) + v(.mouthFrownRight)) / 2
        let press = (v(.mouthPressLeft) + v(.mouthPressRight)) / 2
        return min(1, 0.6 * brow + 0.4 * max(frown, press))
    }

    /// Both-eye blink from ARKit blendShapes (0 = open, 1 = shut). Returns the
    /// MIN of the two eyes so a single open eye keeps it low (no one-eye peek).
    /// Threshold is applied later on the main actor (ConfigService isolation).
    nonisolated static func blinkAmount(_ anchor: ARFaceAnchor) -> Double {
        let l = anchor.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0
        let r = anchor.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0
        return min(l, r)
    }

    /// Eye-gaze yaw/pitch (deg) in face-anchor space. `lookAtPoint` is the
    /// estimated convergence point of the eyes; +z points out of the face, so
    /// the offset in x/y vs z gives how far the eyes are turned off head-center.
    nonisolated static func eyeAngles(_ p: simd_float3) -> (Double, Double) {
        let z = max(0.01, Double(p.z))   // guard div-by-zero; eyes look forward (+z)
        let yaw = atan2(Double(p.x), z) * 180 / .pi
        let pitch = atan2(Double(p.y), z) * 180 / .pi
        return (yaw, pitch)
    }
    #endif

    /// Yaw/pitch in degrees from a face transform.
    nonisolated static func yawPitch(_ m: simd_float4x4) -> (Double, Double) {
        let yaw = atan2(Double(m.columns.0.z), Double(m.columns.2.z)) * 180 / .pi
        let pitch = asin(max(-1, min(1, Double(-m.columns.1.z)))) * 180 / .pi
        return (yaw, pitch)
    }

    /// Apply tracked samples and update the (debounced) gaze state.
    private func process(_ samples: [FaceSample]) {
        // Before lock: report presence so calibration can proceed.
        guard let id = lockedAnchorID else {
            evaluate(samples.contains { $0.tracked } ? .lookingAtScreen : .noFace)
            return
        }

        // After lock the locked face is all that matters. Missing because it
        // turned out of view, lost tracking, OR the whole frame went empty
        // (player walked off) → run the face-lost grace, never a bare .noFace.
        // (Empty-frame check lives HERE, after the lock guard, so leaving the
        // frame reports .faceLost — the old early `samples.isEmpty` return
        // fired .noFace and the locked player stopped being detected.)
        guard let locked = samples.first(where: { $0.id == id }), locked.tracked else {
            if Date().timeIntervalSince(lastSeenLocked) > config.faceLostGraceSeconds {
                evaluate(.faceLost)
            }
            return
        }
        lastSeenLocked = Date()

        let yawDelta = abs(locked.yaw - baseYaw)
        let pitchDelta = abs(locked.pitch - basePitch)

        // Head turned off the calibrated neutral — to the side (yaw) or down
        // (pitch). Below this gate (incl. the 18–40° "peek" band) the bar stays
        // paused, killing the old false positives from a small glance.
        let turnedAway = yawDelta >= config.lookAwayYawThresholdDeg
                      || pitchDelta >= config.lookAwayPitchThresholdDeg

        // Past the hard angle the screen can't be seen at all → always away,
        // skip the peek guard (lookAtPoint gets noisy near profile and would
        // otherwise false-block a real turn — the "already away, no detect" bug).
        let hardAway = yawDelta >= config.hardLookAwayYawThresholdDeg

        // Peek guard (moderate turns only): head turned but eyes slid back to
        // the screen. Combined gaze (head+eye) near neutral baseline = peeking.
        let peeking = config.peekGuardEnabled && turnedAway && !hardAway
            && abs(locked.gazeYaw - baseGazeYaw) <= config.eyeOnScreenToleranceDeg
            && abs(locked.gazePitch - baseGazePitch) <= config.eyeOnScreenToleranceDeg

        // Count each caught peek on its rising edge (cheat detected).
        if peeking && !wasPeeking { peekCount += 1 }
        wasPeeking = peeking

        updateFrustration(locked.frustration)

        // Eyes shut (both) advances the bar regardless of head pose — no peek
        // possible blind, so it skips the gaze guard. Takes priority over the
        // turn/peek decision. The debounce in evaluate() ignores quick blinks.
        let eyesClosed = config.eyesClosedEnabled && locked.eyeBlink >= config.eyeClosedThreshold
        if eyesClosed {
            evaluate(.eyesClosed)
            return
        }

        evaluate((turnedAway && !peeking) ? .lookingAway : .lookingAtScreen)
    }

    /// Rising/falling edge of a held scowl, with a hold to filter fleeting faces.
    private func updateFrustration(_ value: Double) {
        guard config.frustrationEnabled else { return }
        if value >= config.frustrationThreshold {
            if frustratedSince == nil { frustratedSince = Date() }
            if let s = frustratedSince,
               Date().timeIntervalSince(s) >= config.frustrationHoldSeconds, !isFrustrated {
                isFrustrated = true
            }
        } else {
            frustratedSince = nil
            if isFrustrated { isFrustrated = false }
        }
    }

    /// Debounced state commit. Ignores sub-threshold flicker / blinks.
    private func evaluate(_ raw: GazeState) {
        if raw != candidate {
            candidate = raw
            candidateSince = Date()
            return
        }
        let needed = raw == .faceLost ? config.faceLostGraceSeconds : config.debounceSeconds
        if Date().timeIntervalSince(candidateSince) >= needed {
            commit(raw)
        }
    }

    private func commit(_ state: GazeState) {
        guard state != gaze else { return }
        gaze = state
    }
}

#if canImport(ARKit)
extension GazeTracker: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let faceAnchors = anchors.compactMap { $0 as? ARFaceAnchor }
        let samples = faceAnchors.map(GazeTracker.sample)

        // Debug overlay: snapshot the first face's mesh as Sendable value data.
        if meshEnabled, let fa = faceAnchors.first {
            let frame = FaceMeshFrame(transform: fa.transform,
                                      vertices: fa.geometry.vertices,
                                      triangleIndices: fa.geometry.triangleIndices)
            Task { @MainActor in self.meshFrame.send(frame) }
        }

        Task { @MainActor in self.process(samples) }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let removed = Set(anchors.map { $0.identifier })
        Task { @MainActor in
            if let id = self.lockedAnchorID, removed.contains(id) {
                self.evaluate(.faceLost)
            }
        }
    }
}
#endif
