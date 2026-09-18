import AppKit

/// Covers the corner of every display where notification banners appear.
///
/// There is no supported way to suppress another app's banners, so PresentSafe
/// does the next best thing: it parks an opaque window over the region they
/// occupy. Because the window is part of the screen, whatever is capturing that
/// screen captures the cover too — which is exactly the point.
///
/// Best-effort by nature. The banner region is not a documented rectangle, and
/// a viewer sharing a single *window* rather than a whole screen will not see
/// the cover at all. Both limits are stated plainly in the README.
@MainActor
final class NotificationZoneGuard: PresentGuard {
    let id = "notificationZone"
    let title = "Cover the notification corner"
    let summary = "Blocks the region where banners pop up, on every display."
    let symbolName = "bell.slash"
    let isEnabledByDefault = true

    /// Roughly the footprint of a banner stack, in points.
    private static let zoneWidth: CGFloat = 420
    private static let zoneHeight: CGFloat = 640

    private var covers: [NSWindow] = []
    private var screenObserver: (any NSObjectProtocol)?

    func activate() async throws {
        rebuildCovers()

        // The whole point of this app is the moment you connect to a projector,
        // and that moment fires this notification. Without it, a display added
        // after Present Mode is switched on stays completely uncovered — the one
        // screen everybody is actually looking at.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.rebuildCovers()
            }
        }
    }

    func deactivate() async {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeCovers()
    }

    private func rebuildCovers() {
        removeCovers()
        covers = NSScreen.screens.map { screen in
            makeCover(over: Self.bannerZone(on: screen))
        }
        for cover in covers {
            cover.orderFrontRegardless()
        }
    }

    private func removeCovers() {
        for cover in covers {
            cover.orderOut(nil)
        }
        covers = []
    }

    /// The top-right region of a screen, inset from the visible frame so the
    /// cover sits below the menu bar rather than fighting with it.
    static func bannerZone(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(zoneWidth, visible.width)
        let height = min(zoneHeight, visible.height)
        return NSRect(
            x: visible.maxX - width,
            y: visible.maxY - height,
            width: width,
            height: height
        )
    }

    private func makeCover(over frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        // Purely visual: clicks pass straight through, so the cover can never
        // strand the user behind a rectangle they cannot dismiss.
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(frame, display: false)
        return window
    }
}
