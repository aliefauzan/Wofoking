//
//  FoundationModelsMockProvider.swift
//  Wofoking — Load Away
//
//  P2 dynamic taunts via Apple's on-device Foundation Models (PRD §10.8
//  FR-MOCK-3, §12.1, Use Case "Mock User on Early Look-Back"). Returns nil
//  whenever the model is unavailable so MockingService falls back to the
//  static PhraseBank (NFR-6). Fully on-device — no network, no data leaves.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Async strategy for generating taunts. nil result = use static fallback.
protocol AsyncMockTextProvider: Sendable {
    func line(_ context: MockContext, progress: Double, failCount: Int,
              language: AppLanguage) async -> String?
}

struct FoundationModelsMockProvider: AsyncMockTextProvider {

    func line(_ context: MockContext, progress: Double, failCount: Int,
              language: AppLanguage) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let langName = language == .indonesian ? "Indonesian" : "English"
        let instructions = """
        You are a sarcastic, playful loading bar in a comedy game called Load Away.
        Taunt the player in ONE short sentence, at most 12 words. Light and funny,
        never cruel, never personal, no profanity. Reply only with the line, no quotes.
        Write in \(langName).
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: Self.prompt(context, progress: progress, failCount: failCount))
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func prompt(_ context: MockContext, progress: Double, failCount: Int) -> String {
        let pct = Int(progress)
        switch context {
        case .earlyLookBack:
            return "The player looked back too early at \(pct)%. Mock their impatience."
        case .betrayalLookBack:
            return "The player trusted the bar and looked back at \(pct)%, failing again (fail #\(failCount)). Mock their misplaced trust."
        case .fail:
            return "The player mistimed the 100% window (fail #\(failCount)). Mock them and dare a retry."
        case .win:
            return "The player finally won. Congratulate them grudgingly, as if annoyed."
        case .inviteLookBack:
            return "Lure the player into looking at the screen, pretending the bar is almost done."
        case .penalty:
            return "The player stayed away past 100%, so the bar is dropping. Gloat about lowering it."
        case .level3Tap:
            return "The player tapped Level 3, which never loads. Tell them it will never be ready."
        case .deletePrank:
            return "The player tried to delete the app but can't escape. Be ominous and playful."
        case .gaveUp:
            return "The player stared at the screen and tapped Give Up at \(pct)%. Mock them for quitting."
        case .fakeOut:
            return "The bar pretended to finish at 99% then dropped to \(pct)%. Gloat about the fake-out."
        case .peek:
            return "The player turned their head away but slid their eyes back to peek (caught #\(failCount)). Mock the cheating."
        case .heartRateSpike:
            return "The player's heart rate just spiked. Tease them for getting stressed over a loading bar."
        case .frustrated:
            return "The player is scowling at the screen in frustration. Tease them about being mad."
        case .startupNudge, .startupDemand:
            // Scripted intro lines — never AI-refined (emitted with refine:false),
            // but the switch must stay exhaustive.
            return "Tell the staring player to look away from the loading bar."
        }
    }
}
