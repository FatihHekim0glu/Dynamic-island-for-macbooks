// TimerCompactView.swift
// MacIsland
//
// Compact timer display for the island pill.
// Shows circular progress ring + countdown text.

import SwiftUI

struct TimerCompactView: View {
    @ObservedObject var timerService: TimerService

    var body: some View {
        HStack(spacing: 8) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    .frame(width: 22, height: 22)

                Circle()
                    .trim(from: 0, to: timerService.mode == .countdown ? timerService.progress : 0)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))

                Image(systemName: timerService.mode == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }

            // Time display
            Text(timerService.displayTime)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)

            Spacer(minLength: 4)

            // Pause/play indicator
            if timerService.isRunning {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
    }
}
