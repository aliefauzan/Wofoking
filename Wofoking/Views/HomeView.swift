//
//  HomeView.swift
//  Wofoking — Load Away
//
//  Home screen (PRD §10.1, concept art). LOAD AWAY title over the scenery
//  with Start / Level / Settings / Delete App.
//

import SwiftUI

struct HomeView: View {
    @Binding var path: [Route]
    @EnvironmentObject private var store: PersistenceStore
    @State private var showDelete = false

    private var loc: Localization { Localization(language: store.settings.language) }

    var body: some View {
        ZStack {
            LoadAwayBackground()

            // Landscape: title on the left, menu on the right.
            HStack(spacing: 48) {
                titleBlock
                    .frame(maxWidth: .infinity)
                menu
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 24)
        }
        .navigationBarBackButtonHidden(true)
        .overlay {
            if showDelete {
                DeleteConfirmView(
                    onNo: { showDelete = false },
                    onYes: {
                        showDelete = false
                        store.resetToLevelOne()
                        path.append(.game(.one))   // joke: bounce to Level 1
                    })
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: -4) {
            Text("LOAD")
                .font(.system(size: 64, weight: .black, design: .default))
            Text("AWAY")
                .font(.system(size: 40, weight: .light, design: .default))
                .tracking(8)
        }
        .foregroundStyle(.white)
        .shadow(radius: 8)
    }

    private var menu: some View {
        VStack(spacing: 16) {
            MenuButton(title: loc.t(.start)) { path.append(.game(store.lastLevel)) }
            MenuButton(title: loc.t(.level)) { path.append(.levelSelect) }
            MenuButton(title: loc.t(.settings)) { path.append(.settings) }
            MenuButton(title: loc.t(.deleteApp), destructive: true) { showDelete = true }
        }
        .frame(maxWidth: 320)
    }
}

struct MenuButton: View {
    let title: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25)))
                .foregroundStyle(destructive ? Color(red: 1, green: 0.6, blue: 0.6) : .white)
        }
    }
}
