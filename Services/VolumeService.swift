// VolumeService.swift
// MacIsland
//
// Manages system volume via CoreAudio APIs.
// Reads the current output volume, sets it, and listens for external changes
// (e.g., volume keys on the keyboard) to keep the UI slider in sync.
//
// WHY CoreAudio instead of AppleScript?
// - AppleScript requires NSAppleEventsUsageDescription and shows a permission prompt.
// - AppleScript is slow (~50ms per execution) and can silently fail.
// - CoreAudio is the native, zero-overhead API that the system volume keys use internally.

import CoreAudio
import AudioToolbox
import Combine

@MainActor
final class VolumeService: ObservableObject {

    @Published var volume: Float = 0.0

    private var defaultOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        resolveDefaultOutputDevice()
        readCurrentVolume()
        installVolumeChangeListener()
    }

    deinit {
        // deinit is nonisolated, so we inline the cleanup directly
        // rather than calling the MainActor-isolated method.
        guard let block = listenerBlock,
              defaultOutputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            defaultOutputDeviceID,
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Device Resolution

    /// Find the system's default audio output device (speakers, headphones, etc.).
    private func resolveDefaultOutputDevice() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &size, &deviceID
        )

        if status == noErr {
            defaultOutputDeviceID = deviceID
        } else {
            print("[MacIsland] Failed to resolve default audio output device: \(status)")
        }
    }

    // MARK: - Read Volume

    /// Read the current system volume (0.0–1.0) from CoreAudio.
    func readCurrentVolume() {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0, nil,
            &size, &vol
        )

        if status == noErr {
            volume = vol
        }
    }

    // MARK: - Set Volume

    /// Set the system volume (0.0–1.0) via CoreAudio.
    func setVolume(_ value: Float) {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = Float32(min(max(value, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectSetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0, nil,
            size, &vol
        )

        if status == noErr {
            volume = vol
        }
    }

    // MARK: - External Change Listener

    /// Listen for volume changes made externally (keyboard volume keys, System Settings, other apps)
    /// so our slider stays perfectly synced without polling.
    private func installVolumeChangeListener() {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        listenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.readCurrentVolume()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            defaultOutputDeviceID,
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )
    }

    private func removeVolumeChangeListener() {
        guard let block = listenerBlock,
              defaultOutputDeviceID != kAudioObjectUnknown else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            defaultOutputDeviceID,
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
}
