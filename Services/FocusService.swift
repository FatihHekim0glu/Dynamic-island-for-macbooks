// FocusService.swift
// MacIsland
//
// Monitors and toggles Do Not Disturb / Focus mode.
// Uses DistributedNotificationCenter to observe DND state changes.
// Toggles DND via NSAppleScript calling Shortcuts or defaults.

import Foundation
import Combine
import AppKit

@MainActor
final class FocusService: ObservableObject {

    @Published var isDNDActive: Bool = false

    private nonisolated(unsafe) var pollTimer: Timer?
    private var notificationObserver: Any?

    init() {
        checkDNDStatus()
        observeChanges()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Check DND Status

    func checkDNDStatus() {
        // Read DND state from UserDefaults
        // On macOS 14+, Focus/DND state is stored in the notification center preferences
        let script = NSAppleScript(source: """
            try
                do shell script "defaults read com.apple.controlcenter 'NSStatusItem Visible FocusModes'"
            on error
                return "0"
            end try
        """)

        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        let value = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"

        // Also check the assertion state via defaults
        let assertionScript = NSAppleScript(source: """
            try
                set focusState to do shell script "plutil -extract dnd_prefs raw ~/Library/Preferences/com.apple.ncprefs.plist 2>/dev/null || echo ''"
                if focusState is not "" then
                    return "1"
                else
                    return "0"
                end if
            on error
                return "0"
            end try
        """)

        let assertionResult = assertionScript?.executeAndReturnError(&error)
        let assertionValue = assertionResult?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"

        // Use either signal
        let active = value == "1" || assertionValue == "1"
        if isDNDActive != active {
            isDNDActive = active
        }
    }

    // MARK: - Toggle DND

    func toggleDND() {
        let script: NSAppleScript?
        if isDNDActive {
            // Turn off DND
            script = NSAppleScript(source: """
                tell application "System Events"
                    tell process "ControlCenter"
                        -- Open Control Center, toggle Focus
                        try
                            do shell script "shortcuts run 'Toggle Focus' 2>/dev/null || true"
                        end try
                    end tell
                end tell
            """)
        } else {
            // Turn on DND
            script = NSAppleScript(source: """
                try
                    do shell script "shortcuts run 'Toggle Focus' 2>/dev/null || true"
                end try
            """)
        }

        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        // Optimistic update
        isDNDActive.toggle()

        // Refresh after a delay to get actual state
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            checkDNDStatus()
        }
    }

    // MARK: - Observation

    private func observeChanges() {
        // Listen for DND state change notifications
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.notificationcenterui.dndStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkDNDStatus()
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkDNDStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
