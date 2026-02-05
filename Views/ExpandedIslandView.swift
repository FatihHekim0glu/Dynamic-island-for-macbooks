// ExpandedIslandView.swift
// MacIsland
//
// The fully expanded island state. Shows:
// - Now-playing info (album art, title, artist) — tap art to open source app.
// - Media controls (previous, play/pause, next).
// - System controls (volume, brightness sliders) bound to live system state.

import SwiftUI

struct ExpandedIslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    // Observe sub-services directly so SwiftUI redraws when volume/brightness change externally.
    @ObservedObject var volumeService: VolumeService
    @ObservedObject var brightnessService: BrightnessService

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        self.volumeService = viewModel.volumeService
        self.brightnessService = viewModel.brightnessService
    }

    var body: some View {
        VStack(spacing: 10) {
            // MARK: - Now Playing Section
            nowPlayingSection

            // MARK: - Media Controls
            mediaControlsRow

            Divider()
                .background(Color.white.opacity(0.15))

            // MARK: - System Controls
            controlsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            width: IslandDimensions.expanded.width,
            height: IslandDimensions.expanded.height
        )
        .background(
            RoundedRectangle(cornerRadius: IslandDimensions.expanded.cornerRadius)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: IslandDimensions.expanded.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.12),
                                    .white.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    // MARK: - Now Playing

    @ViewBuilder
    private var nowPlayingSection: some View {
        let info = viewModel.nowPlaying

        HStack(spacing: 12) {
            // Album Art — tap to open source app (Spotify, Apple Music, etc.)
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        viewModel.openNowPlayingApp()
                    }
                    .help("Open in source app")
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.system(size: 18))
                    )
            }

            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    info.title.isEmpty ? "Not Playing" : info.title,
                    font: .system(size: 13, weight: .semibold),
                    color: .white,
                    speed: 25,
                    delayBeforeScroll: 3.0
                )
                .frame(height: 18)

                Text(info.artist.isEmpty ? "—" : info.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Waveform (only when playing)
            WaveformView(isPlaying: info.isPlaying, barCount: 4, color: .green)
                .opacity(info.isPlaying ? 1 : 0.3)
        }
    }

    // MARK: - Media Controls

    @ViewBuilder
    private var mediaControlsRow: some View {
        HStack(spacing: 24) {
            // Previous Track
            Button(action: { viewModel.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            // Play / Pause
            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.nowPlaying.isPlaying)
            }
            .buttonStyle(.plain)

            // Next Track
            Button(action: { viewModel.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - System Controls

    /// Dynamic volume icon based on current level.
    private var volumeIcon: String {
        let vol = volumeService.volume
        if vol <= 0 { return "speaker.slash.fill" }
        if vol < 0.33 { return "speaker.wave.1.fill" }
        if vol < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// Dynamic brightness icon based on current level.
    private var brightnessIcon: String {
        brightnessService.brightness < 0.3
            ? "sun.min.fill"
            : "sun.max.fill"
    }

    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 10) {
            // Volume — bound to live CoreAudio state
            HStack(spacing: 8) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 14)

                SliderView(
                    value: Binding(
                        get: { volumeService.volume },
                        set: { viewModel.setVolume($0) }
                    ),
                    tintColor: .white
                )
            }

            // Brightness — bound to live CoreDisplay state
            HStack(spacing: 8) {
                Image(systemName: brightnessIcon)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 14)

                SliderView(
                    value: Binding(
                        get: { brightnessService.brightness },
                        set: { viewModel.setBrightness($0) }
                    ),
                    tintColor: .yellow
                )
            }
        }
    }
}

// MARK: - Custom Slider (compact, Apple-style)

/// A custom slider that matches the compact iOS Control Center aesthetic.
/// The standard SwiftUI Slider is too tall and styled for macOS forms.
struct SliderView: View {

    @Binding var value: Float
    let tintColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 6)

                // Filled track
                Capsule()
                    .fill(tintColor.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(value), height: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = Float(gesture.location.x / geo.size.width)
                        value = min(max(newValue, 0), 1)
                    }
            )
        }
        .frame(height: 6)
    }
}
