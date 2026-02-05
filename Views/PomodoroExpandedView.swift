// PomodoroExpandedView.swift
// MacIsland
//
// Full Pomodoro UI: phase indicator, large countdown,
// session progress, and controls.

import SwiftUI

struct PomodoroExpandedView: View {
    @ObservedObject var pomodoroService: PomodoroService

    var body: some View {
        VStack(spacing: 10) {
            // Phase indicator
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12))
                    .foregroundColor(phaseColor)
                Text(pomodoroService.phase.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(phaseColor)
                Spacer()

                // Session progress
                HStack(spacing: 4) {
                    ForEach(0..<pomodoroService.totalSessionsTarget, id: \.self) { i in
                        Circle()
                            .fill(i < pomodoroService.sessionsCompleted ? phaseColor : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            // Large countdown with ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                    .frame(width: 90, height: 90)

                Circle()
                    .trim(from: 0, to: pomodoroService.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: pomodoroService.progress)

                VStack(spacing: 2) {
                    Text(pomodoroService.displayTime)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text(pomodoroService.phase.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(phaseColor.opacity(0.8))
                }
            }
            .frame(height: 95)

            // Controls
            HStack(spacing: 20) {
                // Reset
                Button(action: { pomodoroService.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                // Start/Pause
                Button(action: { pomodoroService.togglePause() }) {
                    Image(systemName: pomodoroService.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundColor(phaseColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                // Skip phase
                Button(action: { pomodoroService.skip() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Duration presets
            if pomodoroService.phase == .idle {
                HStack(spacing: 6) {
                    durationButton("20/5", work: 20*60, shortBreak: 5*60)
                    durationButton("25/5", work: 25*60, shortBreak: 5*60)
                    durationButton("45/10", work: 45*60, shortBreak: 10*60)
                    durationButton("50/10", work: 50*60, shortBreak: 10*60)
                }
            }
        }
    }

    private var phaseColor: Color {
        switch pomodoroService.phase {
        case .work:       return .red
        case .shortBreak: return .green
        case .longBreak:  return .blue
        case .idle:       return .orange
        }
    }

    @ViewBuilder
    private func durationButton(_ label: String, work: TimeInterval, shortBreak: TimeInterval) -> some View {
        Button(action: {
            pomodoroService.workDuration = work
            pomodoroService.shortBreakDuration = shortBreak
        }) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(
                    pomodoroService.workDuration == work ? phaseColor : .white.opacity(0.5)
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        pomodoroService.workDuration == work
                        ? phaseColor.opacity(0.15)
                        : Color.white.opacity(0.06)
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
