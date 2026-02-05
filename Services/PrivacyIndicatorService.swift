// PrivacyIndicatorService.swift
// MacIsland
//
// Detects when any app is using the microphone or camera.
// Mic: CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere on default input device.
// Camera: IORegistry check for active camera clients.
// Polls every 1s.

import Foundation
import CoreAudio
import AudioToolbox
import IOKit
import Combine
import AppKit

@MainActor
final class PrivacyIndicatorService: ObservableObject {

    @Published var isMicActive: Bool = false
    @Published var isCameraActive: Bool = false
    @Published var micAppName: String = ""
    @Published var cameraAppName: String = ""

    private nonisolated(unsafe) var pollTimer: Timer?

    init() {
        checkMicStatus()
        checkCameraStatus()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Microphone Detection

    func checkMicStatus() {
        // Get default input device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            if isMicActive { isMicActive = false }
            return
        }

        // Check if device is running somewhere
        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let runStatus = AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &runningSize, &isRunning
        )

        let active = (runStatus == noErr && isRunning != 0)
        if isMicActive != active {
            isMicActive = active
            if active {
                micAppName = guessActiveApp()
            } else {
                micAppName = ""
            }
        }
    }

    // MARK: - Camera Detection

    func checkCameraStatus() {
        var cameraActive = false

        // Try multiple IORegistry classes that represent camera devices
        let cameraClasses = [
            "AppleH13CamIn",
            "AppleCamIn",
            "IOUSBHostDevice",
            "AppleH10CamIn"
        ]

        for className in cameraClasses {
            if checkIORegistryCamera(className: className) {
                cameraActive = true
                break
            }
        }

        // Fallback: check via IORegistry for any device with "Camera" in name
        if !cameraActive {
            cameraActive = checkGenericCameraRegistry()
        }

        if isCameraActive != cameraActive {
            isCameraActive = cameraActive
            cameraAppName = cameraActive ? guessActiveApp() : ""
        }
    }

    private func checkIORegistryCamera(className: String) -> Bool {
        guard let matching = IOServiceMatching(className) else { return false }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
            guard result == kIOReturnSuccess, let props = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Check various indicators of camera activity
            if let state = props["IOServiceBusyState"] as? Int, state > 0 {
                return true
            }
            if let clientCount = props["IOServiceBusyTime"] as? Int, clientCount > 0 {
                return true
            }
        }

        return false
    }

    private func checkGenericCameraRegistry() -> Bool {
        // Check via IOServiceGetMatchingService for VDCAssistant (camera daemon)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceNameMatching("AppleCameraAssistant")
        )
        if service != 0 {
            IOObjectRelease(service)
            return true
        }
        return false
    }

    // MARK: - App Guessing

    private func guessActiveApp() -> String {
        let workspace = NSWorkspace.shared

        let mediaApps: Set<String> = [
            "com.apple.FaceTime",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.apple.Safari",
            "com.tinyspeck.slackmacgap",
            "com.cisco.webex.meetings",
            "com.skype.skype",
            "com.apple.PhotoBooth",
            "com.obsproject.obs-studio",
            "com.discord.Discord"
        ]

        // Check running apps that are known media apps
        for app in workspace.runningApplications {
            if let bundleID = app.bundleIdentifier, mediaApps.contains(bundleID) {
                return app.localizedName ?? bundleID
            }
        }

        // Return frontmost app as fallback
        if let frontmost = workspace.frontmostApplication {
            return frontmost.localizedName ?? "Unknown"
        }
        return "Unknown"
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMicStatus()
                self?.checkCameraStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
