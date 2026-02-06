// VolumeService.swift
// MacIsland
//
// Manages system volume via CoreAudio APIs.
// Reads the current output volume, sets it, and stays synced with external changes.
//
// Key robustness features:
// - Listens for default output device changes (e.g., switching to AirPods)
//   and automatically re-resolves the device + reinstalls the volume listener.
// - Polls every 0.5s as a safety net in case the listener block doesn't fire.
// - Logs all failures for debugging.

import CoreAudio
import AudioToolbox
import Combine
import AppKit

@MainActor
final class VolumeService: ObservableObject {

    @Published var volume: Float = 0.0

    private nonisolated(unsafe) var defaultOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private nonisolated(unsafe) var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var pollTimer: Timer?

    init() {
        resolveDefaultOutputDevice()
        readCurrentVolume()
        installVolumeChangeListener()
        installDeviceChangeListener()
        startPolling()
        print("[MacIsland] VolumeService init: device=\(defaultOutputDeviceID), volume=\(volume)")
    }

    deinit {
        pollTimer?.invalidate()
        cleanupListeners()
    }

    // MARK: - Device Resolution

    private func resolveDefaultOutputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        if status == noErr && deviceID != kAudioObjectUnknown {
            defaultOutputDeviceID = deviceID
        } else {
            print("[MacIsland] Volume: Failed to resolve default output device (status=\(status))")
        }
    }

    // MARK: - Read

    func readCurrentVolume() {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }

        // Try VirtualMainVolume first (works on most devices)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        var status = AudioObjectGetPropertyData(
            defaultOutputDeviceID, &address, 0, nil, &size, &vol
        )

        if status == noErr {
            if volume != vol {
                volume = vol
            }
            return
        }

        // Fallback: try kAudioDevicePropertyVolumeScalar on channel 1
        address.mSelector = kAudioDevicePropertyVolumeScalar
        address.mElement = 1  // channel 1 (left)
        status = AudioObjectGetPropertyData(
            defaultOutputDeviceID, &address, 0, nil, &size, &vol
        )

        if status == noErr {
            if volume != vol {
                volume = vol
            }
        }
    }

    // MARK: - Set

    func setVolume(_ value: Float) {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }

        let clamped = Float32(min(max(value, 0), 1))

        // Try VirtualMainVolume first
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = clamped
        let size = UInt32(MemoryLayout<Float32>.size)

        var status = AudioObjectSetPropertyData(
            defaultOutputDeviceID, &address, 0, nil, size, &vol
        )

        if status == noErr {
            volume = clamped
            return
        }

        // Fallback: set per-channel volume
        address.mSelector = kAudioDevicePropertyVolumeScalar
        for channel: UInt32 in [1, 2] {  // Left + Right
            address.mElement = channel
            vol = clamped
            status = AudioObjectSetPropertyData(
                defaultOutputDeviceID, &address, 0, nil, size, &vol
            )
        }
        if status == noErr {
            volume = clamped
        }
    }

    // MARK: - Volume Change Listener

    private func installVolumeChangeListener() {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }

        // Remove old listener if exists
        removeVolumeListener()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.readCurrentVolume()
            }
        }
        volumeListenerBlock = block

        let status = AudioObjectAddPropertyListenerBlock(
            defaultOutputDeviceID, &address, DispatchQueue.main, block
        )

        if status != noErr {
            print("[MacIsland] Volume: Failed to install volume listener (status=\(status))")
        }
    }

    private func removeVolumeListener() {
        guard let block = volumeListenerBlock,
              defaultOutputDeviceID != kAudioObjectUnknown else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            defaultOutputDeviceID, &address, DispatchQueue.main, block
        )
        volumeListenerBlock = nil
    }

    // MARK: - Device Change Listener

    /// Listen for when the user switches audio output devices (e.g., speakers → AirPods).
    /// When this fires, re-resolve the device and reinstall the volume listener.
    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                print("[MacIsland] Volume: Default output device changed, re-resolving...")
                self.removeVolumeListener()
                self.resolveDefaultOutputDevice()
                self.readCurrentVolume()
                self.installVolumeChangeListener()
            }
        }
        deviceChangeListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address, DispatchQueue.main, block
        )
    }

    // MARK: - Polling Fallback

    /// Poll every 0.5s as a safety net. The listener should handle most changes,
    /// but polling catches edge cases where the listener silently stops.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentVolume()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    // MARK: - Cleanup

    private nonisolated func cleanupListeners() {
        // Called from deinit (nonisolated context)
        pollTimer?.invalidate()

        if let block = volumeListenerBlock, defaultOutputDeviceID != kAudioObjectUnknown {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                defaultOutputDeviceID, &address, DispatchQueue.main, block
            )
        }

        if let block = deviceChangeListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
            )
        }
    }
}
