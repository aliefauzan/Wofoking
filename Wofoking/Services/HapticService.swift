//
//  HapticService.swift
//  Wofoking — Load Away
//
//  Core Haptics feedback (PRD §10.9). Degrades silently on devices
//  without a haptic engine.
//

import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif
import UIKit

enum HapticKind {
    case light          // L1 @75%
    case medium         // L1 @90%
    case strongWin
    case strongFail
    case checkpoint     // L2 small
    case barDrop        // L2 / penalty
    case dramatic100    // L2 @100%
    case loadingToggle  // start/stop
    case deletePrank
    case notification   // fake push banner — mimics the iOS notify buzz
}

final class HapticService {
    static let shared = HapticService()

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    #endif
    private let supportsHaptics: Bool

    private init() {
        #if canImport(CoreHaptics)
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if supportsHaptics {
            engine = try? CHHapticEngine()
            try? engine?.start()
        }
        #else
        supportsHaptics = false
        #endif
    }

    func play(_ kind: HapticKind) {
        guard supportsHaptics else { fallback(kind); return }
        #if canImport(CoreHaptics)
        // The fake push imitates the system notify buzz: two crisp taps ~0.1s
        // apart, not one transient.
        if kind == .notification {
            let taps = [0.0, 0.1].map { t in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.9),
                    .init(parameterID: .hapticSharpness, value: 0.9),
                ], relativeTime: t)
            }
            if let pattern = try? CHHapticPattern(events: taps, parameters: []),
               let player = try? engine?.makePlayer(with: pattern) {
                try? player.start(atTime: 0)
            }
            return
        }
        let (intensity, sharpness): (Float, Float)
        switch kind {
        case .light:         (intensity, sharpness) = (0.3, 0.3)
        case .medium:        (intensity, sharpness) = (0.6, 0.5)
        case .checkpoint:    (intensity, sharpness) = (0.35, 0.7)
        case .loadingToggle: (intensity, sharpness) = (0.4, 0.4)
        case .barDrop:       (intensity, sharpness) = (0.8, 0.9)
        case .strongFail:    (intensity, sharpness) = (1.0, 1.0)
        case .strongWin:     (intensity, sharpness) = (1.0, 0.4)
        case .dramatic100:   (intensity, sharpness) = (1.0, 0.8)
        case .deletePrank:   (intensity, sharpness) = (0.9, 1.0)
        case .notification:  (intensity, sharpness) = (0.9, 0.9)   // handled above
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine?.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
        #endif
    }

    /// UIKit feedback fallback when Core Haptics is unavailable.
    private func fallback(_ kind: HapticKind) {
        switch kind {
        case .strongWin:  UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .strongFail: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .notification: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .barDrop, .dramatic100, .deletePrank:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .medium:     UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default:          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
