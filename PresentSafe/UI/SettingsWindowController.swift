import AppKit
import OSLog
import SwiftUI

/// Owns the Settings window.
///
/// SwiftUI's `Settings` scene is built for apps that have a menu bar, where it
/// supplies the standard "Settings…" item and ⌘,. PresentSafe sets
/// `LSUIElement`, so it has no menu bar and gains none of that — while still
/// inheriting the scene's real drawback: `openSettings()` shows the window
/// without activating the app, so on an accessory app it opens *behind*
/// whatever the user is looking at and seems not to have opened at all.
///
/// Owning the window directly costs nothing here and makes bringing it forward
/// something this app decides rather than something it hopes for.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let logger = Logger(subsystem: "dev.justghali.PresentSafe", category: "Settings")

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // Order matters. Activating first gives the app the focus it needs to
        // own a key window; `orderFrontRegardless` then raises the window even
        // if macOS declined the activation request, which it may do when
        // another app currently owns user attention.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        logger.info("Settings shown (visible: \(window.isVisible), key: \(window.isKeyWindow), title: \(window.title, privacy: .public))")
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView()
                .environmentObject(PresentModeController.shared)
                .environmentObject(Preferences.shared)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "PresentSafe Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Closing Settings must not destroy the window, or the next open would
        // hand back a deallocated one.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
