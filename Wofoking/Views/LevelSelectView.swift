//
//  LevelSelectView.swift
//  Wofoking — Load Away
//
//  Level Select (PRD §10.2). L2 locked until L1 cleared; L3 is the fake
//  "always loading" level with a random percentage each visit.
//

import SwiftUI

struct LevelSelectView: View {
    @Binding var path: [Route]
    @EnvironmentObject private var store: PersistenceStore
    @StateObject private var vm = LevelVM()

    private var loc: Localization { Localization(language: store.settings.language) }

    var body: some View {
        ZStack {
            LoadAwayBackground()
            HStack(spacing: 18) {
                ForEach(vm.rows) { row in
                    levelCard(row)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
        }
        .navigationTitle(loc.t(.level))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.refresh() }
        .alert(vm.jokeMessage ?? "", isPresented: .constant(vm.jokeMessage != nil)) {
            Button("OK") { vm.jokeMessage = nil }
        }
    }

    @ViewBuilder
    private func levelCard(_ row: LevelRow) -> some View {
        Button {
            switch row.level {
            case .three: vm.tapLevelThree()
            default: if row.unlocked { path.append(.game(row.level)) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.level.title).font(.headline)
                    Text(subtitle(row)).font(.caption).opacity(0.8)
                }
                Spacer()
                if !row.unlocked && row.level != .three {
                    Image(systemName: "lock.fill")
                }
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .opacity(row.unlocked || row.level == .three ? 1 : 0.5)
        }
        .disabled(!row.unlocked && row.level != .three)
    }

    private func subtitle(_ row: LevelRow) -> String {
        if let pct = row.fakePercent { return "Downloading… \(pct)%" }
        if !row.unlocked { return loc.t(.levelLocked) }
        return row.level.subtitle
    }
}
