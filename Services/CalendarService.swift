// CalendarService.swift
// MacIsland
//
// Fetches upcoming calendar events using EventKit.
// Shows next event with countdown, and up to 3 upcoming events in expanded view.
// Detects video call URLs (Zoom, Meet, Teams) for quick-join buttons.
// Polls every 30s, refreshes on EKEventStoreChanged.

import Foundation
import EventKit
import Combine
import AppKit

// MARK: - Calendar Event Model

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarColor: CGColor?
    let meetingURL: URL?
    let isAllDay: Bool

    var minutesUntilStart: Int {
        Int(startDate.timeIntervalSinceNow / 60)
    }

    var isHappeningSoon: Bool {
        minutesUntilStart <= 5 && minutesUntilStart > 0
    }

    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }

    var countdownText: String {
        let minutes = minutesUntilStart
        if minutes <= 0 { return "Now" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "in \(hours)h" }
        return "in \(hours)h \(mins)m"
    }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.startDate == rhs.startDate
    }
}

// MARK: - CalendarService

@MainActor
final class CalendarService: ObservableObject {

    @Published var nextEvent: CalendarEvent?
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var isAuthorized: Bool = false

    private let eventStore = EKEventStore()
    private nonisolated(unsafe) var pollTimer: Timer?
    private var notificationObserver: Any?

    init() {
        requestAccess()
        observeChanges()
    }

    deinit {
        pollTimer?.invalidate()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Authorization

    private func requestAccess() {
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                self?.isAuthorized = granted
                if granted {
                    self?.fetchEvents()
                    self?.startPolling()
                }
            }
        }
    }

    // MARK: - Fetch Events

    func fetchEvents() {
        guard isAuthorized else { return }

        let now = Date()
        guard let endDate = Calendar.current.date(byAdding: .hour, value: 24, to: now) else { return }

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { event -> CalendarEvent in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarColor: event.calendar?.cgColor,
                    meetingURL: detectMeetingURL(from: event),
                    isAllDay: event.isAllDay
                )
            }

        let eventArray = Array(events)
        self.upcomingEvents = eventArray
        self.nextEvent = eventArray.first
    }

    // MARK: - Meeting URL Detection

    private func detectMeetingURL(from event: EKEvent) -> URL? {
        // Check event URL first
        if let url = event.url {
            if isMeetingURL(url) { return url }
        }

        // Check notes for meeting links
        let textToSearch = [event.notes, event.location].compactMap { $0 }.joined(separator: " ")
        return extractMeetingURL(from: textToSearch)
    }

    private func isMeetingURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("zoom.us") ||
               host.contains("meet.google.com") ||
               host.contains("teams.microsoft.com") ||
               host.contains("webex.com") ||
               host.contains("facetime.apple.com")
    }

    private func extractMeetingURL(from text: String) -> URL? {
        let patterns = [
            "https?://[\\w.-]*zoom\\.us/[\\w/?=&-]+",
            "https?://meet\\.google\\.com/[\\w-]+",
            "https?://teams\\.microsoft\\.com/[\\w/?=&-]+",
            "https?://[\\w.-]*webex\\.com/[\\w/?=&-]+",
            "https?://facetime\\.apple\\.com/[\\w/?=&-]+"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text),
               let url = URL(string: String(text[range])) {
                return url
            }
        }
        return nil
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEvents()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Change Observation

    private func observeChanges() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEvents()
            }
        }
    }

    // MARK: - Actions

    func openMeetingURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
