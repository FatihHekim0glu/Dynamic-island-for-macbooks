// BluetoothBatteryService.swift
// MacIsland
//
// Monitors AirPods and Bluetooth headphone battery levels.
// Uses IORegistry to read BatteryPercent, BatteryPercentLeft/Right/Case.
// Falls back to IOPowerSources for generic Bluetooth devices.
// Polls every 10s.

import Foundation
import IOKit
import Combine
import AppKit

// MARK: - Bluetooth Device Model

struct BluetoothDeviceInfo: Equatable {
    let name: String
    let batteryLevel: Int?       // Overall battery (0-100)
    let leftBattery: Int?        // AirPods left ear
    let rightBattery: Int?       // AirPods right ear
    let caseBattery: Int?        // AirPods case
    let isConnected: Bool
    let isAirPods: Bool

    var displayBattery: Int {
        batteryLevel ?? ((leftBattery ?? 0) + (rightBattery ?? 0)) / 2
    }

    var batteryIcon: String {
        let level = displayBattery
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        if level > 10 { return "battery.25" }
        return "battery.0"
    }
}

// MARK: - BluetoothBatteryService

@MainActor
final class BluetoothBatteryService: ObservableObject {

    @Published var connectedDevice: BluetoothDeviceInfo?
    @Published var hasConnectedDevice: Bool = false

    private nonisolated(unsafe) var pollTimer: Timer?

    init() {
        scanDevices()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Scan

    func scanDevices() {
        // Try IORegistry approach first (works for AirPods)
        if let device = scanIORegistry() {
            connectedDevice = device
            hasConnectedDevice = true
            return
        }

        // Fallback: IOPowerSources for generic Bluetooth batteries
        if let device = scanPowerSources() {
            connectedDevice = device
            hasConnectedDevice = true
            return
        }

        // Try IOBluetooth via AppleScript
        if let device = scanViaAppleScript() {
            connectedDevice = device
            hasConnectedDevice = true
            return
        }

        connectedDevice = nil
        hasConnectedDevice = false
    }

    // MARK: - IORegistry Scan

    private func scanIORegistry() -> BluetoothDeviceInfo? {
        // Search for Bluetooth devices with battery information
        let matchingClasses = [
            "AppleHSBluetoothDevice",
            "IOBluetoothDevice",
            "BNBMouseDevice",
            "AppleBCMBluetoothHostController"
        ]

        for className in matchingClasses {
            if let device = searchIORegistry(className: className) {
                return device
            }
        }

        // Generic search for any IORegistry entry with BatteryPercent
        return searchIORegistryGeneric()
    }

    private func searchIORegistry(className: String) -> BluetoothDeviceInfo? {
        guard let matching = IOServiceMatching(className) else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let props = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Look for battery information
            let batteryLevel = props["BatteryPercent"] as? Int
            let leftBattery = props["BatteryPercentLeft"] as? Int ??
                              props["LeftBatteryPercent"] as? Int
            let rightBattery = props["BatteryPercentRight"] as? Int ??
                               props["RightBatteryPercent"] as? Int
            let caseBattery = props["BatteryPercentCase"] as? Int ??
                              props["CaseBatteryPercent"] as? Int

            let hasBattery = batteryLevel != nil || leftBattery != nil ||
                            rightBattery != nil || caseBattery != nil

            if hasBattery {
                let name = props["Product"] as? String ??
                          props["DeviceName"] as? String ??
                          props["Name"] as? String ?? "Bluetooth Device"

                let isAirPods = name.lowercased().contains("airpod") ||
                               (leftBattery != nil && rightBattery != nil)

                return BluetoothDeviceInfo(
                    name: name,
                    batteryLevel: batteryLevel,
                    leftBattery: leftBattery,
                    rightBattery: rightBattery,
                    caseBattery: caseBattery,
                    isConnected: true,
                    isAirPods: isAirPods
                )
            }
        }

        return nil
    }

    private func searchIORegistryGeneric() -> BluetoothDeviceInfo? {
        // Walk the IORegistry looking for any Bluetooth device with battery
        let matching = IOServiceMatching("IOService") as NSMutableDictionary
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        // Limit iterations to avoid performance issues
        var count = 0
        var service = IOIteratorNext(iterator)
        while service != 0 && count < 500 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
                count += 1
            }

            // Check for BatteryPercent property directly
            if let batteryRef = IORegistryEntryCreateCFProperty(
                service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0
            ) {
                let battery = batteryRef.takeRetainedValue() as? Int

                // Get device name
                let nameRef = IORegistryEntryCreateCFProperty(
                    service, "Product" as CFString, kCFAllocatorDefault, 0
                )
                let name = nameRef?.takeRetainedValue() as? String ?? "Bluetooth Device"

                if let battery = battery, battery > 0 && battery <= 100 {
                    return BluetoothDeviceInfo(
                        name: name,
                        batteryLevel: battery,
                        leftBattery: nil,
                        rightBattery: nil,
                        caseBattery: nil,
                        isConnected: true,
                        isAirPods: name.lowercased().contains("airpod")
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Power Sources

    private func scanPowerSources() -> BluetoothDeviceInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Skip internal battery
            let type = info[kIOPSTypeKey] as? String ?? ""
            if type == kIOPSInternalBatteryType as String { continue }

            let transportType = info[kIOPSTransportTypeKey] as? String ?? ""
            guard transportType.lowercased().contains("bluetooth") ||
                  transportType.lowercased().contains("wireless") else { continue }

            let name = info[kIOPSNameKey] as? String ?? "Bluetooth Device"
            let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let battery = maxCapacity > 0 ? Int((Double(capacity) / Double(maxCapacity)) * 100) : 0

            return BluetoothDeviceInfo(
                name: name,
                batteryLevel: battery,
                leftBattery: nil,
                rightBattery: nil,
                caseBattery: nil,
                isConnected: true,
                isAirPods: name.lowercased().contains("airpod")
            )
        }

        return nil
    }

    // MARK: - AppleScript Fallback

    private func scanViaAppleScript() -> BluetoothDeviceInfo? {
        let script = NSAppleScript(source: """
            try
                set btInfo to do shell script "system_profiler SPBluetoothDataType 2>/dev/null | grep -A5 'Connected: Yes' | head -10"
                return btInfo
            on error
                return ""
            end try
        """)

        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        let output = result?.stringValue ?? ""

        guard !output.isEmpty else { return nil }

        // Parse basic info from system_profiler output
        let lines = output.components(separatedBy: "\n")
        var name = "Bluetooth Device"
        var battery: Int?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(":") && !trimmed.hasPrefix("Connected") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)

                    if key == "Battery Level" || key.contains("Battery") {
                        battery = Int(value.replacingOccurrences(of: "%", with: ""))
                    }
                    if !key.contains("Battery") && !key.contains("Connected") &&
                       !key.contains("Address") && !key.isEmpty && name == "Bluetooth Device" {
                        name = key
                    }
                }
            }
        }

        guard battery != nil else { return nil }

        return BluetoothDeviceInfo(
            name: name,
            batteryLevel: battery,
            leftBattery: nil,
            rightBattery: nil,
            caseBattery: nil,
            isConnected: true,
            isAirPods: name.lowercased().contains("airpod")
        )
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanDevices()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}

import IOKit.ps
