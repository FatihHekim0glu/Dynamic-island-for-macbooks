// IslandContentProvider.swift
// MacIsland
//
// Protocol defining a content provider for the Dynamic Island.
// Each feature (media, timer, calendar, etc.) conforms to this protocol
// and registers with IslandViewModel. The highest-priority active provider
// drives what's shown in compact/expanded states.

import SwiftUI

// MARK: - Content Type

/// Identifies the type of content a provider supplies.
/// Used for tab selection in expanded view and for display prioritization.
enum IslandContentType: String, CaseIterable, Identifiable {
    case media
    case timer
    case pomodoro
    case calendar
    case notification
    case system
    case battery
    case network
    case privacy
    case focus
    case bluetooth

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .media:        return "music.note"
        case .timer:        return "timer"
        case .pomodoro:     return "leaf.fill"
        case .calendar:     return "calendar"
        case .notification: return "bell.fill"
        case .system:       return "cpu"
        case .battery:      return "battery.100"
        case .network:      return "wifi"
        case .privacy:      return "eye.fill"
        case .focus:        return "moon.fill"
        case .bluetooth:    return "airpodspro"
        }
    }

    var label: String {
        switch self {
        case .media:        return "Media"
        case .timer:        return "Timer"
        case .pomodoro:     return "Pomodoro"
        case .calendar:     return "Calendar"
        case .notification: return "Notification"
        case .system:       return "System"
        case .battery:      return "Battery"
        case .network:      return "Network"
        case .privacy:      return "Privacy"
        case .focus:        return "Focus"
        case .bluetooth:    return "Bluetooth"
        }
    }
}

// MARK: - Idle Indicator

/// A small indicator shown in the idle capsule (e.g., battery %, privacy dots, DND moon).
struct IdleIndicator: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let text: String?
    let pulse: Bool

    init(id: String, icon: String, color: Color, text: String? = nil, pulse: Bool = false) {
        self.id = id
        self.icon = icon
        self.color = color
        self.text = text
        self.pulse = pulse
    }
}

// MARK: - Content Provider Protocol

/// Protocol for island content providers.
/// Each provider manages its own service, publishes state changes,
/// and supplies views for compact/expanded rendering.
@MainActor
protocol IslandContentProvider: ObservableObject {
    /// The type of content this provider supplies.
    var contentType: IslandContentType { get }

    /// Priority for compact view display. Higher = shows first.
    /// Notifications: 90, Timer: 70, Media: 50, Calendar: 30
    var priority: Int { get }

    /// Whether this provider currently has content to display.
    var hasActiveContent: Bool { get }

    /// Whether this provider should trigger compact state expansion.
    /// e.g., media playing = true, calendar with no imminent event = false
    var shouldShowCompact: Bool { get }

    /// Optional indicators to show in the idle capsule.
    var idleIndicators: [IdleIndicator] { get }

    /// The compact view for this provider.
    @ViewBuilder var compactView: AnyView { get }

    /// The expanded view for this provider.
    @ViewBuilder var expandedView: AnyView { get }

    /// Auto-dismiss duration (nil = stays until content changes).
    /// Used by notification bubbles to auto-dismiss after N seconds.
    var autoDismissAfter: TimeInterval? { get }
}

// MARK: - Default Implementations

extension IslandContentProvider {
    var autoDismissAfter: TimeInterval? { nil }
    var idleIndicators: [IdleIndicator] { [] }
    var shouldShowCompact: Bool { hasActiveContent }
}
