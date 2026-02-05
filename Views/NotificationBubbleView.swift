// NotificationBubbleView.swift
// MacIsland
//
// Animated notification pill that auto-dismisses.
// Shows app icon + title + subtitle in the compact state.

import SwiftUI

struct NotificationBubbleView: View {
    let notification: IslandNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: notification.icon)
                .font(.system(size: 16))
                .foregroundColor(notification.iconColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(notification.iconColor.opacity(0.15))
                )

            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(notification.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !notification.subtitle.isEmpty {
                    Text(notification.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
