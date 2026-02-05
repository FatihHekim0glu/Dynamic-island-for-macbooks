// BrightnessService.swift
// MacIsland
//
// Manages built-in display brightness via CoreDisplay private API.
// Reads the current brightness, sets it, and polls for external changes
// (F1/F2 keys) since there is no notification API for brightness.
//
// WHY CoreDisplay instead of AppleScript + external CLI?
// - The `brightness` CLI tool is not installed by default on macOS.
// - AppleScript requires permissions and is slow.
// - CoreDisplay is the same private API that System Settings and the
//   brightness keys use internally. It's been stable since macOS 10.12.
//
// NOTE: This only works on built-in displays (MacBook screen).
// External monitors use DDC/CI which requires a completely different approach.

import Foundation
import CoreGraphics
import Combine

// MARK: - CoreDisplay Dynamic Bindings

/// Private CoreDisplay function: sets the user brightness (0.0–1.0) on a display.
private typealias CoreDisplay_Display_SetUserBrightnessFunction =
    @convention(c) (CGDirectDisplayID, Double) -> Void

/// Private CoreDisplay function: reads the current user brightness (0.0–1.0).
private typealias CoreDisplay_Display_GetUserBrightnessFunction =
    @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Void

// MARK: - BrightnessService

@MainActor
final class BrightnessService: ObservableObject {

    @Published var brightness: Float = 0.5

    private var setUserBrightness: CoreDisplay_Display_SetUserBrightnessFunction?
    private var getUserBrightness: CoreDisplay_Display_GetUserBrightnessFunction?
    private var pollTimer: Timer?

    /// Whether the CoreDisplay functions were resolved successfully.
    var isAvailable: Bool { getUserBrightness != nil && setUserBrightness != nil }

    init() {
        loadCoreBrightness()
        readCurrentBrightness()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Dynamic Loading

    /// Load CoreDisplay.framework and resolve the brightness functions.
    private func loadCoreBrightness() {
        let path = "/System/Library/Frameworks/CoreDisplay.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL) else {
            print("[MacIsland] Failed to load CoreDisplay.framework")
            return
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "CoreDisplay_Display_SetUserBrightness" as CFString) {
            setUserBrightness = unsafeBitCast(ptr, to: CoreDisplay_Display_SetUserBrightnessFunction.self)
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "CoreDisplay_Display_GetUserBrightness" as CFString) {
            getUserBrightness = unsafeBitCast(ptr, to: CoreDisplay_Display_GetUserBrightnessFunction.self)
        }

        if !isAvailable {
            print("[MacIsland] CoreDisplay brightness functions not available — brightness control disabled")
        }
    }

    // MARK: - Read Brightness

    /// Read the current display brightness (0.0–1.0).
    func readCurrentBrightness() {
        guard let getter = getUserBrightness else { return }
        var value: Double = 0
        getter(CGMainDisplayID(), &value)
        brightness = Float(value)
    }

    // MARK: - Set Brightness

    /// Set the display brightness (0.0–1.0).
    func setBrightness(_ value: Float) {
        guard let setter = setUserBrightness else { return }
        let clamped = Double(min(max(value, 0), 1))
        setter(CGMainDisplayID(), clamped)
        brightness = Float(clamped)
    }

    // MARK: - Polling

    /// Poll every 2 seconds to stay synced with F1/F2 brightness keys.
    /// Unlike volume (which has a CoreAudio listener), brightness has no
    /// notification API, so polling is the only reliable approach.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentBrightness()
            }
        }
    }
}
