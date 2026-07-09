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
    var lookAwayYawThresholdDeg: Double = 50
    /// Up/down equivalent of the yaw away-gate (looking down also = no peek).
    var lookAwayPitchThresholdDeg: Double = 30
    /// Past this yaw the screen physically can't be seen even with maximal
    /// eye counter-rotation (~45°), so the peek guard is bypassed. Field
    /// screenshots show modern TrueDepth still tracking face + eyes well past
    /// 43°, and the camera-cone guard stays reliable at angle — so the bypass
    /// starts only where peeking is anatomically impossible.
    var hardLookAwayYawThresholdDeg: Double = 60

    /// Eye-gaze peek guard. Even with the head turned past the away-gate, if
    /// the eyes (ARFaceAnchor.lookAtPoint) are still aimed back at the screen
    /// the player is peeking → treated as looking AT the screen, no progress.
    var peekGuardEnabled = true
    /// Peek = the eye-gaze ray points within this many deg of the ray from
    /// the face to the front camera (≈ the phone screen). Pose-INDEPENDENT —
    /// the old baseline-relative head+eye sum missed head-up/eyes-down and
    /// large-yaw side-eye peeks because eye counter-rotation under-measures
    /// in exactly those poses. Screen subtends ~±10° at 40 cm; slack covers
    /// lookAtPoint error. Fails open (180°) when no camera transform.
    var eyeOnScreenConeDeg: Double = 18
    /// Eyes-closed gating. Closing BOTH eyes advances the bar (alt to looking
    /// away). Blind = can't peek, so this path needs no eye-gaze guard.
    var eyesClosedEnabled = true
    /// Both-eye blink blendShape (0..1, min of left/right) at/above this counts
    /// as eyes shut. Min = the MORE-OPEN eye, so a one-eye peek never registers.
    /// Kept high because a squint still sees the screen: lids slitted through
    /// lashes read ~0.65–0.85 with vision intact, and this path skips the
    /// eye-gaze peek guard entirely — only a true closure (~0.9+) may pass.
    var eyeClosedThreshold: Double = 0.85
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
    /// Seconds of stable face required during calibration before lock. Higher =
    /// the box lingers scanning longer before it detects/locks (feels less rushed).
    var calibrationStableSeconds: TimeInterval = 2.5
    /// Continuous look-at-screen time before the Give Up button reveals.
    var giveUpRevealSeconds: TimeInterval = 5.0

    // MARK: Startup intro (fake-loading grace before the first look-away prompt)

    /// At level start the bar acts like a genuine loading screen for this long —
    /// no look-away prompt, no reactive taunts — so the player believes it's
    /// really loading. Then the first mocking nudge fires (`.startupNudge`).
    var startupGraceSeconds: TimeInterval = 7.0
    /// If the player is STILL staring this long after the nudge (never looked
    /// away yet), the firmer follow-up prompt fires (`.startupDemand`).
    var startupDemandDelaySeconds: TimeInterval = 5.0
    /// Where the clean fake-loading bar climbs to over the grace window. Kept
    /// mid-way (not 100) so it reads as loading-in-progress and leaves real
    /// look-away distance to the finish once the mechanic reveals itself.
    var startupFakeLoadTarget: Double = 60.0
    /// Upper bound on a single engine tick's dt. Without it a main-thread
    /// hitch (on-device AI taunt inference, thermal stall) lands seconds of
    /// fill or penalty in the one tick that fires after the stall.
    var maxTickDeltaSeconds: TimeInterval = 0.2

    // MARK: Single-player lock (one face only)

    /// Re-acquire the locked player by face geometry when ARKit drops the
    /// original anchor (a turn-away / re-detect hands back a NEW anchor UUID).
    /// Only a face whose size signature matches the locked player rebinds the
    /// lock — bystanders never match, so the lock can't jump to another person.
    /// NOT biometric Face ID (no public API) — a geometric fingerprint that
    /// separates the seated player from bystanders, not a security-grade match.
    var faceMatchEnabled = true
    /// Max relative difference (0…1) in face WIDTH and DEPTH for a present face
    /// to count as the SAME locked player. The old 0.15 accepted nearly any
    /// adult (face-width spread between people is only ~±8%), which let a
    /// substitute player take over mid-game. Size is now one of TWO gates —
    /// the mesh shape vector below is the discriminating one.
    var faceMatchToleranceRatio: Double = 0.08
    /// Max mean relative difference (0…1) between the locked player's mesh
    /// shape vector and a candidate face's (per-vertex distance-from-centroid
    /// profile on ARKit's canonical topology, scale-normalised). Same person
    /// across expressions stays low; a different face's profile differs.
    /// Looser → survives more expression change but weakens the imposter gate.
    /// Set from on-device badge readings: same player measured err 0.016–0.022
    /// (even mid-turn), an imposter measured 0.036 and slipped through the old
    /// 0.05. Tightened to 0.015: the pre-lock frame AVERAGING (preLockSignature*)
    /// + richer 48-point signature pull the real player's err well below the old
    /// single-frame 0.016–0.022 band, so this hard cut rejects a substitute
    /// aggressively. If the REAL player ever reads above 0.015 on the debug badge
    /// (`id`) and gets dropped, loosen this back toward 0.02.
    var faceShapeToleranceRatio: Double = 0.015
    /// Continuous identity check runs whenever the head is within this yaw/
    /// pitch off the calibrated neutral (deg). Set high — past the look-away
    /// gate — so a substitute can't dodge the check by playing turned-away
    /// (anchor-local shape is pose-independent, so verification is valid at
    /// these angles). Only true near-profile beyond this is skipped, where
    /// ARKit's mesh fit is genuinely noisy.
    var identityVerifyMaxYawDeg: Double = 50
    var identityVerifyMaxPitchDeg: Double = 50
    /// A sustained identity mismatch must persist this long before the lock is
    /// dropped — absorbs a transient bad frame / expression spike without
    /// letting a real substitute keep the lock.
    var identityGraceSeconds: TimeInterval = 0.4
    /// Frames of the stable, single-face pre-lock window averaged into the
    /// stored fingerprint. One frame is noisy; a mean over ~15 frames is a
    /// clean reference, so the REAL player matches more consistently and a
    /// substitute's error stays reliably above `faceShapeToleranceRatio`
    /// instead of dipping under it on a lucky noisy frame.
    var preLockSignatureFrames = 15
    /// Minimum buffered frames before the averaged signature is used; below
    /// this the single lock frame is kept (e.g. an instant lock with no window).
    var preLockMinSignatureFrames = 5

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
            // Retired: L1 is no longer playable (startLevel guards on
            // isPlayable). Rules kept for reference only.
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

    // MARK: Fake notification (the "look at your phone" trap)

    /// Master switch for the fake system-notification banner. It springs while
    /// the player is looking AWAY (bar loading) — the sound + haptic + banner
    /// bait them into glancing back at the phone, which pauses the bar and
    /// usually costs an early-look-back. Pure social-engineering distraction.
    var fakeNotifEnabled = true
    /// Random gap (seconds) between fake-notification attempts. Each attempt
    /// only actually fires if the player is currently looking away, so the
    /// felt cadence is looser than this — banners land only on the traps.
    var fakeNotifIntervalRange: ClosedRange<TimeInterval> = 7...16
    /// The player must be looking away (bar advancing) for at least this long
    /// before a banner is allowed — a notification the instant they turn away
    /// reads as scripted; a beat later feels like a real push arriving.
    var fakeNotifMinLookAwaySeconds: TimeInterval = 1.2
    /// How long the banner stays on screen before it slides away on its own.
    var fakeNotifDurationSeconds: TimeInterval = 4.0
    /// Play an iOS-style chime with the banner (AudioToolbox system sound). The
    /// sound is the real lure — it works even while the head is fully turned.
    var fakeNotifSoundEnabled = true

    // MARK: Face-scan glitch (VISUAL ONLY — never touches gaze/tracking state)

    /// After the single face is locked, the box picks ONE top corner and jumps
    /// face → corner → face this many times before settling. Randomised in
    /// [min…max] so it never looks scripted.
    var glitchJumpCountMin: Int = 4
    var glitchJumpCountMax: Int = 6
    /// Duration (seconds) of a single tear (face → corner, or corner → face),
    /// randomised per jump in [min…max] so the rhythm never feels metronomic.
    var glitchMoveMinSeconds: TimeInterval = 0.12
    var glitchMoveMaxSeconds: TimeInterval = 0.30
    /// Pause (seconds) the box lingers at the corner / on the face between tears,
    /// also randomised per jump so it reads organic, not scripted.
    var glitchHoldMinSeconds: TimeInterval = 0.18
    var glitchHoldMaxSeconds: TimeInterval = 0.55
    /// Per-jump random drift (points) added to the corner so it never lands on
    /// the exact same pixel twice.
    var glitchCornerDrift: Double = 18
    /// Upward offset (points) of the corner the box tears to.
    var glitchTopOffset: Double = 250
    /// Horizontal offset (points) — the box picks EITHER the top-left OR the
    /// top-right corner (one, for the whole sequence), never both.
    var glitchSideOffset: Double = 165
    /// Settle pause after the box snaps back onto the face before advancing to
    /// the story — long enough that the locked box is clearly resting on the face.
    var glitchSettleSeconds: TimeInterval = 1.3

    // MARK: Storyline (static horror-satire intro before gameplay)

    /// Per-character delay while a caption types out (typewriter effect).
    /// Tuned so the longest line still finishes typing within its ~3.6 s window.
    var storyTypeCharSeconds: TimeInterval = 0.045
    /// Hold after a sentence finishes typing, before the page turns to the next.
    var storyLineInterval: TimeInterval = 1.6
    /// Cross-fade duration when swapping one sentence page for the next.
    var storyPageFadeSeconds: TimeInterval = 0.7
    /// Delay after the final line before auto-continuing into gameplay.
    var storyAutoContinueSeconds: TimeInterval = 2.2
    /// Fade duration for a caption appearing/disappearing over the video.
    var storyCaptionFadeSeconds: TimeInterval = 0.45
}
