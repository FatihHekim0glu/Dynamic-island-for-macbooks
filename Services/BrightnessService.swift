// BrightnessService.swift
// MacIsland
//
// Manages built-in display brightness using a three-layer approach:
//   1. DisplayServices.framework (private, most reliable on macOS 14+)
//   2. IOKit IODisplaySetFloatParameter (legacy, works on some configs)
//   3. CoreDisplay (private, older fallback)
// Polls every 0.5s to sync with F1/F2 key changes (no notification API exists).

import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics
import Combine

// MARK: - DisplayServices Typedefs (Primary)

private typealias DisplayServicesGetBrightnessFunc =
    @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

private typealias DisplayServicesSetBrightnessFunc =
    @convention(c) (CGDirectDisplayID, Float) -> Int32

private typealias DisplayServicesCanChangeBrightnessFunc =
    @convention(c) (CGDirectDisplayID) -> Bool

// MARK: - CoreDisplay Fallback Typedefs

private typealias CoreDisplay_Display_SetBrightnessFunc =
    @convention(c) (CGDirectDisplayID, Double) -> Void

private typealias CoreDisplay_Display_GetBrightnessFunc =
    @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Void

// MARK: - BrightnessService

@MainActor
final class BrightnessService: ObservableObject {

    @Published var brightness: Float = 0.5

    private nonisolated(unsafe) var pollTimer: Timer?

    // DisplayServices (primary)
    private var dsGetBrightness: DisplayServicesGetBrightnessFunc?
    private var dsSetBrightness: DisplayServicesSetBrightnessFunc?
    private var dsCanChangeBrightness: DisplayServicesCanChangeBrightnessFunc?
    private var useDisplayServices: Bool = false

    // IOKit (first fallback)
    private nonisolated(unsafe) var displayService: io_service_t = 0
    private var useIOKit: Bool = false

    // CoreDisplay (second fallback)
    private var cdSetBrightness: CoreDisplay_Display_SetBrightnessFunc?
    private var cdGetBrightness: CoreDisplay_Display_GetBrightnessFunc?
    private var useCoreDisplay: Bool = false

    init() {
        loadDisplayServices()
        if !useDisplayServices {
            resolveIOKitDisplayService()
        }
        if !useDisplayServices && !useIOKit {
            loadCoreDisplayFallback()
        }
        readCurrentBrightness()
        startPolling()
        print("[MacIsland] Brightness: DisplayServices=\(useDisplayServices), IOKit=\(useIOKit), CoreDisplay=\(useCoreDisplay), initial=\(brightness)")
    }

    deinit {
        pollTimer?.invalidate()
        if displayService != 0 {
            IOObjectRelease(displayService)
        }
    }

    // MARK: - DisplayServices (Primary — macOS 14+)

    private func loadDisplayServices() {
        let paths = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework",
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        ]

        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }

            if let getPtr = dlsym(handle, "DisplayServicesGetBrightness"),
               let setPtr = dlsym(handle, "DisplayServicesSetBrightness") {

                dsGetBrightness = unsafeBitCast(getPtr, to: DisplayServicesGetBrightnessFunc.self)
                dsSetBrightness = unsafeBitCast(setPtr, to: DisplayServicesSetBrightnessFunc.self)

                // Optional — not all versions have this
                if let canPtr = dlsym(handle, "DisplayServicesCanChangeBrightness") {
                    dsCanChangeBrightness = unsafeBitCast(canPtr, to: DisplayServicesCanChangeBrightnessFunc.self)
                }

                // Test that it actually works
                var testVal: Float = 0
                let result = dsGetBrightness!(CGMainDisplayID(), &testVal)
                if result == 0 {
                    useDisplayServices = true
                    print("[MacIsland] DisplayServices: loaded, current brightness = \(testVal)")
                    return
                } else {
                    print("[MacIsland] DisplayServices: loaded but GetBrightness returned \(result)")
                    dsGetBrightness = nil
                    dsSetBrightness = nil
                }
            }
        }
    }

    // MARK: - IOKit Display Service (Fallback 1)

    private func resolveIOKitDisplayService() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else {
            print("[MacIsland] IOKit: Failed to enumerate display services")
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var testValue: Float = 0
            let testResult = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &testValue)
            if testResult == kIOReturnSuccess {
                displayService = service
                useIOKit = true
                print("[MacIsland] IOKit: Display service found, brightness = \(testValue)")
                return
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        print("[MacIsland] IOKit: No display service supports brightness")
    }

    // MARK: - CoreDisplay Fallback (Fallback 2)

    private func loadCoreDisplayFallback() {
        let paths = [
            "/System/Library/Frameworks/CoreDisplay.framework",
            "/System/Library/PrivateFrameworks/CoreDisplay.framework"
        ]

        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }

            let setNames = [
                "CoreDisplay_Display_SetUserBrightness",
                "CoreDisplay_Display_SetBrightness"
            ]
            let getNames = [
                "CoreDisplay_Display_GetUserBrightness",
                "CoreDisplay_Display_GetBrightness"
            ]

            for setName in setNames {
                if let ptr = dlsym(handle, setName) {
                    cdSetBrightness = unsafeBitCast(ptr, to: CoreDisplay_Display_SetBrightnessFunc.self)
                    print("[MacIsland] CoreDisplay: found \(setName)")
                    break
                }
            }

            for getName in getNames {
                if let ptr = dlsym(handle, getName) {
                    cdGetBrightness = unsafeBitCast(ptr, to: CoreDisplay_Display_GetBrightnessFunc.self)
                    print("[MacIsland] CoreDisplay: found \(getName)")
                    break
                }
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
        // DisplayServices (primary)
        if useDisplayServices, let getter = dsGetBrightness {
            var value: Float = 0
            let result = getter(CGMainDisplayID(), &value)
            if result == 0 {
                if abs(brightness - value) > 0.001 {
                    brightness = value
                }
                return
            }
        }

        // IOKit fallback
        if useIOKit {
            var value: Float = 0
            let result = IODisplayGetFloatParameter(displayService, 0, kIODisplayBrightnessKey as CFString, &value)
            if result == kIOReturnSuccess {
                if abs(brightness - value) > 0.001 {
                    brightness = value
                }
                return
            }
        }

        // CoreDisplay fallback
        if useCoreDisplay, let getter = cdGetBrightness {
            var value: Double = 0
            getter(CGMainDisplayID(), &value)
            let fval = Float(value)
            if abs(brightness - fval) > 0.001 {
                brightness = fval
            }
        }
    }

    // MARK: - Set

    func setBrightness(_ value: Float) {
        let clamped = min(max(value, 0), 1)

        // DisplayServices (primary)
        if useDisplayServices, let setter = dsSetBrightness {
            let result = setter(CGMainDisplayID(), clamped)
            if result == 0 {
                brightness = clamped
                return
            }
            print("[MacIsland] DisplayServices: SetBrightness failed with \(result)")
        }

        // IOKit fallback
        if useIOKit {
            let result = IODisplaySetFloatParameter(displayService, 0, kIODisplayBrightnessKey as CFString, clamped)
            if result == kIOReturnSuccess {
                brightness = clamped
                return
            }
            print("[MacIsland] IOKit: SetBrightness failed with \(result)")
        }

        // CoreDisplay fallback
        if useCoreDisplay, let setter = cdSetBrightness {
            setter(CGMainDisplayID(), Double(clamped))
            brightness = clamped
            return
        }

        print("[MacIsland] Brightness: All methods failed to set brightness")
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentBrightness()
            }
        }
        // Add to .common mode so it fires even when tracking UI controls
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
