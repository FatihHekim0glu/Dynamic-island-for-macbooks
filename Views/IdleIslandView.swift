// IdleIslandView.swift
// MacIsland
//
// The "Black Hole" — a minimal black capsule that visually merges with the
// hardware notch. This is what the user sees 90% of the time.
// Designed to be indistinguishable from the physical bezel.

import SwiftUI

struct IdleIslandView: View {

    var body: some View {
        Capsule()
            .fill(.black)
            .frame(
                width: IslandDimensions.idle.width,
                height: IslandDimensions.idle.height
            )
            // Subtle inner shadow to give depth, matching the notch's recessed look.
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.05),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}
