// IdleIslandView.swift
// MacIsland
//
// The "Black Hole" — a wide capsule that merges with the hardware notch.
// Status indicators sit in the visible "wings" that extend past the notch:
//   Left wing:  DND moon, privacy dots (camera/mic)
//   Right wing: CPU warning, battery badge

import SwiftUI

struct IdleIslandView: View {

    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        ZStack {
            // Base capsule — extends past the notch on both sides
            Capsule()
                .fill(.black)
                .frame(
                    width: IslandDimensions.idle.width,
                    height: IslandDimensions.idle.height
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )

            // Status indicators in the wings (outside the notch)
            HStack(spacing: 0) {
                // ── LEFT WING ── (push content to the LEFT edge, away from notch)
                HStack(spacing: 5) {
                    if viewModel.focusService.isDNDActive {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                    }

                    if viewModel.privacyService.isCameraActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .modifier(PulseModifier())
                    }

                    if viewModel.privacyService.isMicActive {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .modifier(PulseModifier())
                    }

                    // Wi-Fi signal quality
                    Image(systemName: viewModel.networkService.signalQuality.icon)
                        .font(.system(size: 10))
                        .foregroundColor(wifiColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                // ── NOTCH ZONE ── (dead space behind the physical notch)
                Spacer()
                    .frame(width: 180)

                // ── RIGHT WING ── (push content to the RIGHT edge, away from notch)
                HStack(spacing: 5) {
                    if viewModel.systemStatsService.isHighCPU {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }

                    BatteryBadgeView(service: viewModel.batteryService)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            }
            .frame(
                width: IslandDimensions.idle.width,
                height: IslandDimensions.idle.height
            )
        }
    }
    private var wifiColor: Color {
        switch viewModel.networkService.signalQuality {
        case .excellent: return .green
        case .good:      return .white.opacity(0.7)
        case .fair:      return .yellow
        case .poor:      return .red
        case .disconnected: return .gray.opacity(0.4)
        }
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 0.9)
            .opacity(isPulsing ? 1.0 : 0.7)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
