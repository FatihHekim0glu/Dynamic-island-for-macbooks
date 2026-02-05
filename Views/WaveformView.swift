// WaveformView.swift
// MacIsland
//
// Tempo-synced waveform visualization using overlapping sine waves.
// Each bar oscillates at a different frequency with harmonics for organic rhythm.
// Uses a Timer to drive animation since TimelineView doesn't reliably fire
// in floating NSPanel windows that aren't part of the main app window hierarchy.

import SwiftUI

struct WaveformView: View {

    let isPlaying: Bool
    let barCount: Int
    let color: Color

    /// Each bar gets a unique frequency and phase offset.
    private let baseFrequencies: [Double]
    private let phaseOffsets: [Double]

    /// Timer-driven animation time. Updated ~30fps.
    @State private var currentTime: Double = Date.timeIntervalSinceReferenceDate
    @State private var timer: Timer? = nil

    init(isPlaying: Bool, barCount: Int = 5, color: Color = .white) {
        self.isPlaying = isPlaying
        self.barCount = barCount
        self.color = color

        var freqs: [Double] = []
        var phases: [Double] = []
        for i in 0..<barCount {
            freqs.append(1.8 + Double(i) * 0.6)
            phases.append(Double(i) * 0.7)
        }
        self.baseFrequencies = freqs
        self.phaseOffsets = phases
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let height = barHeight(for: index, at: currentTime)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.9))
                    .frame(width: 3, height: height * 16)
                    .animation(.linear(duration: 0.05), value: currentTime)
            }
        }
        .frame(height: 16)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startTimer()
            }
            // Keep timer running even when paused so bars settle to rest position
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        // ~30 fps is enough for smooth sine-wave animation
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            currentTime = Date.timeIntervalSinceReferenceDate
        }
        // Make sure timer fires even when tracking mouse in the panel
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Compute bar height using overlapping sine waves.
    private func barHeight(for index: Int, at time: Double) -> CGFloat {
        guard isPlaying else { return 0.2 }

        let freq = baseFrequencies[index]
        let phase = phaseOffsets[index]

        let primary = sin(2 * .pi * freq * time + phase)
        let harmonic = sin(2 * .pi * freq * 2.1 * time + phase * 1.3) * 0.3

        let combined = primary + harmonic
        let normalized = (combined + 1.3) / 2.6
        let mapped = 0.15 + normalized * 0.85

        return CGFloat(mapped)
    }
}
