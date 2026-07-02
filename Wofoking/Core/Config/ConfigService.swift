//
//  ConfigService.swift
//  Wofoking — Load Away
//
//  Single source of truth for tunable thresholds. PRD §8.2 forbids
//  hardcoding gaze/timing values inside the engine — they live here.
//

import Foundation

final class ConfigService {
    static let shared = ConfigService()
    private init() {}

    // MARK: Gaze gating (PRD §8.2)

    /// Inner neutral cone (deg). Within this the head is clearly facing the
    /// screen. Kept for debug/telemetry; the look-away decision is gated by
    /// the wider `lookAway*ThresholdDeg` below — the gap between the two is the
    /// "peek" dead zone that counts as NOT looking away (bar stays paused).
    var lookYawThresholdDeg: Double = 18
    var lookPitchThresholdDeg: Double = 18

    /// Head must turn at least this far (deg) to the SIDE off the calibrated
    /// neutral before it counts as a real look-away. Well past the 18° neutral
    /// cone so a glance can't advance the bar, but kept inside TrueDepth's
    /// reliable tracking range (~45°) — beyond that the face half-occludes and
    /// reports faceLost instead of lookingAway, so a genuine turn never reads.
    /// No-peek is enforced by the eye-gaze guard below, not by a huge angle.
    var lookAwayYawThresholdDeg: Double = 40
    /// Up/down equivalent of the yaw away-gate (looking down also = no peek).
    var lookAwayPitchThresholdDeg: Double = 30
    /// Past this yaw the screen physically can't be seen → accept look-away
    /// regardless of the (noisy at large angles) eye-gaze peek guard.
    var hardLookAwayYawThresholdDeg: Double = 55

    /// Eye-gaze peek guard. Even with the head turned past the away-gate, if
    /// the eyes (ARFaceAnchor.lookAtPoint) are still aimed back at the screen
    /// the player is peeking → treated as looking AT the screen, no progress.
    var peekGuardEnabled = true
    /// Combined head+eye gaze within this many deg of the calibrated baseline
    /// is judged "eyes on screen" (peeking). Fails open: if device eye-gaze
    /// sign differs, the guard simply won't fire and the game stays playable.
    var eyeOnScreenToleranceDeg: Double = 22
    /// Eyes-closed gating. Closing BOTH eyes advances the bar (alt to looking
    /// away). Blind = can't peek, so this path needs no eye-gaze guard.
    var eyesClosedEnabled = true
    /// Both-eye blink blendShape (0..1, min of left/right) at/above this counts
    /// as eyes shut. Min = the MORE-OPEN eye, so a one-eye peek never registers.
    var eyeClosedThreshold: Double = 0.65
    /// Eyes-closed is only trusted when the face is at most this far (metres).
    /// Past it the mesh is too low-res → `eyeBlink` drifts high with eyes OPEN
    /// (the "too far reads as eyes shut" bug). Beyond range → never eyesClosed.
    var eyeClosedMaxDistanceM: Double = 0.6
    /// Eyes-closed is only trusted within this pitch delta (deg) off the
    /// calibrated neutral. Head tilted up/down makes TrueDepth read the lid as
    /// half-shut with eyes OPEN (the "head up reads as eyes shut" bug).
    var eyeClosedMaxPitchDeltaDeg: Double = 20
    /// Stable duration before a gaze state flips (anti-flicker / blink grace).
    /// Also separates a quick involuntary blink from an intentional eyes-shut.
    var debounceSeconds: TimeInterval = 0.30
    /// How long the locked face may be absent before we declare faceLost.
    var faceLostGraceSeconds: TimeInterval = 1.2
    /// Seconds of stable face required during calibration before lock.
    var calibrationStableSeconds: TimeInterval = 1.0
    /// Continuous look-at-screen time before the Give Up button reveals.
    var giveUpRevealSeconds: TimeInterval = 5.0

    // MARK: Single-player lock (one face only)

    /// Re-acquire the locked player by face geometry when ARKit drops the
    /// original anchor (a turn-away / re-detect hands back a NEW anchor UUID).
    /// Only a face whose size signature matches the locked player rebinds the
    /// lock — bystanders never match, so the lock can't jump to another person.
    /// NOT biometric Face ID (no public API) — a geometric fingerprint that
    /// separates the seated player from bystanders, not a security-grade match.
    var faceMatchEnabled = true
    /// Max relative difference (0…1) in face WIDTH and DEPTH for a present face
    /// to count as the SAME locked player. Looser → re-acquires through more
    /// expression/distance change but risks matching a similar-sized bystander;
    /// tighter → stricter identity but may fail to re-lock the real player.
    var faceMatchToleranceRatio: Double = 0.15

    // MARK: Frozen-mesh guard

    /// A live ARKit face micro-jitters every frame. If the locked face's pose
    /// is unchanged for this long, the mesh is STUCK (a stale anchor is being
    /// replayed) — its last pose is often a turn, which would peg the bar to a
    /// false "lookingAway". A frozen mesh is treated as faceLost so the bar
    /// pauses instead of advancing on dead data.
    var staleFaceSeconds: TimeInterval = 0.8
    /// Per-frame yaw/pitch change (deg) at/below which the pose counts as "not
    /// moving" for the frozen-mesh guard. Set below TrueDepth's jitter floor so
    /// only a bit-identical replayed anchor trips it, never a live still face.
    var staleFaceEpsilonDeg: Double = 0.02
    /// Distance change (m) at/below which counts as "not moving" (frozen guard).
    var staleFaceEpsilonM: Double = 0.0005

    // MARK: Per-level rules

    func rules(for level: Level) -> LevelRules {
        switch level {
        case .one:
            // 0→100% in ~15s of accumulated look-away (PRD FR-L1-3).
            return LevelRules(lives: 3,
                              baseFillPerSecond: 100.0 / 15.0,
                              unstable: false,
                              usesCheckpoints: false,
                              winWindow: 2.0)
        case .two:
            return LevelRules(lives: nil,            // no permanent loss
                              baseFillPerSecond: 100.0 / 22.0,
                              unstable: true,
                              usesCheckpoints: true,
                              winWindow: 2.0)
        case .three:
            // Never playable; values unused.
            return LevelRules(lives: nil,
                              baseFillPerSecond: 0,
                              unstable: true,
                              usesCheckpoints: false,
                              winWindow: 2.0)
        }
    }

    // MARK: Level 2 unstable tuning

    /// Random fill multiplier range applied per tick when `unstable`.
    var unstableFillRange: ClosedRange<Double> = 0.4...1.8
    /// Expected number of taunting DROP ticks per SECOND (the engine multiplies
    /// by `dt`, so it is frame-rate independent). Was a raw per-tick probability
    /// (0.12) which, at 30 Hz, fired ~3.6 drops/sec and pinned the bar near 0.
    var unstableDropChance: Double = 1.5
    /// Drop RATE (% per second) on an unstable drop tick — scaled by `dt` like
    /// the fill, NOT an absolute per-tick %. (The old absolute 3…9 %/tick at
    /// 30 Hz overpowered the ~0.15 %/tick fill → bar stuck shaking below 10%.)
    var unstableDropAmount: ClosedRange<Double> = 30...70
    /// Heart-rate volatility multiplier when BPM is high (P2).
    var heartRateVolatilityBoost: Double = 1.5

    // MARK: Level 2 fake-out (rage bait)

    /// Master switch for the near-complete fake-out (L2 only).
    var fakeOutEnabled = true
    /// Bar must climb past this before a fake-out can spring.
    var fakeOutTriggerProgress: Double = 96
    /// Chance the fake-out springs once armed (once per climb).
    var fakeOutChance: Double = 0.6
    /// "99%… almost…" dramatic freeze before the betrayal drop.
    var fakeOutFreezeSeconds: TimeInterval = 0.7
    /// Where the bar is yanked back to after the freeze.
    var fakeOutDropTo: ClosedRange<Double> = 60...80

    // MARK: Peek tax

    /// Punish the player when caught peeking (head turned away, eyes slid back).
    var peekTaxEnabled = true
    /// % knocked off the bar each time a peek is caught.
    var peekTaxAmount: Double = 5

    // MARK: Frustration detection (facial expression — free via blendShapes)

    /// Detect a furrowed-brow / tight-frown scowl and taunt it.
    var frustrationEnabled = true
    /// 0…1 scowl score (browDown + frown/press) at/above which = frustrated.
    var frustrationThreshold: Double = 0.45
    /// Hold the scowl this long before it counts (filters fleeting expressions).
    var frustrationHoldSeconds: TimeInterval = 0.6

    // MARK: Penalty

    /// % per second the bar falls during the over-loading penalty.
    var penaltyDropPerSecond: Double = 14

    // MARK: Face-scan glitch (VISUAL ONLY — never touches gaze/tracking state)

    /// Number of times the detection reticle "glitches" to a random nearby
    /// spot after a stable face is detected, before it settles. 2…4 feels
    /// intentional-creepy without reading as a broken app.
    var glitchJumpCount: Int = 3
    /// How long each glitch jump holds (seconds). Kept short (100–300 ms).
    var glitchJumpSeconds: TimeInterval = 0.16
    /// Max random offset (points) the reticle jumps from its resting centre.
    var glitchMaxOffset: Double = 90
    /// Settle pause after the reticle snaps back before advancing to the story.
    var glitchSettleSeconds: TimeInterval = 0.9

    // MARK: Storyline (static horror-satire intro before gameplay)

    /// Delay between storyline lines appearing one-by-one.
    var storyLineInterval: TimeInterval = 1.5
    /// Delay after the final line before auto-continuing into gameplay.
    var storyAutoContinueSeconds: TimeInterval = 2.2
}
