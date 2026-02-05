// AppDelegate.swift
// MacIsland
//
// Application lifecycle manager. Responsible for:
// 1. Hiding the Dock icon (LSUIElement behavior via code, backed by Info.plist).
// 2. Creating and showing the island window on launch.
// 3. Setting up global keyboard shortcuts via HotkeyService.
// 4. Setting up a status bar item (menu bar icon) for quit/preferences.
//
// WHY AppDelegate instead of pure SwiftUI @main App?
// Because we need fine-grained control over NSWindow/NSPanel creation that
// the SwiftUI App lifecycle doesn't expose. The SwiftUI WindowGroup would
// create a standard titled window, which we don't want.

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var viewModel: IslandViewModel?
    private var hotkeyService: HotkeyService?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── 1. Hide from Dock ──
        // Even though Info.plist has LSUIElement = true, we reinforce it here
        // so that the app never shows a Dock tile. This is the programmatic equivalent.
        NSApp.setActivationPolicy(.accessory)

        // ── 2. Create the Island ──
        let vm = IslandViewModel()
        self.viewModel = vm

        let controller = IslandWindowController(viewModel: vm)
        controller.showIsland()
        self.windowController = controller

        // ── 3. Global Keyboard Shortcuts ──
        setupHotkeys(viewModel: vm)

        // ── 4. Status Bar Item (menu bar icon) ──
        setupStatusItem()

        print("[MacIsland] Launched. Notch detected: \(ScreenUtility.detectNotch().hasNotch)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when the panel is "closed" — we're a background utility.
        return false
    }

    // MARK: - Hotkeys

    private func setupHotkeys(viewModel vm: IslandViewModel) {
        // Request Accessibility permission if not already granted.
        // Without it, global hotkeys silently fail.
        HotkeyService.checkAndRequestAccessibility()

        let hotkeys = HotkeyService()
        hotkeys.onAction = { [weak vm] action in
            guard let vm else { return }
            switch action {
            case .togglePlayPause:
                vm.togglePlayPause()
            case .nextTrack:
                vm.nextTrack()
            case .previousTrack:
                vm.previousTrack()
            case .volumeUp:
                let current = vm.volumeService.volume
                vm.setVolume(min(current + 0.05, 1.0))
            case .volumeDown:
                let current = vm.volumeService.volume
                vm.setVolume(max(current - 0.05, 0.0))
            case .toggleTimer:
                vm.timerService.togglePause()
            case .togglePomodoro:
                vm.pomodoroService.togglePause()
            }
        }
        self.hotkeyService = hotkeys
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // SF Symbol for the menu bar icon.
            button.image = NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: "MacIsland")
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "About MacIsland", action: #selector(showAbout), keyEquivalent: "")
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit MacIsland", action: #selector(quitApp), keyEquivalent: "q")
        )
        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MacIsland"
        alert.informativeText = "Dynamic Island for macOS.\n\nOption+Space: Play/Pause\nOption+Arrows: Skip/Volume\nOption+T: Timer\nOption+P: Pomodoro\n\nmacOS Sonoma 14.0+"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
