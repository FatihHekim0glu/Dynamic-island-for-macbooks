// IslandViewModel.swift
// MacIsland
//
// Central state machine for the Dynamic Island.
// Drives the SwiftUI view transitions between Idle / Compact / Expanded states.
// Owns the NowPlayingService and reacts to playback changes.

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
    static let compact  = IslandDimensions(width: 280, height: 38, cornerRadius: 19)
    static let expanded = IslandDimensions(width: 360, height: 180, cornerRadius: 24)
}

// MARK: - ViewModel

@MainActor
final class IslandViewModel: ObservableObject {

    // MARK: Published State

    @Published var state: IslandState = .idle
    @Published var isHovering: Bool = false

    // MARK: Dependencies

    let nowPlayingService: NowPlayingService

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

    // MARK: - System Controls (stubs for Phase 1)

    func setVolume(_ value: Float) {
        // Use CoreAudio or NSSound to set system volume.
        // Phase 1: execute AppleScript as a quick bridge.
        let script = "set volume output volume \(Int(value * 100))"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    func setBrightness(_ value: Float) {
        // CoreDisplay / IOKit brightness setting.
        // Phase 1: execute via external `brightness` CLI or skip gracefully.
        let script = """
        do shell script "brightness \(String(format: "%.2f", value))"
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
