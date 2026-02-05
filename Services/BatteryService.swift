// BatteryService.swift
// MacIsland
//
// Monitors laptop battery state using IOPowerSources.
// Publishes percentage, charging status, and time remaining.
// Polls every 30s (battery changes slowly).

import Foundation
import IOKit.ps
import Combine

@MainActor
final class BatteryService: ObservableObject {

    @Published var percentage: Int = 100
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var minutesRemaining: Int? = nil
    @Published var isFullyCharged: Bool = false

    private nonisolated(unsafe) var pollTimer: Timer?

    init() {
        readBattery()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Read

    func readBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Only process internal battery
            guard let type = info[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType as String else {
                continue
            }

            let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = maxCapacity > 0 ? Int((Double(capacity) / Double(maxCapacity)) * 100) : 0

            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let powerSource = info[kIOPSPowerSourceStateKey] as? String ?? ""
            let pluggedIn = powerSource == (kIOPSACPowerValue as String)

            var timeRemaining: Int? = nil
            if charging {
                let ttf = info[kIOPSTimeToFullChargeKey] as? Int ?? -1
                if ttf > 0 { timeRemaining = ttf }
            } else {
                let tte = info[kIOPSTimeToEmptyKey] as? Int ?? -1
                if tte > 0 { timeRemaining = tte }
            }

            let fullyCharged = info[kIOPSIsChargedKey] as? Bool ?? (pct >= 100 && pluggedIn)

            if self.percentage != pct { self.percentage = pct }
            if self.isCharging != charging { self.isCharging = charging }
            if self.isPluggedIn != pluggedIn { self.isPluggedIn = pluggedIn }
            if self.minutesRemaining != timeRemaining { self.minutesRemaining = timeRemaining }
            if self.isFullyCharged != fullyCharged { self.isFullyCharged = fullyCharged }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readBattery()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Helpers

    var timeRemainingFormatted: String {
        guard let minutes = minutesRemaining, minutes > 0 else { return "" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    var batteryIcon: String {
        if isCharging { return "battery.100.bolt" }
        if percentage > 75 { return "battery.100" }
        if percentage > 50 { return "battery.75" }
        if percentage > 25 { return "battery.50" }
        if percentage > 10 { return "battery.25" }
        return "battery.0"
    }

    var batteryColor: Color {
        if isCharging { return .green }
        if percentage > 20 { return .white }
        if percentage > 10 { return .yellow }
        return .red
    }
}

// Need to import SwiftUI for Color
import SwiftUI
