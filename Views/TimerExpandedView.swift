// TimerExpandedView.swift
// MacIsland
//
// Full timer UI: large countdown, circular progress, preset buttons,
// start/pause/reset controls, and stopwatch mode toggle.

import SwiftUI

struct TimerExpandedView: View {
    @ObservedObject var timerService: TimerService

    var body: some View {
        VStack(spacing: 10) {
            // Mode toggle
            HStack(spacing: 12) {
                modeButton("Timer", icon: "timer", isActive: timerService.mode != .stopwatch) {
                    if timerService.mode == .idle || timerService.mode == .stopwatch {
                        timerService.reset()
                    }
                }
                modeButton("Stopwatch", icon: "stopwatch.fill", isActive: timerService.mode == .stopwatch) {
                    timerService.startStopwatch()
                }
            }

            // Large countdown / stopwatch display
            ZStack {
                // Progress ring (countdown only)
                if timerService.mode == .countdown {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: timerService.progress)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: timerService.progress)
                }

                Text(timerService.displayTime)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(height: 85)

            // Preset buttons (only when idle or countdown mode)
            if timerService.mode != .stopwatch {
                HStack(spacing: 8) {
                    presetButton("1m", seconds: 60)
                    presetButton("5m", seconds: 300)
                    presetButton("10m", seconds: 600)
                    presetButton("15m", seconds: 900)
                    presetButton("25m", seconds: 1500)
                }
            }

            // Controls
            HStack(spacing: 20) {
                // Reset
                Button(action: { timerService.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                // Play/Pause
                Button(action: { timerService.togglePause() }) {
                    Image(systemName: timerService.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                // Stop
                Button(action: { timerService.reset() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func modeButton(_ label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? .orange : .white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isActive ? Color.orange.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func presetButton(_ label: String, seconds: TimeInterval) -> some View {
        Button(action: { timerService.startCountdown(seconds: seconds) }) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
