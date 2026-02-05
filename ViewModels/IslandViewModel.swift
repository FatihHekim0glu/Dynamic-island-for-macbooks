// IslandViewModel.swift
// MacIsland
//
// Central state machine for the Dynamic Island.
// Drives the SwiftUI view transitions between Idle / Compact / Expanded states.
// Owns all services: NowPlaying, Volume, Brightness, Battery, Privacy,
// Timer, Pomodoro, Calendar, Network, Focus, Bluetooth, SystemStats, Notifications.

import SwiftUI
import Combine

// MARK: - Island State

enum IslandState: Equatable {
    case idle
    case compact
    case expanded
}

// MARK: - Expanded Tab

enum ExpandedTab: String, CaseIterable, Identifiable {
    case media
    case timer
    case system

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .media:  return "music.note"
        case .timer:  return "timer"
        case .system: return "cpu"
        }
    }

    var label: String {
        switch self {
        case .media:  return "Media"
        case .timer:  return "Timer"
        case .system: return "System"
        }
    }
}

// MARK: - Island Dimensions

struct IslandDimensions {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    static let idle     = IslandDimensions(width: 400, height: 32, cornerRadius: 16)
    static let compact  = IslandDimensions(width: 300, height: 68, cornerRadius: 22)
    static let expanded = IslandDimensions(width: 380, height: 320, cornerRadius: 24)
}

// MARK: - ViewModel

@MainActor
final class IslandViewModel: ObservableObject {

    // MARK: Published State

    @Published var state: IslandState = .idle
    @Published var isHovering: Bool = false
    @Published var selectedTab: ExpandedTab = .media

    // MARK: Dependencies — Original

    let nowPlayingService: NowPlayingService
    let volumeService: VolumeService
    let brightnessService: BrightnessService

    // MARK: Dependencies — New Features

    let batteryService: BatteryService
    let privacyService: PrivacyIndicatorService
    let timerService: TimerService
    let pomodoroService: PomodoroService
    let calendarService: CalendarService
    let networkService: NetworkService
    let focusService: FocusService
    let bluetoothService: BluetoothBatteryService
    let systemStatsService: SystemStatsService
    let notificationService: NotificationService

    // MARK: Forwarded State

    @Published var nowPlaying: NowPlayingInfo = .empty

    // MARK: Computed

    var dimensions: IslandDimensions {
        switch state {
        case .idle:     return .idle
        case .compact:  return .compact
        case .expanded: return .expanded
        }
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private var hoverOutTask: Task<Void, Never>?

    // MARK: - Init

    init(nowPlayingService: NowPlayingService? = nil) {
        self.nowPlayingService = nowPlayingService ?? NowPlayingService()
        self.volumeService = VolumeService()
        self.brightnessService = BrightnessService()
        self.batteryService = BatteryService()
        self.privacyService = PrivacyIndicatorService()
        self.timerService = TimerService()
        self.pomodoroService = PomodoroService()
        self.calendarService = CalendarService()
        self.networkService = NetworkService()
        self.focusService = FocusService()
        self.bluetoothService = BluetoothBatteryService()
        self.systemStatsService = SystemStatsService()
        self.notificationService = NotificationService()

        bindNowPlaying()
        bindNotifications()
        bindTimerState()
    }

    // MARK: - Bindings

    private func bindNowPlaying() {
        nowPlayingService.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self else { return }
                self.nowPlaying = info
                self.updateStateForPlayback(info)
            }
            .store(in: &cancellables)
    }

    private func bindNotifications() {
        notificationService.$hasActiveNotification
            .receive(on: RunLoop.main)
            .sink { [weak self] hasNotification in
                guard let self else { return }
                if hasNotification && self.state == .idle {
                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                        self.state = .compact
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func bindTimerState() {
        timerService.$isRunning
            .combineLatest(pomodoroService.$isRunning)
            .receive(on: RunLoop.main)
            .sink { [weak self] timerRunning, pomodoroRunning in
                guard let self else { return }
                if (timerRunning || pomodoroRunning) && self.state == .idle && !self.isHovering {
                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                        self.state = .compact
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func updateStateForPlayback(_ info: NowPlayingInfo) {
        if isHovering { return }
        if notificationService.hasActiveNotification { return }

        if info.isPlaying && !info.title.isEmpty {
            if state != .compact {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                    state = .compact
                }
            }
        } else if !timerService.isRunning && !pomodoroService.isRunning {
            if state != .idle {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                    state = .idle
                }
            }
        }
    }

    // MARK: - Compact Content Priority

    var compactContentType: IslandContentType {
        if notificationService.hasActiveNotification { return .notification }
        if timerService.isRunning || timerService.mode != .idle { return .timer }
        if pomodoroService.isRunning || pomodoroService.phase != .idle { return .pomodoro }
        if nowPlaying.isPlaying && !nowPlaying.title.isEmpty { return .media }
        if let event = calendarService.nextEvent, event.minutesUntilStart <= 30 { return .calendar }
        return .media
    }

    // MARK: - Hover Handling

    func onHoverEnter() {
        hoverOutTask?.cancel()
        isHovering = true

        withAnimation(.interpolatingSpring(stiffness: 170, damping: 15)) {
            state = .expanded
        }
    }

    func onHoverExit() {
        hoverOutTask?.cancel()

        hoverOutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            isHovering = false
            let info = self.nowPlaying

            withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                if info.isPlaying && !info.title.isEmpty {
                    state = .compact
                } else if timerService.isRunning || pomodoroService.isRunning {
                    state = .compact
                } else {
                    state = .idle
                }
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        nowPlayingService.togglePlayPause()
    }

    func nextTrack() {
        nowPlayingService.nextTrack()
    }

    func previousTrack() {
        nowPlayingService.previousTrack()
    }

    func openNowPlayingApp() {
        nowPlayingService.getNowPlayingAppPID { pid in
            if pid > 0,
               let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
            }
        }
    }

    // MARK: - System Controls

    func setVolume(_ value: Float) {
        volumeService.setVolume(value)
    }

    func setBrightness(_ value: Float) {
        brightnessService.setBrightness(value)
    }
}
