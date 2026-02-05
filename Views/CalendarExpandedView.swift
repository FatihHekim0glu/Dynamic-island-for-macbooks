// CalendarExpandedView.swift
// MacIsland
//
// Expanded calendar view: next 3 events timeline with join-meeting buttons.

import SwiftUI

struct CalendarExpandedView: View {
    @ObservedObject var calendarService: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text("Upcoming")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }

            if calendarService.upcomingEvents.isEmpty {
                HStack {
                    Spacer()
                    Text("No upcoming events")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                // Event list (up to 3)
                ForEach(calendarService.upcomingEvents.prefix(3)) { event in
                    eventRow(event)
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(cgColorToSwiftUI(event.calendarColor))
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(formatEventTime(event))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Countdown or "Now" badge
            if event.isHappeningNow {
                Text("Now")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            } else {
                Text(event.countdownText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(event.isHappeningSoon ? .orange : .white.opacity(0.5))
            }

            // Join meeting button
            if let url = event.meetingURL {
                Button(action: { calendarService.openMeetingURL(url) }) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                        .padding(4)
                        .background(Circle().fill(Color.blue.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Join meeting")
            }
        }
    }

    private func formatEventTime(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }

    private func cgColorToSwiftUI(_ cgColor: CGColor?) -> Color {
        guard let cgColor = cgColor else { return .blue }
        return Color(cgColor: cgColor)
    }
}
