// AirPodsBatteryView.swift
// MacIsland
//
// AirPods / Bluetooth battery display for expanded view.
// Shows per-ear + case breakdown for AirPods, or overall battery for other devices.

import SwiftUI

struct AirPodsBatteryView: View {
    let device: BluetoothDeviceInfo

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: device.isAirPods ? "airpodspro" : "headphones")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))

                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)

                Spacer()
            }

            if device.isAirPods && (device.leftBattery != nil || device.rightBattery != nil) {
                // AirPods per-ear layout
                HStack(spacing: 16) {
                    if let left = device.leftBattery {
                        earView(label: "L", percentage: left, icon: "ear.and.waveform")
                    }
                    if let right = device.rightBattery {
                        earView(label: "R", percentage: right, icon: "ear.and.waveform")
                    }
                    if let caseBattery = device.caseBattery {
                        earView(label: "Case", percentage: caseBattery, icon: "case.fill")
                    }
                }
            } else {
                // Generic device — single battery bar
                HStack(spacing: 8) {
                    Image(systemName: device.batteryIcon)
                        .font(.system(size: 12))
                        .foregroundColor(batteryColor(device.displayBattery))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 6)
                            Capsule()
                                .fill(batteryColor(device.displayBattery))
                                .frame(width: geo.size.width * CGFloat(device.displayBattery) / 100.0, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(device.displayBattery)%")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func earView(label: String, percentage: Int, icon: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: CGFloat(percentage) / 100.0)
                    .stroke(batteryColor(percentage), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))

                Text("\(percentage)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
            }
        }
    }

    private func batteryColor(_ percentage: Int) -> Color {
        if percentage > 50 { return .green }
        if percentage > 20 { return .yellow }
        return .red
    }
}
