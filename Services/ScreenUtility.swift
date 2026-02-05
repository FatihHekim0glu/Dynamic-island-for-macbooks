// ScreenUtility.swift
// MacIsland
//
// Detects the physical notch geometry on Apple Silicon MacBooks.
// Uses NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea (macOS 12+) as the
// primary detection method — these APIs return the screen regions flanking the
// notch, so the notch rectangle is the gap between them.
//
// Fallback: NSScreen.safeAreaInsets.top > threshold with hardcoded defaults
// tuned for MacBook Air 15" M2 (37pt height, ~160pt width, 10pt corner radius).

import AppKit

// MARK: - NotchGeometry

struct NotchGeometry {
    /// The notch rectangle in screen coordinates (origin = bottom-left of screen).
    let rect: CGRect
    /// The notch height in points (0 on non-notch displays).
    let notchHeight: CGFloat
    /// The width of the physical notch area.
    let notchWidth: CGFloat
    /// The origin point (bottom-left corner) for the island window in screen coordinates.
    let windowOrigin: CGPoint
    /// Corner radius for the notch's bottom corners (cosmetic reference).
    let cornerRadius: CGFloat
    /// Whether this screen actually has a hardware notch.
    let hasNotch: Bool
}

// MARK: - ScreenUtility

enum ScreenUtility {

    // MARK: - Fallback Constants (MacBook Air 15" M2)

    /// Default notch height if auxiliaryTopArea API is unavailable.
    private static let fallbackNotchHeight: CGFloat = 37

    /// Default notch width for idle-state sizing.
    private static let fallbackNotchWidth: CGFloat = 160

    /// Bottom corner radius of the notch cutout.
    private static let fallbackCornerRadius: CGFloat = 10

    /// Minimum safeAreaInsets.top that indicates a notch is present.
    /// Non-notch displays report 0; notch displays report ~32–44pt.
    private static let notchThreshold: CGFloat = 20

    // MARK: - Public API

    /// Detect notch geometry for the main screen (the one with the menu bar).
    static func detectNotch() -> NotchGeometry {
        guard let screen = NSScreen.main else {
            return .init(rect: .zero, notchHeight: 0, notchWidth: 0,
                         windowOrigin: .zero, cornerRadius: 0, hasNotch: false)
        }

        let screenFrame = screen.frame
        let safeAreaTop = screen.safeAreaInsets.top

        // ── Primary: auxiliaryTopLeftArea / auxiliaryTopRightArea ──
        // These rects describe the usable screen area on each side of the notch.
        // The gap between topLeftRect.maxX and topRightRect.minX IS the notch.
        if let topLeftRect = screen.auxiliaryTopLeftArea,
           let topRightRect = screen.auxiliaryTopRightArea {

            let notchLeftEdge = topLeftRect.maxX
            let notchRightEdge = topRightRect.minX
            let notchWidth = notchRightEdge - notchLeftEdge
            let notchHeight = safeAreaTop  // menu bar height == notch height on notch Macs

            // Build the notch rect in screen coordinates.
            // macOS: origin is bottom-left, Y increases upward.
            // The notch sits at the very top of the screen.
            let notchY = screenFrame.origin.y + screenFrame.height - notchHeight
            let notchRect = CGRect(x: notchLeftEdge, y: notchY,
                                   width: notchWidth, height: notchHeight)

            // Default island window origin: centered on the notch, pinned to top.
            let defaultIslandWidth: CGFloat = IslandDimensions.idle.width
            let originX = notchLeftEdge + (notchWidth - defaultIslandWidth) / 2
            let originY = notchY

            return NotchGeometry(
                rect: notchRect,
                notchHeight: notchHeight,
                notchWidth: notchWidth,
                windowOrigin: CGPoint(x: originX, y: originY),
                cornerRadius: fallbackCornerRadius,
                hasNotch: true
            )
        }

        // ── Fallback: safeAreaInsets threshold + hardcoded dimensions ──
        let hasNotch = safeAreaTop > notchThreshold

        if hasNotch {
            let notchHeight = safeAreaTop
            let notchWidth = fallbackNotchWidth

            // Center the notch on screen (best guess without auxiliary API).
            let notchX = screenFrame.midX - (notchWidth / 2)
            let notchY = screenFrame.origin.y + screenFrame.height - notchHeight
            let notchRect = CGRect(x: notchX, y: notchY,
                                   width: notchWidth, height: notchHeight)

            let defaultIslandWidth: CGFloat = IslandDimensions.idle.width
            let originX = screenFrame.midX - (defaultIslandWidth / 2)
            let originY = notchY

            return NotchGeometry(
                rect: notchRect,
                notchHeight: notchHeight,
                notchWidth: notchWidth,
                windowOrigin: CGPoint(x: originX, y: originY),
                cornerRadius: fallbackCornerRadius,
                hasNotch: true
            )
        }

        // ── No notch (external display / clamshell) ──
        return NotchGeometry(
            rect: .zero,
            notchHeight: 0,
            notchWidth: 0,
            windowOrigin: CGPoint(
                x: screenFrame.midX - (IslandDimensions.idle.width / 2),
                y: screenFrame.origin.y + screenFrame.height - IslandDimensions.idle.height
            ),
            cornerRadius: 0,
            hasNotch: false
        )
    }

    /// Recalculate the window origin for a given island width/height, keeping it centered on screen.
    /// Uses the notch center (from auxiliary API) if available, otherwise falls back to screen center.
    static func centeredOrigin(forIslandWidth width: CGFloat, height: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame

        // If we can detect the notch precisely, center on it.
        if let topLeftRect = screen.auxiliaryTopLeftArea,
           let topRightRect = screen.auxiliaryTopRightArea {
            let notchLeftEdge = topLeftRect.maxX
            let notchRightEdge = topRightRect.minX
            let notchCenterX = (notchLeftEdge + notchRightEdge) / 2
            let x = notchCenterX - (width / 2)
            let y = screenFrame.origin.y + screenFrame.height - height
            return CGPoint(x: x, y: y)
        }

        // Fallback: center on screen.
        let x = screenFrame.midX - (width / 2)
        let y = screenFrame.origin.y + screenFrame.height - height
        return CGPoint(x: x, y: y)
    }
}
