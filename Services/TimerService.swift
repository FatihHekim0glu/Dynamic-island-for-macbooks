// TimerService.swift
// MacIsland
//
// Countdown timer and stopwatch with live updates.
// Fires completion notification via UNUserNotificationCenter.
// Updates every 0.1s for smooth countdown display.

import Foundation
import Combine
import AppKit
import UserNotifications

// MARK: - Timer Mode

enum TimerMode: Equatable {
    case idle
    case countdown
    case stopwatch
}

// MARK: - TimerService

@MainActor
final class TimerService: ObservableObject {

    @Published var mode: TimerMode = .idle
    @Published var remainingSeconds: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var isRunning: Bool = false
    @Published var elapsedSeconds: TimeInterval = 0 // for stopwatch

    private nonisolated(unsafe) var timer: Timer?
    private var startDate: Date?
    private var pausedRemaining: TimeInterval = 0

    init() {
        requestNotificationPermission()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Countdown

    func startCountdown(seconds: TimeInterval) {
        stopTimer()
        mode = .countdown
        totalDuration = seconds
        remainingSeconds = seconds
        isRunning = true
        startDate = Date()
        startTicking()
    }

    func togglePause() {
        if isRunning {
            pause()
        } else if mode != .idle {
            resume()
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        if mode == .countdown {
            pausedRemaining = remainingSeconds
        }
    }

    func resume() {
        guard mode != .idle else { return }
        isRunning = true
        if mode == .countdown {
            startDate = Date()
            remainingSeconds = pausedRemaining
        } else {
            startDate = Date().addingTimeInterval(-elapsedSeconds)
        }
        startTicking()
    }

    func reset() {
        stopTimer()
        mode = .idle
        remainingSeconds = 0
        totalDuration = 0
        elapsedSeconds = 0
        isRunning = false
        pausedRemaining = 0
    }

    // MARK: - Stopwatch

    func startStopwatch() {
        stopTimer()
        mode = .stopwatch
        elapsedSeconds = 0
        isRunning = true
        startDate = Date()
        startTicking()
    }

    // MARK: - Timer Loop

    private func startTicking() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard isRunning, let start = startDate else { return }

        switch mode {
        case .countdown:
            let elapsed = Date().timeIntervalSince(start)
            let newRemaining = pausedRemaining > 0 ? pausedRemaining - elapsed : totalDuration - elapsed
            if newRemaining <= 0 {
                remainingSeconds = 0
                timerCompleted()
            } else {
                remainingSeconds = newRemaining
            }

        case .stopwatch:
            elapsedSeconds = Date().timeIntervalSince(start)

        case .idle:
            break
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        pausedRemaining = 0
    }

    // MARK: - Completion

    private func timerCompleted() {
        isRunning = false
        stopTimer()

        // Play sound
        NSSound(named: "Ping")?.play()

        // Send notification
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.body = "Your \(formatTime(totalDuration)) timer has finished."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macisland.timer.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Formatting

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (remainingSeconds / totalDuration)
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    var displayTime: String {
        switch mode {
        case .countdown:
            return formatTime(remainingSeconds)
        case .stopwatch:
            return formatTime(elapsedSeconds)
        case .idle:
            return "00:00"
        }
    }
}
