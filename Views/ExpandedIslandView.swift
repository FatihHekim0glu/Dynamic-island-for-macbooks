// ExpandedIslandView.swift
// MacIsland
//
// The fully expanded island state with tabbed content:
// - Media tab: Now-playing, controls, volume/brightness sliders
// - Timer tab: Countdown timer + Pomodoro
// - System tab: CPU/memory stats, network, Wi-Fi, battery, calendar, DND, bluetooth

import SwiftUI

struct ExpandedIslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var volumeService: VolumeService
    @ObservedObject var brightnessService: BrightnessService

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        self.volumeService = viewModel.volumeService
        self.brightnessService = viewModel.brightnessService
    }

    var body: some View {
        VStack(spacing: 6) {
            // Tab picker
            tabBar

            // Tab content
            tabContent
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(
            width: IslandDimensions.expanded.width,
            height: IslandDimensions.expanded.height
        )
        .background(
            RoundedRectangle(cornerRadius: IslandDimensions.expanded.cornerRadius)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: IslandDimensions.expanded.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ExpandedTab.allCases) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: viewModel.selectedTab == tab,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedTab = tab
                        }
                    }
                )
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .media:
            mediaTab
        case .timer:
            TimerExpandedView(timerService: viewModel.timerService)
        case .pomodoro:
            PomodoroExpandedView(pomodoroService: viewModel.pomodoroService)
        case .system:
            systemTab
        }
    }

    // MARK: - Media Tab

    @ViewBuilder
    private var mediaTab: some View {
        VStack(spacing: 8) {
            nowPlayingSection
            mediaControlsRow

            Divider().background(Color.white.opacity(0.15))

            controlsSection
        }
    }

    // MARK: - Now Playing

    @ViewBuilder
    private var nowPlayingSection: some View {
        let info = viewModel.nowPlaying

        HStack(spacing: 12) {
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { viewModel.openNowPlayingApp() }
                    .help("Open in source app")
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.system(size: 16))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    info.title.isEmpty ? "Not Playing" : info.title,
                    font: .system(size: 12, weight: .semibold),
                    color: .white,
                    speed: 25,
                    delayBeforeScroll: 3.0
                )
                .frame(height: 16)

                Text(info.artist.isEmpty ? "—" : info.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            WaveformView(isPlaying: info.isPlaying, barCount: 4, color: .green)
                .opacity(info.isPlaying ? 1 : 0.3)
        }
    }

    // MARK: - Media Controls

    @ViewBuilder
    private var mediaControlsRow: some View {
        HStack(spacing: 24) {
            MediaControlButton(
                systemName: "backward.fill",
                fontSize: 14,
                action: {
                    HapticHelper.tap()
                    viewModel.previousTrack()
                }
            )

            MediaControlButton(
                systemName: viewModel.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                fontSize: 20,
                isBright: true,
                action: {
                    HapticHelper.tap()
                    viewModel.togglePlayPause()
                }
            )
            .contentTransition(.symbolEffect(.replace.offUp))
            .animation(.easeInOut(duration: 0.2), value: viewModel.nowPlaying.isPlaying)

            MediaControlButton(
                systemName: "forward.fill",
                fontSize: 14,
                action: {
                    HapticHelper.tap()
                    viewModel.nextTrack()
                }
            )
        }
    }

    // MARK: - System Controls (Volume/Brightness)

    private var volumeIcon: String {
        let vol = volumeService.volume
        if vol <= 0 { return "speaker.slash.fill" }
        if vol < 0.33 { return "speaker.wave.1.fill" }
        if vol < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var brightnessIcon: String {
        brightnessService.brightness < 0.3 ? "sun.min.fill" : "sun.max.fill"
    }

    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 12)

                SliderView(
                    value: Binding(
                        get: { volumeService.volume },
                        set: { viewModel.setVolume($0) }
                    ),
                    tintColor: .white
                )
            }

            HStack(spacing: 8) {
                Image(systemName: brightnessIcon)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 12)

                SliderView(
                    value: Binding(
                        get: { brightnessService.brightness },
                        set: { viewModel.setBrightness($0) }
                    ),
                    tintColor: .yellow
                )
            }
        }
    }

    // MARK: - System Tab

    @ViewBuilder
    private var systemTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                // Battery
                BatteryExpandedView(service: viewModel.batteryService)

                Divider().background(Color.white.opacity(0.1))

                // System Stats
                SystemStatsView(statsService: viewModel.systemStatsService)

                Divider().background(Color.white.opacity(0.1))

                // Network / Wi-Fi
                networkRow

                Divider().background(Color.white.opacity(0.1))

                // Bottom row: Calendar + DND + Bluetooth
                HStack(spacing: 12) {
                    // DND Toggle
                    dndToggle

                    Spacer()

                    // Bluetooth device
                    if viewModel.bluetoothService.hasConnectedDevice,
                       let device = viewModel.bluetoothService.connectedDevice {
                        AirPodsBatteryView(device: device)
                    }
                }

                // Calendar
                if viewModel.calendarService.nextEvent != nil {
                    Divider().background(Color.white.opacity(0.1))
                    CalendarExpandedView(calendarService: viewModel.calendarService)
                }

                // Privacy indicators
                if viewModel.privacyService.isMicActive || viewModel.privacyService.isCameraActive {
                    Divider().background(Color.white.opacity(0.1))
                    privacyRow
                }
            }
        }
    }

    // MARK: - Network Row

    @ViewBuilder
    private var networkRow: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.networkService.signalQuality.icon)
                .font(.system(size: 11))
                .foregroundColor(networkColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.networkService.ssid ?? "Not Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(viewModel.networkService.signalQuality.rawValue.capitalized)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if viewModel.networkService.isConnected {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7))
                        Text(viewModel.systemStatsService.formatBytes(viewModel.systemStatsService.networkDownSpeed))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 7))
                        Text(viewModel.systemStatsService.formatBytes(viewModel.systemStatsService.networkUpSpeed))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private var networkColor: Color {
        switch viewModel.networkService.signalQuality {
        case .excellent: return .green
        case .good:      return .white
        case .fair:      return .yellow
        case .poor:      return .red
        case .disconnected: return .gray
        }
    }

    // MARK: - DND Toggle

    @ViewBuilder
    private var dndToggle: some View {
        Button(action: {
            HapticHelper.tap()
            viewModel.focusService.toggleDND()
        }) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.focusService.isDNDActive ? "moon.fill" : "moon")
                    .font(.system(size: 10))
                Text(viewModel.focusService.isDNDActive ? "Focus On" : "Focus Off")
                    .font(.system(size: 9))
            }
            .foregroundColor(viewModel.focusService.isDNDActive ? .purple : .white.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    viewModel.focusService.isDNDActive
                        ? Color.purple.opacity(0.2)
                        : Color.white.opacity(0.05)
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Privacy Row

    @ViewBuilder
    private var privacyRow: some View {
        HStack(spacing: 8) {
            if viewModel.privacyService.isCameraActive {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Camera")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text(viewModel.privacyService.cameraAppName)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            if viewModel.privacyService.isMicActive {
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("Mic")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    Text(viewModel.privacyService.micAppName)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
    }
}

// MARK: - Tab Bar Button (with hover state)

struct TabBarButton: View {

    let tab: ExpandedTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 9))
                Text(tab.label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(
                isSelected
                    ? .white
                    : (isHovering ? .white.opacity(0.55) : .white.opacity(0.35))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Media Control Button (with hover highlight)

struct MediaControlButton: View {

    let systemName: String
    var fontSize: CGFloat = 14
    var isBright: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .foregroundColor(isBright ? .white : .white.opacity(0.8))
                .frame(width: fontSize + 16, height: fontSize + 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovering ? 0.1 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Enhanced Custom Slider

struct SliderView: View {

    @Binding var value: Float
    let tintColor: Color

    @State private var isHovering = false
    @State private var isDragging = false

    private var trackHeight: CGFloat {
        isHovering || isDragging ? 8 : 6
    }

    private var percentageText: String {
        "\(Int(value * 100))%"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: trackHeight)

                // Filled track
                Capsule()
                    .fill(tintColor.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(value), height: trackHeight)

                // Thumb (visible on hover or drag)
                if isHovering || isDragging {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .offset(x: thumbOffset(in: geo.size.width))
                }

                // Percentage tooltip while dragging
                if isDragging {
                    Text(percentageText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                        )
                        .offset(x: tooltipOffset(in: geo.size.width), y: -16)
                }
            }
            .frame(height: max(trackHeight, 10))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = Float(gesture.location.x / geo.size.width)
                        value = min(max(newValue, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
        }
        .frame(height: 10)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
    }

    /// Offset for the thumb circle so it stays centered on the filled edge
    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        let thumbRadius: CGFloat = 5
        let position = totalWidth * CGFloat(value)
        return position - thumbRadius
    }

    /// Offset for the percentage tooltip, clamped so it doesn't overflow
    private func tooltipOffset(in totalWidth: CGFloat) -> CGFloat {
        let position = totalWidth * CGFloat(value)
        let tooltipHalfWidth: CGFloat = 18
        return min(max(position - tooltipHalfWidth, 0), totalWidth - tooltipHalfWidth * 2)
    }
}

// MARK: - Haptic Feedback

private enum HapticHelper {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
