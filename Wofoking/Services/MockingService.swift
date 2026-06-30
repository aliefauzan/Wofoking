//
//  MockingService.swift
//  Wofoking — Load Away
//
//  Produces mocking lines for on-screen text + voice. A static PhraseBank
//  line is shown instantly; if a Foundation Models provider is configured and
//  available, it asynchronously refines the line in place (FR-MOCK-1/3, NFR-6).
//

import Foundation
import Combine

/// Synchronous strategy (static bank). Always available.
protocol MockTextProvider {
    func line(_ context: MockContext, progress: Double, failCount: Int) -> String
}

/// MVP provider — random pick from the static bank.
struct StaticMockProvider: MockTextProvider {
    func line(_ context: MockContext, progress: Double, failCount: Int) -> String {
        PhraseBank.line(context)
    }
}

@MainActor
final class MockingService: ObservableObject {
    private let provider: MockTextProvider
    private let ai: AsyncMockTextProvider?

    /// Latest line to display in the gameplay UI.
    @Published private(set) var currentLine: String = ""

    /// Monotonic token so a slow AI reply can't overwrite a newer emit.
    private var emitToken = 0

    init(provider: MockTextProvider? = nil,
         ai: AsyncMockTextProvider? = nil) {
        self.provider = provider ?? StaticMockProvider()
        self.ai = ai ?? FoundationModelsMockProvider()
    }

    /// Show a static line immediately and speak it in the Tes voice; then refine
    /// the on-screen text via AI. The refinement is **caption-only** — it is not
    /// spoken, because only static bank lines have a pre-generated Tes clip and
    /// the device can't synthesise new audio at runtime. This keeps one clean,
    /// zero-latency Tes utterance per event with no voice mismatch.
    @discardableResult
    func emit(_ context: MockContext,
              progress: Double = 0,
              failCount: Int = 0,
              speak: Bool = false,
              language: AppLanguage = .english) -> String {
        emitToken &+= 1
        let token = emitToken

        let staticLine = provider.line(context, progress: progress, failCount: failCount)
        currentLine = staticLine
        if speak { VoiceService.shared.speak(staticLine, language: language) }

        if let ai {
            Task { [weak self] in
                let refined = await ai.line(context, progress: progress,
                                            failCount: failCount, language: language)
                guard let self, let refined, token == self.emitToken else { return }
                self.currentLine = refined   // caption-only; the Tes clip already spoke
            }
        }
        return staticLine
    }
}
