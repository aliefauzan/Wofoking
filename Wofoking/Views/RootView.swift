//
//  RootView.swift
//  Wofoking — Load Away
//
//  Top-level navigation (App Flow diagram). Applies theme + language from
//  persisted settings.
//

import SwiftUI

enum Route: Hashable {
    case levelSelect
    case game(Level)
}

struct RootView: View {
    @StateObject private var store = PersistenceStore.shared
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .levelSelect:
                        LevelSelectView(path: $path)
                    case .game(let level):
                        GameContainerView(level: level, path: $path)
                    }
                }
        }
        .environmentObject(store)
        .preferredColorScheme(store.settings.theme.colorScheme)
        .tint(.white)
    }
}

#Preview { RootView() }
