//
//  SettingsView.swift
//  Wofoking — Load Away
//
//  Settings (PRD §10.7): language, appearance, heart rate (P2), voice mute.
//
//  Styled to the Figma "settings coba coba" export: a centred dark card
//  (#161616 @ 98%, red-gradient border) floating over the home scene as a
//  popup — dim scrim behind, an X close button, and a centred "Settings"
//  title with a full-width rule under it. Not a pushed navigation page.
//

import SwiftUI

struct SettingsView: View {
    /// Dismiss the popup (owned by the presenting view).
    let onClose: () -> Void

    @StateObject private var vm = SettingsVM()

    private var loc: Localization { vm.loc }

    var body: some View {
        ZStack {
            // Dim scrim — tap outside the card to dismiss.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            ScrollView(.vertical, showsIndicators: false) {
                card
                    .frame(maxWidth: 460)
                    .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            titleRule

            SettingRow(title: loc.t(.language)) {
                Picker("", selection: $vm.settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .tint(Card.accent)
            }

            divider

            SettingRow(title: loc.t(.theme)) {
                Picker("", selection: $vm.settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }

            divider

            SettingRow(title: loc.t(.voiceMocking)) {
                redToggle($vm.settings.voiceMockingEnabled)
            }

            divider

            SettingRow(title: loc.t(.heartRate)) {
                redToggle($vm.settings.heartRateEnabled)
            }

            footer("Heart rate is optional and used only to make the game feel more dramatic. Load Away is not a medical or fitness app.")
                .padding(.bottom, 8)

            divider
            

            SettingRow(title: loc.t(.debugFaceMesh), subtitle: loc.t(.debug)) {
                redToggle($vm.settings.debugFaceMesh)
            }

            footer(loc.t(.debugFaceMeshFooter))
                .padding(.bottom, 8)
        }
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(white: 0.086).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(0xBC1A16), Color(0x560C0A)],
                        startPoint: .top, endPoint: .bottom
                    ).opacity(0.5),
                    lineWidth: 2.5
                )
        )
        .shadow(color: Color(0xDB0700).opacity(0.35), radius: 26)
        .padding(.horizontal, 16)
        
    }

    // MARK: - Header (centred title + trailing X)

    private var header: some View {
        ZStack {
            Text(loc.t(.settings))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
            }
        }
        .padding(.horizontal, Card.pad)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Full-width rule under the title (SVG `line` at y=123.5).
    private var titleRule: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(height: 1)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
            .padding(.leading, Card.pad)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Card.pad)
            .padding(.top, 6)
    }

    private func redToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .tint(Card.accent)
    }
}

// MARK: - Row

private struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Card.pad)
        .frame(minHeight: 48)
    }
}

// MARK: - Style tokens

private enum Card {
    static let pad: CGFloat = 18
    static let accent = Color(0xDB0700)
}

private extension Color {
    /// 0xRRGGBB literal → Color (matches the Figma export palette).
    init(_ hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}

#Preview(traits: .landscapeLeft) {
    ZStack {
        ForestMenuBackground()
        SettingsView(onClose: {})
    }
}
