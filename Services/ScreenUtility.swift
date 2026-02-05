// ScreenUtility.swift
// MacIsland
//
// Detects the physical notch geometry on Apple Silicon MacBooks.
// Uses NSScreen.safeAreaInsets (macOS 12+) to determine the notch height,
// then computes the center-top position and sizing for the island window.

import AppKit

struct NotchGeometry {
    /// The notch height in points (0 on non-notch displays).
    let notchHeight: CGFloat
    /// The origin point (bottom-left corner) for the island window in screen coordinates.
    let windowOrigin: CGPoint
    /// The width of the physical notch area.
    let notchWidth: CGFloat
    /// Whether this screen actually has a hardware notch.
    let hasNotch: Bool
}

enum ScreenUtility {

    // MARK: - Constants

    /// The known hardware notch width on 14"/16" MacBook Pro (in points).
    /// Apple doesn't expose this directly, but it's ~180pt on 14" and ~190pt on 16".
    /// We use a conservative baseline; the island can grow beyond this.
    private static let estimatedNotchWidth: CGFloat = 180

    /// Minimum safe area inset that indicates a notch is present.
    /// Non-notch displays report 0; notch displays report ~32-38pt.
    private static let notchThreshold: CGFloat = 20

    // MARK: - Public API

    /// Detect notch geometry for the main screen (or the screen containing the menu bar).
    static func detectNotch() -> NotchGeometry {
        guard let screen = NSScreen.main else {
            return .init(notchHeight: 0, windowOrigin: .zero, notchWidth: 0, hasNotch: false)
        }

        let safeAreaTop = screen.safeAreaInsets.top
        let hasNotch = safeAreaTop > notchThreshold

        // The notch height is the safe area inset minus the standard menu bar height.
        // On notch displays, safeAreaInsets.top ~ 38pt which includes the menu bar
        // integrated into the notch region. We use the full inset as our reference.
        let notchHeight = hasNotch ? safeAreaTop : 0

        // Screen geometry: NSScreen.frame is in global screen coordinates.
        // The "main" screen has its origin at (0, 0) bottom-left.
        let screenFrame = screen.frame

        // The notch width — use estimated hardware width as baseline.
        let notchWidth = hasNotch ? estimatedNotchWidth : 0

        // Window origin: center horizontally on screen, pin to the very top.
        // We use a default island width for initial positioning (will be updated dynamically).
        let defaultIslandWidth: CGFloat = 200
        let originX = screenFrame.midX - (defaultIslandWidth / 2)

        // In macOS coordinate system, Y increases upward.
        // To pin to the top of the screen, we compute:
        //   top of screen = screenFrame.origin.y + screenFrame.height
        // Then subtract the island height (which starts at notchHeight).
        let originY = screenFrame.origin.y + screenFrame.height - notchHeight

        return NotchGeometry(
            notchHeight: notchHeight,
            windowOrigin: CGPoint(x: originX, y: originY),
            notchWidth: notchWidth,
            hasNotch: hasNotch
        )
    }

    /// Recalculate the window origin for a given island width, keeping it centered on screen.
    static func centeredOrigin(forIslandWidth width: CGFloat, height: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        let x = screenFrame.midX - (width / 2)
        let y = screenFrame.origin.y + screenFrame.height - height
        return CGPoint(x: x, y: y)
    }
}
