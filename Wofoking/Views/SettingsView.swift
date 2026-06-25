//
//  SettingsView.swift
//  Wofoking — Load Away
//
//  Settings (PRD §10.7): language, appearance, heart rate (P2), voice mute.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsVM()

    private var loc: Localization { vm.loc }

    var body: some View {
        Form {
            Section(loc.t(.language)) {
                Picker(loc.t(.language), selection: $vm.settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section(loc.t(.theme)) {
                Picker(loc.t(.theme), selection: $vm.settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Toggle(loc.t(.voiceMocking), isOn: $vm.settings.voiceMockingEnabled)
                Toggle(loc.t(.heartRate), isOn: $vm.settings.heartRateEnabled)
            } footer: {
                Text("Heart rate is optional and used only to make the game feel more dramatic. Load Away is not a medical or fitness app.")
            }
            Section {
                Toggle(loc.t(.debugFaceMesh), isOn: $vm.settings.debugFaceMesh)
            } header: {
                Text(loc.t(.debug))
            } footer: {
                Text(loc.t(.debugFaceMeshFooter))
            }
        }
        .navigationTitle(loc.t(.settings))
        .navigationBarTitleDisplayMode(.inline)
    }
}
