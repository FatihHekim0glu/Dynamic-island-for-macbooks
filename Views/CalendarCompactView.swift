// CalendarCompactView.swift
// MacIsland
//
// Compact calendar display: color dot + event title + countdown.

import SwiftUI

struct CalendarCompactView: View {
    @ObservedObject var calendarService: CalendarService

    var body: some View {
        if let event = calendarService.nextEvent {
            HStack(spacing: 8) {
                // Calendar color dot
                Circle()
                    .fill(cgColorToSwiftUI(event.calendarColor))
                    .frame(width: 8, height: 8)

                // Event title
                MarqueeText(
                    event.title,
                    font: .system(size: 12, weight: .medium),
                    color: .white,
                    speed: 30,
                    delayBeforeScroll: 2.0
                )
                .frame(height: 16)

                Spacer(minLength: 4)

                // Countdown
                Text(event.countdownText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(event.isHappeningSoon ? .orange : .white.opacity(0.7))
                    .animation(.easeInOut, value: event.isHappeningSoon)
            }
            .padding(.horizontal, 14)
        }
    }

    private func cgColorToSwiftUI(_ cgColor: CGColor?) -> Color {
        guard let cgColor = cgColor else { return .blue }
        return Color(cgColor: cgColor)
    }
}
