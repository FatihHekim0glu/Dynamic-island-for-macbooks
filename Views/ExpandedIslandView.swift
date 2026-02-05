// ExpandedIslandView.swift
// MacIsland
//
// The fully expanded island state. Shows:
// - Now-playing info (album art, title, artist) at the top.
// - System controls (volume, brightness sliders) below.
// Revealed on hover, dismissed on hover-out.

import SwiftUI

struct ExpandedIslandView: View {

    @ObservedObject var viewModel: IslandViewModel

    @State private var volume: Float = 0.5
    @State private var brightness: Float = 0.5

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Now Playing Section
            nowPlayingSection

            Divider()
                .background(Color.white.opacity(0.15))

            // MARK: - Controls Section
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
            // Album Art
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Text(info.title.isEmpty ? "Not Playing" : info.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

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

    // MARK: - Controls

    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 10) {
            // Volume
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 14)

                SliderView(value: $volume, tintColor: .white) { newValue in
                    viewModel.setVolume(newValue)
                }
            }

            // Brightness
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 14)

                SliderView(value: $brightness, tintColor: .yellow) { newValue in
                    viewModel.setBrightness(newValue)
                }
            }
        }
    }
}

// MARK: - Custom Slider (compact, Apple-style)

/// A custom slider that matches the compact iOS Control Center aesthetic.
/// The standard SwiftUI Slider is too tall and styled for macOS forms.
private struct SliderView: View {

    @Binding var value: Float
    let tintColor: Color
    var onChanged: ((Float) -> Void)?

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
                        onChanged?(value)
                    }
            )
        }
        .frame(height: 6)
    }
}
