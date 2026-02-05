// IslandView.swift
// MacIsland
//
// Root SwiftUI view for the Dynamic Island.
// Switches between Idle / Compact / Expanded sub-views based on state.
// Compact view dynamically shows highest-priority content (notification,
// timer, music, calendar) via compactContentType.

import SwiftUI

struct IslandView: View {

    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        ZStack {
            Color.clear

            islandContent
                .onHover { hovering in
                    if hovering {
                        viewModel.onHoverEnter()
                    } else {
                        viewModel.onHoverExit()
                    }
                }
        }
        .frame(
            width: viewModel.dimensions.width,
            height: viewModel.dimensions.height
        )
    }

    // MARK: - State-Driven Content

    @ViewBuilder
    private var islandContent: some View {
        switch viewModel.state {
        case .idle:
            IdleIslandView(viewModel: viewModel)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))

        case .compact:
            compactView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))

        case .expanded:
            ExpandedIslandView(viewModel: viewModel)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Compact View

    @ViewBuilder
    private var compactView: some View {
        VStack(spacing: 0) {
            // Top zone — blends with the notch (invisible black)
            Color.clear
                .frame(height: 33)

            // Content zone — visible below the notch
            compactContent
                .frame(height: 35)
        }
        .frame(
            width: IslandDimensions.compact.width,
            height: IslandDimensions.compact.height
        )
        .background(
            RoundedRectangle(cornerRadius: IslandDimensions.compact.cornerRadius)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: IslandDimensions.compact.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.06), .white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    // MARK: - Dynamic Compact Content

    @ViewBuilder
    private var compactContent: some View {
        switch viewModel.compactContentType {
        case .notification:
            notificationCompact

        case .timer:
            TimerCompactView(timerService: viewModel.timerService)

        case .pomodoro:
            PomodoroCompactView(pomodoroService: viewModel.pomodoroService)

        case .calendar:
            CalendarCompactView(calendarService: viewModel.calendarService)

        default:
            mediaCompact
        }
    }

    // MARK: - Media Compact

    @ViewBuilder
    private var mediaCompact: some View {
        let info = viewModel.nowPlaying

        HStack(spacing: 8) {
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { viewModel.openNowPlayingApp() }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
            }

            MarqueeText(
                info.title.isEmpty ? "Not Playing" : info.title,
                font: .system(size: 12, weight: .medium),
                color: .white,
                speed: 30,
                delayBeforeScroll: 2.0
            )
            .frame(height: 16)

            Spacer(minLength: 4)

            Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
                .contentTransition(.symbolEffect(.replace.offUp))
                .animation(.easeInOut(duration: 0.2), value: info.isPlaying)

            WaveformView(isPlaying: info.isPlaying, barCount: 3, color: .green)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Notification Compact

    @ViewBuilder
    private var notificationCompact: some View {
        if let notification = viewModel.notificationService.currentNotification {
            NotificationBubbleView(notification: notification, onDismiss: { viewModel.notificationService.dismiss() })
        } else {
            mediaCompact
        }
    }
}

#Preview {
    IslandView(viewModel: IslandViewModel())
        .frame(width: 400, height: 200)
        .background(.gray.opacity(0.3))
}
