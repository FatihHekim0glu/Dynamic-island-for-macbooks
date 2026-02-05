// MacIslandApp.swift
// MacIsland
//
// App entry point. We use the SwiftUI @main but delegate all real work
// to AppDelegate, since we need full AppKit control over window creation.
//
// WHY not use WindowGroup?
// WindowGroup creates a standard NSWindow with title bar, which is the opposite
// of what we want. Our AppDelegate manually creates a borderless NSPanel.
// The SwiftUI App struct here is just the entry point + delegate wiring.

import SwiftUI

@main
struct MacIslandApp: App {

    // Wire in our AppDelegate for full AppKit lifecycle control.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We need at least one Scene declaration for @main to compile,
        // but we use Settings (which creates no window unless opened)
        // to avoid spawning an unwanted default window.
        Settings {
            EmptyView()
        }
    }
}
