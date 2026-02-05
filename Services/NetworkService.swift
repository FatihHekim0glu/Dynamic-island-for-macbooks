// NetworkService.swift
// MacIsland
//
// Monitors Wi-Fi connection status, SSID, and signal strength.
// Uses NWPathMonitor for connectivity and CoreWLAN for Wi-Fi details.
// Provides disconnect alerts for the notification system.

import Foundation
import Network
import CoreWLAN
import Combine

// MARK: - Signal Quality

enum SignalQuality: String {
    case excellent
    case good
    case fair
    case poor
    case disconnected

    var icon: String {
        switch self {
        case .excellent, .good: return "wifi"
        case .fair:             return "wifi"
        case .poor:             return "wifi.exclamationmark"
        case .disconnected:     return "wifi.slash"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good:      return "white"
        case .fair:      return "yellow"
        case .poor:      return "red"
        case .disconnected: return "gray"
        }
    }
}

// MARK: - NetworkService

@MainActor
final class NetworkService: ObservableObject {

    @Published var isConnected: Bool = true
    @Published var isWifi: Bool = false
    @Published var ssid: String? = nil
    @Published var signalQuality: SignalQuality = .good
    @Published var rssi: Int = 0
    @Published var didJustDisconnect: Bool = false

    private var pathMonitor: NWPathMonitor?
    private nonisolated(unsafe) var pollTimer: Timer?
    private var previouslyConnected: Bool = true

    init() {
        startPathMonitor()
        readWifiDetails()
        startPolling()
    }

    deinit {
        pathMonitor?.cancel()
        pollTimer?.invalidate()
    }

    // MARK: - NWPathMonitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let connected = path.status == .satisfied
                let wifi = path.usesInterfaceType(.wifi)

                if self.isConnected && !connected {
                    self.didJustDisconnect = true
                    // Auto-clear disconnect flag after 5s
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        self.didJustDisconnect = false
                    }
                }

                self.isConnected = connected
                self.isWifi = wifi

                if connected && wifi {
                    self.readWifiDetails()
                } else if !connected {
                    self.ssid = nil
                    self.signalQuality = .disconnected
                    self.rssi = 0
                }

                self.previouslyConnected = connected
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    // MARK: - CoreWLAN

    func readWifiDetails() {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else {
            ssid = nil
            signalQuality = .disconnected
            return
        }

        ssid = interface.ssid()
        rssi = interface.rssiValue()

        // Signal quality based on RSSI
        let signalStrength = rssi
        if signalStrength >= -50 {
            signalQuality = .excellent
        } else if signalStrength >= -60 {
            signalQuality = .good
        } else if signalStrength >= -70 {
            signalQuality = .fair
        } else {
            signalQuality = .poor
        }
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readWifiDetails()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
