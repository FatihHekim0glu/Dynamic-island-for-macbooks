// IslandViewModel.swift
// MacIsland
//
// Central state machine for the Dynamic Island.
// Drives the SwiftUI view transitions between Idle / Compact / Expanded states.
// Owns the NowPlayingService, VolumeService, and BrightnessService.

import SwiftUI
import Combine

// MARK: - Island State

enum IslandState: Equatable {
    /// Default resting state — small black capsule that merges with the notch.
    case idle

    /// Music is playing — shows a compact pill with title + waveform.
    case compact

    /// User hovered or tapped — full expansion with controls.
    case expanded
}

// MARK: - Island Dimensions

/// Pre-defined sizes for each state. These drive both the SwiftUI frame
/// and the NSWindow resize in IslandWindowController.
struct IslandDimensions {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    static let idle     = IslandDimensions(width: 200, height: 32, cornerRadius: 16)
    static let compact  = IslandDimensions(width: 380, height: 38, cornerRadius: 19)
    // Height increased from 180 → 220 to accommodate the media controls row.
    static let expanded = IslandDimensions(width: 360, height: 220, cornerRadius: 24)
}

// MARK: - ViewModel

@MainActor
final class IslandViewModel: ObservableObject {

    // MARK: Published State

    @Published var state: IslandState = .idle
    @Published var isHovering: Bool = false

    // MARK: Dependencies

    let nowPlayingService: NowPlayingService
    let volumeService: VolumeService
    let brightnessService: BrightnessService

    // MARK: Computed

    var dimensions: IslandDimensions {
        switch state {
        case .idle:     return .idle
        case .compact:  return .compact
        case .expanded: return .expanded
        }
    }

    var nowPlaying: NowPlayingInfo {
        nowPlayingService.nowPlaying
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()

    /// Debounce timer for hover-out so the island doesn't flicker.
    private var hoverOutTask: Task<Void, Never>?

    // MARK: - Init

    init(nowPlayingService: NowPlayingService? = nil) {
        self.nowPlayingService = nowPlayingService ?? NowPlayingService()
        self.volumeService = VolumeService()
        self.brightnessService = BrightnessService()
        bindNowPlaying()
    }

    // MARK: - Bindings

    private func bindNowPlaying() {
        nowPlayingService.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self else { return }
                self.updateStateForPlayback(info)
            }
            .store(in: &cancellables)
    }

    /// Determine the correct state based on playback + hover.
    private func updateStateForPlayback(_ info: NowPlayingInfo) {
        if isHovering {
            // Hover always wins — keep expanded.
            return
        }

        if info.isPlaying && !info.title.isEmpty {
            if state != .compact {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                    state = .compact
                }
            }
        } else {
            if state != .idle {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                    state = .idle
                }
            }
        }
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

        // Debounce hover-out by 400ms to prevent flicker when the cursor
        // briefly leaves the window during animations.
        hoverOutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            isHovering = false
            let info = nowPlayingService.nowPlaying

            withAnimation(.interpolatingSpring(stiffness: 200, damping: 18)) {
                if info.isPlaying && !info.title.isEmpty {
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

    /// Activate the app that is currently providing now-playing info (e.g., Spotify, Apple Music).
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
