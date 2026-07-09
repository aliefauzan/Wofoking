//
//  JumpscareView.swift
//  Wofoking — Load Away
//
//  Full-screen payoff shown the instant the player "wins" (bar hits 100% / the
//  win window resolves). The red scream face slams in with the scream clip,
//  then the parting insult plays, then `onComplete` fires and the container
//  routes back to the main menu. No buttons — you don't get to dismiss it.
//

import SwiftUI
import Combine

struct JumpscareView: View {
    let onComplete: () -> Void

    @StateObject private var driver = JumpscareDriver()
    @State private var pop = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("Jumpscare")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                // Slam in oversized, then settle — the classic jumpscare snap.
                .scaleEffect(pop ? 1.0 : 1.35)
                .opacity(pop ? 1 : 0)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear {
            withAnimation(.easeOut(duration: 0.12)) { pop = true }
            driver.start(onComplete: onComplete)
        }
    }
}

/// Owns the JumpscareService for the view's lifetime (a bare `let` service
/// would be released before the audio chain finishes).
final class JumpscareDriver: ObservableObject {
    private let service = JumpscareService()
    private var started = false

    func start(onComplete: @escaping () -> Void) {
        guard !started else { return }   // onAppear can re-fire; run the chain once
        started = true
        service.run(completion: onComplete)
    }
}
