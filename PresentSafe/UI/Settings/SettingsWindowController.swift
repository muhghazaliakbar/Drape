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
/// Owning the window also buys the authentic look: `toolbarStyle = .preference`
/// with a selectable `NSToolbar` is what gives macOS settings windows their
/// centred icon-and-label switcher, and there is no SwiftUI equivalent outside
/// the `Settings` scene.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var currentPane: SettingsPane = .protections
    private let logger = Logger(subsystem: "dev.justghali.PresentSafe", category: "Settings")

    private static let lastPaneKey = "lastSettingsPane"

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

        logger.info("Settings shown (visible: \(window.isVisible), key: \(window.isKeyWindow), pane: \(self.currentPane.rawValue, privacy: .public))")
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let restored = UserDefaults.standard.string(forKey: Self.lastPaneKey)
        currentPane = restored.flatMap(SettingsPane.init(rawValue:)) ?? .protections

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: currentPane.idealSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // Closing Settings must not destroy the window, or the next open would
        // hand back a deallocated one.
        window.isReleasedWhenClosed = false
        window.title = currentPane.title
        window.toolbarStyle = .preference

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = currentPane.toolbarItemIdentifier
        window.toolbar = toolbar

        window.contentViewController = hostingController(for: currentPane)
        window.center()
        return window
    }

    private func hostingController(for pane: SettingsPane) -> NSHostingController<some View> {
        let controller = NSHostingController(
            rootView: pane.content
                .environmentObject(PresentModeController.shared)
                .environmentObject(Preferences.shared)
                .frame(width: pane.idealSize.width, height: pane.idealSize.height)
        )
        controller.view.frame.size = pane.idealSize
        return controller
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarItemIdentifier == sender.itemIdentifier }),
              pane != currentPane
        else { return }
        transition(to: pane)
    }

    private func transition(to pane: SettingsPane) {
        guard let window else { return }
        currentPane = pane
        UserDefaults.standard.set(pane.rawValue, forKey: Self.lastPaneKey)

        window.title = pane.title
        window.toolbar?.selectedItemIdentifier = pane.toolbarItemIdentifier
        window.contentViewController = hostingController(for: pane)

        // Grow or shrink from the title bar downwards. Resizing around the
        // window's origin instead would make the title bar jump, which reads as
        // the window moving rather than the content changing.
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: pane.idealSize))
        let target = NSRect(
            x: window.frame.minX,
            y: window.frame.maxY - frame.height,
            width: frame.width,
            height: frame.height
        )
        window.setFrame(target, display: true, animate: true)
    }
}

// MARK: - NSToolbarDelegate

extension SettingsWindowController: NSToolbarDelegate {
    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    /// Making the items selectable is what turns the toolbar into a pane
    /// switcher, complete with the highlight macOS draws behind the active one.
    nonisolated func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            guard let pane = SettingsPane.allCases.first(where: { $0.toolbarItemIdentifier == itemIdentifier })
            else { return nil }

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = pane.title
            item.paletteLabel = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            item.target = self
            item.action = #selector(selectPane(_:))
            item.isNavigational = false
            return item
        }
    }
}
