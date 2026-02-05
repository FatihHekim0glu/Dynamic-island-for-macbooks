// HotkeyService.swift
// MacIsland
//
// Global keyboard shortcuts for controlling media playback and volume.
// Uses NSEvent.addGlobalMonitorForEvents to capture key events system-wide.
//
// IMPORTANT: Requires Accessibility permission in System Settings > Privacy & Security.
// Without it, globalMonitor silently fails (no error callback from macOS).
//
// Hotkey bindings (all require Option modifier to avoid conflicts with normal typing):
//   Option + Space       → Toggle play/pause
//   Option + Right Arrow → Next track
//   Option + Left Arrow  → Previous track
//   Option + Up Arrow    → Volume up
//   Option + Down Arrow  → Volume down

import AppKit

// MARK: - Hotkey Actions

enum HotkeyAction {
    case togglePlayPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case toggleTimer
    case togglePomodoro
}

// MARK: - HotkeyService

@MainActor
final class HotkeyService {

    var onAction: ((HotkeyAction) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init() {
        setupMonitors()
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Monitor Setup

    private func setupMonitors() {
        // Global monitor: captures key events when our app is NOT focused.
        // This is what makes hotkeys work while Spotify/Chrome/etc. are active.
        // Requires Accessibility permission — silently fails without it.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Local monitor: captures key events when our app IS focused
        // (e.g., user clicked into the expanded island panel).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            return event  // Pass through — don't consume the event.
        }
    }

    // MARK: - Key Handling

    /// Map Option+key combinations to hotkey actions.
    private func handleKeyEvent(_ event: NSEvent) {
        // Only respond when Option (Alt) is held as a modifier.
        // This prevents conflicts with normal typing, Cmd shortcuts, etc.
        guard event.modifierFlags.contains(.option) else { return }

        // Also reject if Cmd/Ctrl/Shift are held (those are other shortcuts).
        let unwantedModifiers: NSEvent.ModifierFlags = [.command, .control, .shift]
        guard event.modifierFlags.intersection(unwantedModifiers).isEmpty else { return }

        switch event.keyCode {
        case 49:   // Space bar
            onAction?(.togglePlayPause)
        case 124:  // Right arrow
            onAction?(.nextTrack)
        case 123:  // Left arrow
            onAction?(.previousTrack)
        case 126:  // Up arrow
            onAction?(.volumeUp)
        case 125:  // Down arrow
            onAction?(.volumeDown)
        case 17:   // T key
            onAction?(.toggleTimer)
        case 35:   // P key
            onAction?(.togglePomodoro)
        default:
            break
        }
    }

    // MARK: - Accessibility Check

    /// Check if the app has Accessibility permission. If not, prompt the user.
    /// Call this on app launch.
    static func checkAndRequestAccessibility() {
        if !AXIsProcessTrusted() {
            // This call shows the macOS "allow Accessibility" prompt.
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
}
