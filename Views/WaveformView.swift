// WaveformView.swift
// MacIsland
//
// Animated waveform bars that pulse when music is playing.
// Uses a simple random-height animation loop to mimic an audio visualizer.
// In a future phase, this could connect to actual audio levels via AudioToolbox.

import SwiftUI

struct WaveformView: View {

    let isPlaying: Bool
    let barCount: Int
    let color: Color

    @State private var barHeights: [CGFloat]

    init(isPlaying: Bool, barCount: Int = 5, color: Color = .white) {
        self.isPlaying = isPlaying
        self.barCount = barCount
        self.color = color
        // Initialize with mid-range heights.
        _barHeights = State(initialValue: (0..<barCount).map { _ in CGFloat.random(in: 0.3...0.7) })
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.9))
                    .frame(width: 3, height: barHeights[index] * 16)
            }
        }
        .frame(height: 16)
        .onAppear { startAnimating() }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startAnimating()
            } else {
                resetBars()
            }
        }
    }

    // MARK: - Animation Loop

    private func startAnimating() {
        guard isPlaying else { return }
        animateBars()
    }

    private func animateBars() {
        guard isPlaying else { return }

        withAnimation(
            .interpolatingSpring(stiffness: 120, damping: 8)
        ) {
            barHeights = (0..<barCount).map { _ in CGFloat.random(in: 0.15...1.0) }
        }

        // Schedule next random update. Vary the interval for organic feel.
        let delay = Double.random(in: 0.15...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            animateBars()
        }
    }

    private func resetBars() {
        withAnimation(.easeOut(duration: 0.4)) {
            barHeights = (0..<barCount).map { _ in CGFloat(0.2) }
        }
    }
}
