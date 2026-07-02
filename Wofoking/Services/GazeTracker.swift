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
    /// Face distance from the camera (metres) = length of the anchor transform
    /// translation. Gates the eyes-closed path: far face → low-res mesh → bogus
    /// blink, so eyesClosed is only trusted when the face is near.
    let distanceM: Double
    /// Bounding-box size (w,h,d in metres) of the face mesh in anchor-local
    /// space ≈ the player's physical face dimensions. Lightweight identity
    /// signature used to keep the lock on ONE person and reject bystanders.
    let extent: SIMD3<Double>
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
    /// Number of tracked faces currently visible. Session already tracks up to
    /// 3 faces (see `start()`), so this is a free read used only by the
    /// face-scan UI to warn "too many faces" — it never gates gameplay.
    @Published private(set) var visibleFaceCount = 0
    /// True only on hardware that supports ARKit face tracking.
    let isSupported: Bool

    /// Debug face-mesh stream. Only populated while `meshEnabled` is true.
    let meshFrame = PassthroughSubject<FaceMeshFrame, Never>()
    /// Set by the debug overlay; read on the (nonisolated) AR session thread.
    nonisolated(unsafe) var meshEnabled = false
    /// Mirror of `lockedAnchorID` readable on the (nonisolated) AR session
    /// thread, so the debug mesh overlay renders the LOCKED player's anchor —
    /// not `faceAnchors.first`, which can be a bystander/ghost and makes the
    /// wireframe detach and float beside the real face. Benign race (UUID copy).
    nonisolated(unsafe) private var meshAnchorID: UUID?

    private let config = ConfigService.shared

    #if canImport(ARKit)
    private let session = ARSession()
    /// Exposed so the gameplay view can render the real camera feed.
    var arSession: ARSession { session }
    #endif
    private var lockedAnchorID: UUID?
    private var lastSeenLocked = Date()

    // Geometry signature (face w/h/d, metres) of the locked player, captured at
    // lock. Used to re-acquire the SAME person after ARKit hands back a new
    // anchor UUID, and to reject bystanders — the lock stays on one person.
    private var lockedExtent = SIMD3<Double>(repeating: 0)

    // Frozen-mesh detection: last locked pose + when it first stopped moving.
    // NaN seed → the first frame can't read as frozen.
    private var lastLockedYaw = Double.nan
    private var lastLockedPitch = Double.nan
    private var lastLockedDistance = Double.nan
    private var lockedFrozenSince: Date?

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

    // Last yaw delta off baseline (deg) from the most recent good frame. Logged
    // when the face is lost to diagnose whether `hardLookAwayYawThresholdDeg`
    // (55°) is ever reached before TrueDepth drops the face (~45°) — Bug D.
    private var lastYawDelta = 0.0

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

    /// Capture the active player's face as the locked anchor. Returns false if
    /// no usable face this frame (none present, or the chosen face is mid-blink
    /// — locking on a blink would poison the gaze baseline and the eyes-closed
    /// reference). Caller should keep waiting and retry on a later frame.
    @discardableResult
    func lockCurrentFace() -> Bool {
        #if canImport(ARKit)
        let faces = (session.currentFrame?.anchors ?? []).compactMap { $0 as? ARFaceAnchor }
        let samples = faces.map { Self.sample(from: $0) }
        // On a re-lock (retry) a prior signature exists — prefer the SAME
        // player over a bystander who may now be more front-facing. First lock
        // has no signature → fall back to the most front-facing face.
        let pool = lockedExtent.x > 0 ? samples.filter { signatureMatches($0.extent) } : []
        let candidates = pool.isEmpty ? samples : pool
        guard let best = candidates.min(by: { $0.offAxis < $1.offAxis }),
              best.eyeBlink < config.eyeClosedThreshold else { return false }
        lockedAnchorID = best.id
        meshAnchorID = best.id      // overlay tracks the locked player
        lockedExtent = best.extent  // identity fingerprint for re-acquisition
        baseYaw = best.yaw          // neutral = where player looks now
        basePitch = best.pitch
        baseGazeYaw = best.gazeYaw
        baseGazePitch = best.gazePitch
        lastSeenLocked = Date()
        lastLockedYaw = best.yaw
        lastLockedPitch = best.pitch
        lastLockedDistance = best.distanceM
        lockedFrozenSince = nil
        isCalibrated = true
        peekCount = 0
        wasPeeking = false
        isFrustrated = false
        frustratedSince = nil
        return true
        #else
        isCalibrated = true
        return true
        #endif
    }

    /// Drop the lock so a new player can be captured (Use Case re-lock).
    func releaseLock() {
        lockedAnchorID = nil
        meshAnchorID = nil
        lockedExtent = SIMD3<Double>(repeating: 0)
        lockedFrozenSince = nil
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
        let t = anchor.transform.columns.3
        let distance = Double(simd_length(SIMD3<Float>(t.x, t.y, t.z)))
        return FaceSample(id: anchor.identifier, tracked: anchor.isTracked,
                          yaw: yaw, pitch: pitch, eyeYaw: eyeYaw, eyePitch: eyePitch,
                          eyeBlink: blinkAmount(anchor), frustration: frustrationScore(anchor),
                          distanceM: distance, extent: faceExtent(anchor.geometry))
    }

    /// Bounding-box size (w,h,d, metres) of the face mesh in anchor-local
    /// space ≈ the player's physical face dimensions. Cheap per-person
    /// signature: ARKit's mesh is a canonical topology, so the box reflects
    /// real face size. One pass over the verts; ~negligible at 30 Hz × 3 faces.
    nonisolated static func faceExtent(_ geometry: ARFaceGeometry) -> SIMD3<Double> {
        let verts = geometry.vertices
        guard let first = verts.first else { return SIMD3<Double>(repeating: 0) }
        var lo = first, hi = first
        for v in verts { lo = simd_min(lo, v); hi = simd_max(hi, v) }
        let d = hi - lo
        return SIMD3<Double>(Double(d.x), Double(d.y), Double(d.z))
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

    /// Same-player test: face WIDTH and DEPTH within tolerance of the locked
    /// signature. Height (y) is skipped — it stretches when the mouth opens, so
    /// it's expression, not identity. False until a lock signature exists.
    private func signatureMatches(_ a: SIMD3<Double>) -> Bool {
        let b = lockedExtent
        guard b.x > 0, b.z > 0, a.x > 0, a.z > 0 else { return false }
        let dw = abs(a.x - b.x) / max(a.x, b.x)
        let dd = abs(a.z - b.z) / max(a.z, b.z)
        return dw <= config.faceMatchToleranceRatio && dd <= config.faceMatchToleranceRatio
    }

    /// Apply tracked samples and update the (debounced) gaze state.
    private func process(_ samples: [FaceSample]) {
        let tracked = samples.filter { $0.tracked }.count
        if tracked != visibleFaceCount { visibleFaceCount = tracked }

        // Before lock: report presence so calibration can proceed.
        guard let id = lockedAnchorID else {
            evaluate(samples.contains { $0.tracked } ? .lookingAtScreen : .noFace)
            return
        }

        // After lock the locked face is all that matters. Follow that anchor.
        // If ARKit dropped it (turned out of view, lost tracking, OR a re-detect
        // that hands back a FRESH UUID), re-acquire the SAME player by face
        // signature — never the nearest face, so a bystander can't steal the
        // lock. Among matching faces, take the most front-facing. No match and
        // no locked anchor → face-lost grace, never a bare .noFace (the locked
        // player leaving the frame must read .faceLost, not "no face").
        var locked = samples.first(where: { $0.id == id && $0.tracked })
        if locked == nil, config.faceMatchEnabled {
            locked = samples
                .filter { $0.tracked && signatureMatches($0.extent) }
                .min(by: { $0.offAxis < $1.offAxis })
            if let rebound = locked { lockedAnchorID = rebound.id; meshAnchorID = rebound.id }   // rebind same person
        }
        guard let locked else {
            if Date().timeIntervalSince(lastSeenLocked) > config.faceLostGraceSeconds {
                #if DEBUG
                print("[GazeTracker] faceLost — last yawDelta \(String(format: "%.1f", lastYawDelta))° vs hardAway gate \(config.hardLookAwayYawThresholdDeg)°")
                #endif
                evaluate(.faceLost)
            }
            return
        }
        lastSeenLocked = Date()

        // Frozen-mesh guard: a live face always micro-jitters. If the locked
        // pose is byte-identical for staleFaceSeconds, ARKit is replaying a
        // stale anchor (mesh stuck) — its last pose is often a turn that would
        // false-advance the bar. Treat a frozen mesh as faceLost (bar pauses).
        if abs(locked.yaw - lastLockedYaw) <= config.staleFaceEpsilonDeg
            && abs(locked.pitch - lastLockedPitch) <= config.staleFaceEpsilonDeg
            && abs(locked.distanceM - lastLockedDistance) <= config.staleFaceEpsilonM {
            if lockedFrozenSince == nil { lockedFrozenSince = Date() }
        } else {
            lockedFrozenSince = nil
        }
        lastLockedYaw = locked.yaw
        lastLockedPitch = locked.pitch
        lastLockedDistance = locked.distanceM
        if let s = lockedFrozenSince, Date().timeIntervalSince(s) >= config.staleFaceSeconds {
            evaluate(.faceLost)
            return
        }

        let yawDelta = abs(locked.yaw - baseYaw)
        let pitchDelta = abs(locked.pitch - basePitch)
        lastYawDelta = yawDelta

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
        // Distance + pitch gates: ARKit's eyeBlink blendShape reads high with
        // eyes OPEN when the face is far (low-res mesh) or tilted up/down (lid
        // occludes the iris) — only trust it near and near-neutral pitch.
        let eyesClosed = config.eyesClosedEnabled
            && locked.eyeBlink >= config.eyeClosedThreshold
            && locked.distanceM <= config.eyeClosedMaxDistanceM
            && pitchDelta <= config.eyeClosedMaxPitchDeltaDeg
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

        // Debug overlay: snapshot the LOCKED player's mesh as Sendable value
        // data. Pick by locked id — not `.first`, which can be a bystander/ghost
        // and detaches the wireframe from the real face. Locked face absent this
        // frame → publish nothing (hold last pose) so it never jumps to another
        // face. Before lock (meshAnchorID nil) → fall back to first.
        if meshEnabled {
            let target = meshAnchorID.flatMap { id in faceAnchors.first { $0.identifier == id } }
                       ?? (meshAnchorID == nil ? faceAnchors.first : nil)
            if let fa = target {
                let frame = FaceMeshFrame(transform: fa.transform,
                                          vertices: fa.geometry.vertices,
                                          triangleIndices: fa.geometry.triangleIndices)
                Task { @MainActor in self.meshFrame.send(frame) }
            }
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
