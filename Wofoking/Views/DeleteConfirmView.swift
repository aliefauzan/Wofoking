//
//  DeleteConfirmView.swift
//  Wofoking — Load Away
//
//  Fake "Delete App" prank (PRD §10.1 FR-HOME-4..6, Use Case "Delete App").
//  Never deletes anything. Yes → taunt for 5s → bounce to Level 1.
//  Deliberately NOT styled like a system alert (App Store risk, PRD §17).
//

import SwiftUI

struct DeleteConfirmView: View {
    let onNo: () -> Void
    let onYes: () -> Void

    @EnvironmentObject private var store: PersistenceStore
    @State private var pranking = false

    private var loc: Localization { Localization(language: store.settings.language) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            if pranking {
                Text(PhraseBank.line(.deletePrank))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(40)
                    .transition(.opacity)
            } else {
                VStack(spacing: 20) {
                    Text(loc.t(.deleteConfirmTitle))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        Button(loc.t(.no), action: onNo)
                            .buttonStyle(.bordered)
                        Button(loc.t(.yes), action: startPrank)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(40)
            }
        }
    }

    private func startPrank() {
        withAnimation { pranking = true }
        HapticService.shared.play(.deletePrank)
        VoiceService.shared.speak(PhraseBank.line(.deletePrank), language: store.settings.language)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { onYes() }
    }
}
