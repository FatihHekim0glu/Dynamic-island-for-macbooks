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

    // MARK: - Compact View (split around notch — iPhone Dynamic Island style)
    //
    // The compact pill is wider than the notch (~380pt vs ~180pt notch).
    // Content is split into two "ears" flanking the camera cutout:
    //   Left ear:  album art + song title
    //   Right ear: play/pause indicator + waveform
    // The middle is a solid black bridge that blends with the notch.

    @ViewBuilder
    private var compactView: some View {
        let info = viewModel.nowPlaying
        let notchGap: CGFloat = 140 // approximate camera region to keep clear

        HStack(spacing: 0) {
            // ── Left Ear ──
            HStack(spacing: 6) {
                if let artwork = info.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .onTapGesture { viewModel.openNowPlayingApp() }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                }

                MarqueeText(
                    info.title.isEmpty ? "Not Playing" : info.title,
                    font: .system(size: 11, weight: .medium),
                    color: .white.opacity(0.9),
                    speed: 25,
                    delayBeforeScroll: 2.0
                )
                .frame(height: 14)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Notch Gap (invisible bridge) ──
            Color.clear
                .frame(width: notchGap)

            // ── Right Ear ──
            HStack(spacing: 6) {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .animation(.easeInOut(duration: 0.2), value: info.isPlaying)

                WaveformView(isPlaying: info.isPlaying, barCount: 3, color: .green)
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
