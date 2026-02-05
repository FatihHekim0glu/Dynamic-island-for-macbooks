// WaveformView.swift
// MacIsland
//
// Tempo-synced waveform visualization using overlapping sine waves.
// Each bar oscillates at a different frequency with harmonics for organic rhythm.
//
// WHY sine waves instead of real audio FFT?
// - Real system audio capture requires Screen Recording permission on macOS.
// - FFT analysis adds significant complexity (AudioToolbox, buffer management).
// - Sine-wave approach creates a convincing rhythmic visualizer with zero permissions.
// - Uses TimelineView for proper display-linked animation (no DispatchQueue hacks).

import SwiftUI

struct WaveformView: View {

    let isPlaying: Bool
    let barCount: Int
    let color: Color

    /// Each bar gets a unique frequency and phase offset to create varied but rhythmic motion.
    private let baseFrequencies: [Double]
    private let phaseOffsets: [Double]

    init(isPlaying: Bool, barCount: Int = 5, color: Color = .white) {
        self.isPlaying = isPlaying
        self.barCount = barCount
        self.color = color

        // Generate deterministic but varied frequencies per bar.
        // Primary frequency between 1.5 Hz and 4 Hz (typical music beat range).
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
        // TimelineView fires at display refresh rate and pauses automatically
        // when the view is off-screen — no manual timer management needed.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let height = barHeight(
                        for: index,
                        at: timeline.date.timeIntervalSinceReferenceDate
                    )
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(0.9))
                        .frame(width: 3, height: height * 16)
                }
            }
        }
        .frame(height: 16)
    }

    /// Compute bar height using overlapping sine waves for organic, rhythmic motion.
    private func barHeight(for index: Int, at time: Double) -> CGFloat {
        // When not playing, return a flat resting height.
        guard isPlaying else { return 0.2 }

        let freq = baseFrequencies[index]
        let phase = phaseOffsets[index]

        // Combine two sine waves for more organic motion:
        // - Primary wave at the bar's base frequency.
        // - Secondary harmonic at ~2x frequency with lower amplitude.
        // This mimics the look of frequency-band analysis without actual FFT.
        let primary = sin(2 * .pi * freq * time + phase)
        let harmonic = sin(2 * .pi * freq * 2.1 * time + phase * 1.3) * 0.3

        // Map the combined signal from [-1.3, 1.3] to [0.15, 1.0].
        let combined = primary + harmonic
        let normalized = (combined + 1.3) / 2.6
        let mapped = 0.15 + normalized * 0.85

        return CGFloat(mapped)
    }
}
