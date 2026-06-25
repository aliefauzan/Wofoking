//
//  PhraseBank.swift
//  Wofoking — Load Away
//
//  Static mocking copy (PRD §22, FR-MOCK-1). MVP fallback for the
//  Foundation Models dynamic taunts (P2). Tone: light, never personal.
//

import Foundation

enum MockContext {
    case earlyLookBack      // looked before 100%
    case fail               // wrong-time look-back (L1 life lost)
    case win
    case inviteLookBack     // taunt to lure player back
    case betrayalLookBack   // mock player who trusted the bar and looked back
    case penalty            // stayed away past 100%, bar dropping
    case level3Tap          // tapped the impossible level
    case deletePrank        // "you think you can run from us?"
    case gaveUp             // player tapped Give Up
}

struct PhraseBank {
    static func line(_ context: MockContext) -> String {
        (bank[context] ?? ["…"]).randomElement()!
    }

    private static let bank: [MockContext: [String]] = [
        .earlyLookBack: [
            "Too early. Classic.",
            "You looked too soon.",
            "The loading bar saw you.",
            "99% confidence. 0% patience.",
            "You blinked. It noticed.",
        ],
        .fail: [
            "Almost. But almost is still failure.",
            "You were one second away from greatness.",
            "The loading bar is disappointed, but not surprised.",
            "Try again. The loading bar enjoys this.",
        ],
        .win: [
            "Fine. You win. This time.",
            "The loading bar concedes. Barely.",
            "Loading complete. Joy not included.",
        ],
        .inviteLookBack: [
            "Go on, look. I dare you.",
            "Don't you want to see the progress?",
            "It's almost done. Come check.",
        ],
        .betrayalLookBack: [
            "You trusted the loading bar. Mistake.",
            "It moved. You didn't.",
            "You and patience are clearly not friends.",
        ],
        .penalty: [
            "Because you didn't trust me, I'll decrease it back.",
            "100% was there. You were not.",
            "Watch it fall. You earned this.",
        ],
        .level3Tap: [
            "Still loading.",
            "Come back later.",
            "Level 3 is preparing itself emotionally.",
            "99%. Forever.",
            "This level is not ready to be perceived.",
        ],
        .deletePrank: [
            "You think you can run from us?",
        ],
        .gaveUp: [
            "Giving up? The loading bar expected nothing less.",
            "Quitter. The bar will remember this.",
            "You looked too long and lost your nerve. Typical.",
            "Surrender accepted. Disappointment noted.",
        ],
    ]
}
