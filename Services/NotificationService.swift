// NotificationService.swift
// MacIsland
//
// Observes system notifications via DistributedNotificationCenter and
// surfaces them as animated pill expansions that auto-dismiss.
// Also accepts internal notifications from other services (timer complete, etc.).

import Foundation
import Combine
import AppKit

// MARK: - Notification Payload

struct IslandNotification: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let icon: String          // SF Symbol name
    let iconColor: Color
    let timestamp: Date
    let autoDismissSeconds: TimeInterval

    static func == (lhs: IslandNotification, rhs: IslandNotification) -> Bool {
        lhs.id == rhs.id
    }
}

import SwiftUI

// MARK: - NotificationService

@MainActor
final class NotificationService: ObservableObject {

    @Published var currentNotification: IslandNotification? = nil
    @Published var hasActiveNotification: Bool = false

    private var dismissTask: Task<Void, Never>?
    private var queue: [IslandNotification] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init() {
        setupDistributedObservers()
    }

    deinit {
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Distributed Notification Observers

    private func setupDistributedObservers() {
        // Observe various system notifications
        let center = DistributedNotificationCenter.default()

        // Bluetooth connection changes
        let btObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.bluetooth.state"),
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.post(IslandNotification(
                    id: UUID(),
                    title: "Bluetooth",
                    subtitle: "Connection changed",
                    icon: "bluetooth",
                    iconColor: .blue,
                    timestamp: Date(),
                    autoDismissSeconds: 3
                ))
            }
        }
        distributedObservers.append(btObserver)

        // Screen lock/unlock
        let lockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.post(IslandNotification(
                    id: UUID(),
                    title: "Screen Locked",
                    subtitle: "",
                    icon: "lock.fill",
                    iconColor: .yellow,
                    timestamp: Date(),
                    autoDismissSeconds: 2
                ))
            }
        }
        distributedObservers.append(lockObserver)

        // Power source changes (plugged in / unplugged)
        let powerObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.system.powersources.timeremaining"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.post(IslandNotification(
                    id: UUID(),
                    title: "Power",
                    subtitle: "Power source changed",
                    icon: "bolt.fill",
                    iconColor: .green,
                    timestamp: Date(),
                    autoDismissSeconds: 3
                ))
            }
        }
        distributedObservers.append(powerObserver)
    }

    // MARK: - Post Notification

    func post(_ notification: IslandNotification) {
        // If a notification is currently showing, queue it
        if hasActiveNotification {
            queue.append(notification)
            return
        }

        showNotification(notification)
    }

    private func showNotification(_ notification: IslandNotification) {
        withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
            currentNotification = notification
            hasActiveNotification = true
        }

        // Auto-dismiss
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(notification.autoDismissSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
            currentNotification = nil
            hasActiveNotification = false
        }

        // Show next queued notification after a brief pause
        if !queue.isEmpty {
            let next = queue.removeFirst()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                showNotification(next)
            }
        }
    }
}
