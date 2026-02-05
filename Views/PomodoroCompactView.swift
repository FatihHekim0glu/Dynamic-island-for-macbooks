// PomodoroCompactView.swift
// MacIsland
//
// Compact Pomodoro display: red progress ring + session dots + countdown.

import SwiftUI

struct PomodoroCompactView: View {
    @ObservedObject var pomodoroService: PomodoroService

    var body: some View {
        HStack(spacing: 8) {
            // Phase-colored progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    .frame(width: 22, height: 22)

                Circle()
                    .trim(from: 0, to: pomodoroService.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "leaf.fill")
                    .font(.system(size: 7))
                    .foregroundColor(phaseColor)
            }

            // Phase label + time
            VStack(alignment: .leading, spacing: 1) {
                Text(pomodoroService.phase.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(phaseColor)

                Text(pomodoroService.displayTime)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
            }

            Spacer(minLength: 4)

            // Session dots
            HStack(spacing: 3) {
                ForEach(0..<pomodoroService.totalSessionsTarget, id: \.self) { i in
                    Circle()
                        .fill(i < pomodoroService.sessionsCompleted ? phaseColor : Color.white.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var phaseColor: Color {
        switch pomodoroService.phase {
        case .work:       return .red
        case .shortBreak: return .green
        case .longBreak:  return .blue
        case .idle:       return .gray
        }
    }
}
