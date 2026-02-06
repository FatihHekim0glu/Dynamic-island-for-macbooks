// IslandWindowController.swift
// MacIsland
//
// THE critical piece — configures an NSPanel to be borderless, transparent,
// floating above all windows, and click-through in transparent regions.
//
// WHY NSPanel instead of NSWindow?
// - NSPanel supports .nonactivatingPanel: it won't steal focus from the user's
//   active app when they hover/click the island. This is essential for a utility overlay.
// - NSPanel also supports utility-window behavior (auto-hide on deactivate, etc.)
//   although we override most of that since we want it always visible.

import AppKit
import SwiftUI
import Combine

final class IslandWindowController: NSWindowController {

    private let viewModel: IslandViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel

        let geometry = ScreenUtility.detectNotch()
        let dims = viewModel.dimensions

        // --- NSPanel Configuration ---
        // .borderless:         No title bar, no resize controls — we draw everything ourselves.
        // .nonactivatingPanel: Clicking the panel does NOT activate (bring to front) our app,
        //                      so the user's foreground app stays focused.
        // .fullSizeContentView: Our SwiftUI content extends to the panel edges with no insets.
        let panel = NSPanel(
            contentRect: NSRect(
                x: geometry.windowOrigin.x,
                y: geometry.windowOrigin.y,
                width: dims.width,
                height: dims.height
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // --- Transparency & Rendering ---
        // isOpaque = false:              Tells the compositor this window has transparent pixels.
        // backgroundColor = .clear:      No system-drawn background — we render our own capsule.
        // hasShadow = false:             Shadows on a floating capsule look wrong; we may add
        //                                a custom SwiftUI shadow later for depth.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        // --- Z-Order (Window Level) ---
        // .statusBar puts us above most windows (including full-screen edges)
        // but below system alerts and the actual menu bar items.
        // Alternative: .floating (lower) or .screenSaver (higher, but blocks everything).
        panel.level = .statusBar

        // --- Behavior Flags ---
        // .canJoinAllSpaces:   Visible on every Mission Control space. The island should
        //                      never disappear when switching desktops.
        // .fullScreenAuxiliary: Remains visible even when another app goes full-screen.
        //                       Without this, macOS hides non-fullscreen windows.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // --- Click-Through in Transparent Areas ---
        // ignoresMouseEvents = false:  We DO want hover/click on the capsule itself.
        // The magic is in the panel's `isOpaque = false` + `backgroundColor = .clear`:
        //   macOS automatically makes fully-transparent pixels click-through when
        //   the window is non-opaque. So only the black capsule region receives events.
        panel.ignoresMouseEvents = false

        // Keep the panel visible when our app is not frontmost.
        panel.hidesOnDeactivate = false

        // Prevent the window from becoming key (taking keyboard focus) unless explicitly needed.
        // This avoids stealing keyboard input from the user's active application.
        panel.becomesKeyOnlyIfNeeded = true

        super.init(window: panel)

        setupHostingView()
        bindWindowSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IslandWindowController does not support Interface Builder.")
    }

    // MARK: - SwiftUI Hosting

    /// Embed the SwiftUI IslandView inside the panel using NSHostingView.
    private func setupHostingView() {
        let islandView = IslandView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: islandView)

        // Critical: the hosting view must not draw its own opaque background,
        // otherwise the transparency trick breaks.
        hostingView.layer?.isOpaque = false

        window?.contentView = hostingView
    }

    // MARK: - Dynamic Window Resizing

    /// Observe state changes and animate the window frame to match the island's current dimensions.
    /// We resize the NSWindow in sync with the SwiftUI animation so the hit-testing region
    /// matches the visual capsule at all times.
    private func bindWindowSize() {
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.resizeWindow(for: state)
            }
            .store(in: &cancellables)
    }

    private func resizeWindow(for state: IslandState) {
        guard let panel = window else { return }

        let dims: IslandDimensions
        switch state {
        case .idle:     dims = .idle
        case .compact:  dims = .compact
        case .expanded: dims = .expanded
        }

        let origin = ScreenUtility.centeredOrigin(forIslandWidth: dims.width, height: dims.height)
        let newFrame = NSRect(x: origin.x, y: origin.y, width: dims.width, height: dims.height)

        // Match the SwiftUI interpolatingSpring timing more closely.
        // Spring with stiffness 200, damping 18 settles in ~0.35s.
        // Using a custom cubic bezier that mimics the spring's ease-out overshoot.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2, 0.9, 0.3, 1.0
            )
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - Show

    func showIsland() {
        window?.orderFrontRegardless()
    }
}
