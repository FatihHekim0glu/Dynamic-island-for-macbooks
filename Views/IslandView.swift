// IslandView.swift
// MacIsland
//
// Root SwiftUI view for the Dynamic Island. This is the single view embedded
// in the NSHostingView inside the floating NSPanel.
//
// Responsibilities:
// - Switch between Idle / Compact / Expanded sub-views based on state.
// - Handle mouse hover tracking to trigger expansion.
// - Apply the interpolatingSpring animations for organic, Apple-physics morphing.

import SwiftUI

struct IslandView: View {

    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        ZStack {
            // The entire view sits on a fully transparent canvas.
            // Only the capsule/rounded-rect shapes are opaque black,
            // which is what makes the click-through transparency work.
            Color.clear

            islandContent
                .onHover { hovering in
                    if hovering {
                        viewModel.onHoverEnter()
                    } else {
                        viewModel.onHoverExit()
                    }
                }
        }
        // The frame matches the NSWindow size (driven by IslandWindowController).
        .frame(
            width: viewModel.dimensions.width,
            height: viewModel.dimensions.height
        )
    }

    // MARK: - State-Driven Content

    @ViewBuilder
    private var islandContent: some View {
        switch viewModel.state {
        case .idle:
            IdleIslandView()
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))

        case .compact:
            compactView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))

        case .expanded:
            ExpandedIslandView(viewModel: viewModel)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Compact View (drops below notch)
    //
    // The compact pill is 300×68pt. The top ~33pt blends with the notch (black),
    // and the content row sits in the visible bottom ~35pt below the notch.
    // This avoids fighting the hardware camera cutout entirely.

    @ViewBuilder
    private var compactView: some View {
        let info = viewModel.nowPlaying

        VStack(spacing: 0) {
            // Top zone — blends with the notch (invisible black)
            Color.clear
                .frame(height: 33)

            // Content zone — visible below the notch
            HStack(spacing: 8) {
                // Album art
                if let artwork = info.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { viewModel.openNowPlayingApp() }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                }

                // Song title — scrolls when too long
                MarqueeText(
                    info.title.isEmpty ? "Not Playing" : info.title,
                    font: .system(size: 12, weight: .medium),
                    color: .white,
                    speed: 30,
                    delayBeforeScroll: 2.0
                )
                .frame(height: 16)

                Spacer(minLength: 4)

                // Play/pause indicator
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .animation(.easeInOut(duration: 0.2), value: info.isPlaying)

                // Waveform bars
                WaveformView(isPlaying: info.isPlaying, barCount: 3, color: .green)
            }
            .padding(.horizontal, 14)
            .frame(height: 35)
        }
        .frame(
            width: IslandDimensions.compact.width,
            height: IslandDimensions.compact.height
        )
        .background(
            RoundedRectangle(cornerRadius: IslandDimensions.compact.cornerRadius)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: IslandDimensions.compact.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.06),
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
}

// MARK: - Preview

#Preview {
    IslandView(viewModel: IslandViewModel())
        .frame(width: 400, height: 200)
        .background(.gray.opacity(0.3))
}
