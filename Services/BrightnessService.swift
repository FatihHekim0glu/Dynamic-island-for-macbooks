// BrightnessService.swift
// MacIsland
//
// Manages built-in display brightness via IOKit (primary) with CoreDisplay fallback.
// Uses IODisplayGetFloatParameter / IODisplaySetFloatParameter with
// kIODisplayBrightnessKey — the stable IOKit approach.
// Polls every 1s to sync with F1/F2 keys (no brightness notification API exists).

import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics
import Combine

// MARK: - CoreDisplay Fallback Typedefs

private typealias CoreDisplay_Display_SetBrightnessFunc =
    @convention(c) (CGDirectDisplayID, Double) -> Void

private typealias CoreDisplay_Display_GetBrightnessFunc =
    @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Void

// MARK: - BrightnessService

@MainActor
final class BrightnessService: ObservableObject {

    @Published var brightness: Float = 0.5

    private var pollTimer: Timer?

    // IOKit service port for the built-in display
    private var displayService: io_service_t = 0
    private var useIOKit: Bool = false

    // CoreDisplay fallback
    private var cdSetBrightness: CoreDisplay_Display_SetBrightnessFunc?
    private var cdGetBrightness: CoreDisplay_Display_GetBrightnessFunc?
    private var useCoreDisplay: Bool = false

    init() {
        resolveDisplayService()
        loadCoreDisplayFallback()
        readCurrentBrightness()
        startPolling()
        print("[MacIsland] Brightness: IOKit=\(useIOKit), CoreDisplay=\(useCoreDisplay), initial=\(brightness)")
    }

    deinit {
        pollTimer?.invalidate()
        if displayService != 0 {
            IOObjectRelease(displayService)
        }
    }

    // MARK: - IOKit Display Service

    private func resolveDisplayService() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else {
            print("[MacIsland] IOKit: Failed to enumerate display services")
            return
        }
        defer { IOObjectRelease(iterator) }

        // Get the first display (built-in on MacBooks)
        let service = IOIteratorNext(iterator)
        if service != 0 {
            // Verify we can actually read brightness from this service
            var testValue: Float = 0
            let testResult = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &testValue)
            if testResult == kIOReturnSuccess {
                displayService = service
                useIOKit = true
                print("[MacIsland] IOKit: Display service found, brightness = \(testValue)")
            } else {
                // Try more services
                IOObjectRelease(service)
                var nextService = IOIteratorNext(iterator)
                while nextService != 0 {
                    let r = IODisplayGetFloatParameter(nextService, 0, kIODisplayBrightnessKey as CFString, &testValue)
                    if r == kIOReturnSuccess {
                        displayService = nextService
                        useIOKit = true
                        print("[MacIsland] IOKit: Display service found (secondary), brightness = \(testValue)")
                        break
                    }
                    IOObjectRelease(nextService)
                    nextService = IOIteratorNext(iterator)
                }
            }
        }
    }

    // MARK: - CoreDisplay Fallback

    private func loadCoreDisplayFallback() {
        let paths = [
            "/System/Library/Frameworks/CoreDisplay.framework",
            "/System/Library/PrivateFrameworks/CoreDisplay.framework"
        ]

        for path in paths {
            guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL) else {
                continue
            }

            if let ptr = CFBundleGetFunctionPointerForName(bundle, "CoreDisplay_Display_SetUserBrightness" as CFString) {
                cdSetBrightness = unsafeBitCast(ptr, to: CoreDisplay_Display_SetBrightnessFunc.self)
            }
            if let ptr = CFBundleGetFunctionPointerForName(bundle, "CoreDisplay_Display_GetUserBrightness" as CFString) {
                cdGetBrightness = unsafeBitCast(ptr, to: CoreDisplay_Display_GetBrightnessFunc.self)
            }

            if cdSetBrightness != nil && cdGetBrightness != nil {
                useCoreDisplay = true
                print("[MacIsland] CoreDisplay: Loaded brightness fallback from \(path)")
                break
            }
        }
    }

    // MARK: - Read

    func readCurrentBrightness() {
        // Try IOKit first
        if useIOKit {
            var value: Float = 0
            let result = IODisplayGetFloatParameter(displayService, 0, kIODisplayBrightnessKey as CFString, &value)
            if result == kIOReturnSuccess {
                brightness = value
                return
            }
        }

        // CoreDisplay fallback
        if useCoreDisplay, let getter = cdGetBrightness {
            var value: Double = 0
            getter(CGMainDisplayID(), &value)
            brightness = Float(value)
        }
    }

    // MARK: - Set

    func setBrightness(_ value: Float) {
        let clamped = min(max(value, 0), 1)

        // Try IOKit first
        if useIOKit {
            let result = IODisplaySetFloatParameter(displayService, 0, kIODisplayBrightnessKey as CFString, clamped)
            if result == kIOReturnSuccess {
                brightness = clamped
                return
            }
        }

        // CoreDisplay fallback
        if useCoreDisplay, let setter = cdSetBrightness {
            setter(CGMainDisplayID(), Double(clamped))
            brightness = clamped
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentBrightness()
            }
        }
    }
}
