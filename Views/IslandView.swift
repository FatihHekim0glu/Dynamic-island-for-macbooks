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

    // MARK: - Compact View (inline music pill)

    @ViewBuilder
    private var compactView: some View {
        let info = viewModel.nowPlaying

        HStack(spacing: 10) {
            // Mini album art — tap to open source app
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 6)
                    .onTapGesture {
                        viewModel.openNowPlayingApp()
                    }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .padding(.leading, 6)
            }

            // Song title — auto-scrolls when text is too long for the pill
            MarqueeText(
                info.title,
                font: .system(size: 12, weight: .medium),
                color: .white,
                speed: 30,
                delayBeforeScroll: 2.0
            )
            .frame(height: 16)

            Spacer()

            // Waveform indicator
            WaveformView(isPlaying: info.isPlaying, barCount: 3, color: .green)
                .padding(.trailing, 8)
        }
        .frame(
            width: IslandDimensions.compact.width,
            height: IslandDimensions.compact.height
        )
        .background(
            Capsule()
                .fill(.black)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.08),
                                    .clear
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
