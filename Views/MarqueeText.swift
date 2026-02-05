// MarqueeText.swift
// MacIsland
//
// A scrolling text view that auto-scrolls when the text is wider than its container.
// Used in compact and expanded views for long song titles.
//
// Approach: Duplicate the text side by side with a gap. A linear animation scrolls
// the entire block left. When the first copy scrolls out, the second is at the start
// position and repeatForever resets seamlessly — classic marquee pattern.

import SwiftUI

struct MarqueeText: View {

    let text: String
    let font: Font
    let color: Color
    let speed: Double              // points per second
    let delayBeforeScroll: Double  // seconds to pause before scrolling starts

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating: Bool = false

    init(
        _ text: String,
        font: Font = .system(size: 12, weight: .medium),
        color: Color = .white,
        speed: Double = 30,
        delayBeforeScroll: Double = 2.0
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.speed = speed
        self.delayBeforeScroll = delayBeforeScroll
    }

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width

            ZStack(alignment: .leading) {
                // Invisible text to measure the natural width.
                Text(text)
                    .font(font)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.onAppear {
                                textWidth = textGeo.size.width
                                containerWidth = geo.size.width
                            }
                        }
                    )
                    .hidden()

                // Visible scrolling text
                if needsScroll {
                    // Two copies of the text separated by spaces for seamless loop.
                    Text(text + "          " + text)
                        .font(font)
                        .foregroundColor(color)
                        .fixedSize()
                        .offset(x: offset)
                        .onAppear { startScrolling() }
                        .onChange(of: text) { _, _ in
                            resetAndRestart()
                        }
                } else {
                    // Text fits — no scrolling needed, just render normally.
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                }
            }
            .clipped()  // Clip overflow outside the container bounds.
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
            }
        }
    }

    // MARK: - Scroll Animation

    private func startScrolling() {
        offset = 0
        animating = false

        // Pause at the start position so the user can read the beginning.
        DispatchQueue.main.asyncAfter(deadline: .now() + delayBeforeScroll) {
            guard textWidth > containerWidth else { return }

            // scrollDistance = width of one text copy + gap (~60pt for 10 spaces)
            let scrollDistance = textWidth + 60
            let duration = scrollDistance / speed

            withAnimation(
                .linear(duration: duration)
                .repeatForever(autoreverses: false)
            ) {
                offset = -scrollDistance
            }
            animating = true
        }
    }

    private func resetAndRestart() {
        offset = 0
        animating = false
        // Re-measure will happen via onAppear on next layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startScrolling()
        }
    }
}
