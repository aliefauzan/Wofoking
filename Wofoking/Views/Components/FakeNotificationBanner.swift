//
//  FakeNotificationBanner.swift
//  Wofoking — Load Away
//
//  The on-screen decoy banner, styled to read as a real iOS notification so a
//  player who turns to check it has already lost the tick. Slides down from the
//  top; GameContainerView owns show/hide via the service's `current`.
//

import SwiftUI

struct FakeNotificationBanner: View {
    let notification: FakeNotification

    var body: some View {
        HStack(spacing: 12) {
            // App-icon stand-in: SF Symbol on the app's tint, rounded square.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(notification.tint)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: notification.iconSystemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.appName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(notification.time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .colorScheme(.light)   // real banners are light-chrome regardless of app
    }
}

#Preview(traits: .landscapeLeft) {
    ZStack(alignment: .top) {
        Color.black.ignoresSafeArea()
        FakeNotificationBanner(notification: FakeNotification(
            appName: "Messages", iconSystemName: "message.fill", tint: .green,
            title: "Mom", message: "Are you home? Call me when you can.",
            time: "now"))
            .padding(.top, 8)
            .padding(.horizontal, 40)
    }
}
