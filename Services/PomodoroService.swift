// PomodoroService.swift
// MacIsland
//
// Pomodoro timer state machine: 25min work / 5min break / 15min long break.
// Tracks completed sessions, sends notifications on phase transitions.
// Persists settings in UserDefaults.

import Foundation
import Combine
import AppKit
import UserNotifications

// MARK: - Pomodoro Phase

enum PomodoroPhase: Equatable {
    case idle
    case work
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .idle:       return "Ready"
        case .work:       return "WORK"
        case .shortBreak: return "BREAK"
        case .longBreak:  return "LONG BREAK"
        }
    }

    var color: String {
        switch self {
        case .idle:       return "gray"
        case .work:       return "red"
        case .shortBreak: return "green"
        case .longBreak:  return "blue"
        }
    }
}

// MARK: - PomodoroService

@MainActor
final class PomodoroService: ObservableObject {

    @Published var phase: PomodoroPhase = .idle
    @Published var remainingSeconds: TimeInterval = 0
    @Published var isRunning: Bool = false
    @Published var sessionsCompleted: Int = 0
    @Published var totalSessionsTarget: Int = 4

    // Settings (persisted)
    @Published var workDuration: TimeInterval {
        didSet { UserDefaults.standard.set(workDuration, forKey: "pomodoro.workDuration") }
    }
    @Published var shortBreakDuration: TimeInterval {
        didSet { UserDefaults.standard.set(shortBreakDuration, forKey: "pomodoro.shortBreakDuration") }
    }
    @Published var longBreakDuration: TimeInterval {
        didSet { UserDefaults.standard.set(longBreakDuration, forKey: "pomodoro.longBreakDuration") }
    }

    private nonisolated(unsafe) var timer: Timer?
    private var startDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private var currentPhaseDuration: TimeInterval = 0

    init() {
        let defaults = UserDefaults.standard
        workDuration = defaults.double(forKey: "pomodoro.workDuration").nonZero ?? 25 * 60
        shortBreakDuration = defaults.double(forKey: "pomodoro.shortBreakDuration").nonZero ?? 5 * 60
        longBreakDuration = defaults.double(forKey: "pomodoro.longBreakDuration").nonZero ?? 15 * 60
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Controls

    func start() {
        if phase == .idle {
            startPhase(.work)
        } else if !isRunning {
            resume()
        }
    }

    func pause() {
        isRunning = false
        pausedRemaining = remainingSeconds
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard phase != .idle else { return }
        isRunning = true
        startDate = Date()
        startTicking()
    }

    func skip() {
        advanceToNextPhase()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        remainingSeconds = 0
        isRunning = false
        sessionsCompleted = 0
        pausedRemaining = 0
        startDate = nil
    }

    func togglePause() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    // MARK: - Phase Management

    private func startPhase(_ newPhase: PomodoroPhase) {
        timer?.invalidate()

        phase = newPhase
        switch newPhase {
        case .idle:
            remainingSeconds = 0
            isRunning = false
            return
        case .work:
            currentPhaseDuration = workDuration
        case .shortBreak:
            currentPhaseDuration = shortBreakDuration
        case .longBreak:
            currentPhaseDuration = longBreakDuration
        }

        remainingSeconds = currentPhaseDuration
        pausedRemaining = currentPhaseDuration
        isRunning = true
        startDate = Date()
        startTicking()
    }

    private func advanceToNextPhase() {
        timer?.invalidate()
        timer = nil

        switch phase {
        case .work:
            sessionsCompleted += 1
            if sessionsCompleted >= totalSessionsTarget {
                sendNotification(title: "Long Break!", body: "You've completed \(totalSessionsTarget) sessions. Take a long break.")
                startPhase(.longBreak)
            } else {
                sendNotification(title: "Break Time!", body: "Session \(sessionsCompleted) complete. Take a short break.")
                startPhase(.shortBreak)
            }
        case .shortBreak:
            sendNotification(title: "Back to Work!", body: "Break's over. Session \(sessionsCompleted + 1) starting.")
            startPhase(.work)
        case .longBreak:
            sendNotification(title: "Pomodoro Complete!", body: "All \(totalSessionsTarget) sessions done. Great work!")
            sessionsCompleted = 0
            startPhase(.idle)
        case .idle:
            startPhase(.work)
        }
    }

    // MARK: - Timer

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

        let elapsed = Date().timeIntervalSince(start)
        let newRemaining = pausedRemaining - elapsed
        if newRemaining <= 0 {
            remainingSeconds = 0
            NSSound(named: "Ping")?.play()
            advanceToNextPhase()
        } else {
            remainingSeconds = newRemaining
        }
    }

    // MARK: - Computed

    var progress: Double {
        guard currentPhaseDuration > 0 else { return 0 }
        return 1.0 - (remainingSeconds / currentPhaseDuration)
    }

    var displayTime: String {
        let totalSeconds = Int(remainingSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        NSSound(named: "Ping")?.play()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macisland.pomodoro.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Helper

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
