// BatteryIndicatorView.swift
// MacIsland
//
// Custom battery icon with fill level and charging glow animation.
// Used in idle capsule (small) and expanded view (detailed).

import SwiftUI

// MARK: - Compact Battery (for idle capsule)

struct BatteryBadgeView: View {
    @ObservedObject var service: BatteryService

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: service.batteryIcon)
                .font(.system(size: 9))
                .foregroundColor(service.batteryColor)
                .symbolEffect(.pulse, isActive: service.isCharging)

            Text("\(service.percentage)%")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundColor(service.batteryColor.opacity(0.9))
        }
    }
}

// MARK: - Expanded Battery Row

struct BatteryExpandedView: View {
    @ObservedObject var service: BatteryService

    var body: some View {
        HStack(spacing: 8) {
            // Battery icon with fill animation
            BatteryGaugeView(
                percentage: service.percentage,
                isCharging: service.isCharging,
                color: service.batteryColor
            )
            .frame(width: 28, height: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(service.percentage)%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)

                    if service.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
                }

                if !service.timeRemainingFormatted.isEmpty {
                    Text(service.isCharging ? "\(service.timeRemainingFormatted) until full" : "\(service.timeRemainingFormatted) remaining")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
    }
}

// MARK: - Custom Battery Gauge

struct BatteryGaugeView: View {
    let percentage: Int
    let isCharging: Bool
    let color: Color

    @State private var glowPhase: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bodyWidth = w - 3 // leave room for tip
            let fillWidth = bodyWidth * CGFloat(percentage) / 100.0

            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: bodyWidth, height: h)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isCharging
                        ? AnyShapeStyle(LinearGradient(
                            colors: [color.opacity(0.6), color, color.opacity(0.6)],
                            startPoint: UnitPoint(x: glowPhase - 0.3, y: 0.5),
                            endPoint: UnitPoint(x: glowPhase + 0.3, y: 0.5)
                          ))
                        : AnyShapeStyle(color.opacity(0.8))
                    )
                    .frame(width: max(fillWidth - 2, 0), height: h - 3)
                    .padding(.leading, 1.5)

                // Battery tip
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2, height: h * 0.4)
                    .offset(x: bodyWidth)
            }
        }
        .onAppear {
            if isCharging {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    glowPhase = 1.5
                }
            }
        }
        .onChange(of: isCharging) { _, charging in
            if charging {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    glowPhase = 1.5
                }
            } else {
                glowPhase = 0
            }
        }
    }
}
