// SystemStatsView.swift
// MacIsland
//
// System stats dashboard: CPU, memory, and network speed.
// Mini bar charts and formatted values.

import SwiftUI

struct SystemStatsView: View {
    @ObservedObject var statsService: SystemStatsService

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text("System")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }

            // CPU
            statRow(
                icon: "cpu",
                label: "CPU",
                value: "\(Int(statsService.cpuUsage * 100))%",
                progress: statsService.cpuUsage,
                color: statsService.isHighCPU ? .red : .cyan
            )

            // Memory
            statRow(
                icon: "memorychip",
                label: "Memory",
                value: String(format: "%.1f / %.0f GB", statsService.memoryUsedGB, statsService.memoryTotalGB),
                progress: statsService.memoryUsage,
                color: statsService.memoryUsage > 0.8 ? .orange : .purple
            )

            // Network
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.7))

                Text(statsService.formatBytes(statsService.networkDownSpeed))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.7))

                Text(statsService.formatBytes(statsService.networkUpSpeed))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func statRow(icon: String, label: String, value: String, progress: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color.opacity(0.7))
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Text(value)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)

                    Capsule()
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * min(CGFloat(progress), 1.0), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)
        }
    }
}
