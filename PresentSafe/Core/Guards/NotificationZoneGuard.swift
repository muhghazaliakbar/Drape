import AppKit
import SwiftUI

/// Hides notification banners while Present Mode is on.
///
/// macOS offers no supported way to suppress another app's banners, so
/// PresentSafe covers them instead: a panel of its own, parked over the corner
/// they occupy. Because the panel is part of the screen, whatever is capturing
/// that screen captures the panel too — which is the point.
///
/// The first version left that panel up for the whole session. It worked, and
/// it was miserable: a dead slab over a chunk of your display for the length of
/// a presentation, on the chance that something might arrive. This version
/// watches for banners and covers only while one is actually up.
///
/// Best-effort by nature, and worth stating plainly:
/// - The banner rectangle is not published. macOS exposes a full-screen host
///   window for Notification Center, not the banner's own frame, so the covered
///   region is a well-placed estimate rather than a measurement.
/// - Someone sharing a single *window* rather than a whole screen never sees
///   the cover, since it is a window of its own.
@MainActor
final class NotificationZoneGuard: PresentGuard {
    let id = "notificationZone"
    let title = "Cover the notification corner"
    let summary = "Hides banners as they appear, on every display."
    let symbolName = "bell.slash"
    let isEnabledByDefault = true

    /// Banners are about 344pt wide; the cover is a little wider to allow for
    /// shadows and the odd oversized banner.
    private static let coverWidth: CGFloat = 372
    private static let edgeInset: CGFloat = 10
    private static let pollInterval = Duration.milliseconds(250)

    private var covers: [NSWindow] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var watchTask: Task<Void, Never>?
    private var isCovering = false

    func activate() async throws {
        rebuildCovers()
        startWatchingForBanners()

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
        watchTask?.cancel()
        watchTask = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeCovers()
    }

    // MARK: - Detection

    /// True while macOS has a Notification Center window on screen.
    ///
    /// Verified rather than assumed: the window is absent with no banner up and
    /// appears for exactly as long as one is displayed. Owner names and bounds
    /// come back from `CGWindowListCopyWindowInfo` without Screen Recording
    /// permission — only window *titles* are withheld — which keeps this guard
    /// inside the app's no-permissions rule.
    nonisolated private static func bannerIsOnScreen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        return windows.contains { window in
            (window[kCGWindowOwnerName as String] as? String) == "Notification Center"
        }
    }

    private func startWatchingForBanners() {
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                // Measured at 0.5ms a call. Cheap, but this app runs during
                // presentations, so it stays off the main thread regardless.
                let showing = await Task.detached(priority: .utility) {
                    NotificationZoneGuard.bannerIsOnScreen()
                }.value

                guard !Task.isCancelled, let self else { return }
                self.setCovering(showing)

                try? await Task.sleep(for: NotificationZoneGuard.pollInterval)
            }
        }
    }

    private func setCovering(_ covering: Bool) {
        guard covering != isCovering else { return }
        isCovering = covering

        for cover in covers {
            if covering {
                // Appear instantly. Fading in would mean the banner is legible
                // through a half-transparent cover for a few frames, which is
                // the one thing this guard exists to prevent.
                cover.alphaValue = 1
                cover.orderFrontRegardless()
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    cover.animator().alphaValue = 0
                } completionHandler: {
                    cover.orderOut(nil)
                }
            }
        }
    }

    // MARK: - Covers

    private func rebuildCovers() {
        removeCovers()
        covers = NSScreen.screens.map { makeCover(over: Self.coverFrame(on: $0)) }
        if isCovering {
            for cover in covers { cover.orderFrontRegardless() }
        }
    }

    private func removeCovers() {
        for cover in covers { cover.orderOut(nil) }
        covers = []
        isCovering = false
    }

    /// The full right-hand column of a screen, inside the visible frame so the
    /// cover stays clear of the menu bar and the Dock.
    ///
    /// Full height rather than a banner-sized card, because a stack grows
    /// downwards and there is no way to learn how tall it got: macOS publishes
    /// only a full-screen host window for Notification Center, never the
    /// banners' own frames. A fixed height would be a guess that leaks the
    /// moment three notifications arrive at once. Covering the whole column is
    /// the only version that cannot be wrong — and it is affordable now that
    /// the cover appears only while a banner is actually up.
    static func coverFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(coverWidth, visible.width)
        return NSRect(
            x: visible.maxX - width - edgeInset,
            y: visible.minY + edgeInset,
            width: width,
            height: visible.height - (edgeInset * 2)
        )
    }

    private func makeCover(over frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: NotificationCoverView())
        // Clear and non-opaque so the panel's own rounded corners survive; the
        // panel itself is fully opaque, because a blurred material would leave
        // a banner's shape and colour readable through it.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.alphaValue = 0
        // Purely visual: clicks pass straight through, so the cover can never
        // strand the user behind a rectangle they cannot dismiss.
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(frame, display: false)
        return window
    }
}

/// What the audience sees instead of the notification.
///
/// A deliberate panel rather than a black rectangle: an unexplained void reads
/// as a broken screen, while this reads as something working.
private struct NotificationCoverView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                HStack(spacing: 7) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 13))
                    Text("Notification hidden")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.top, 22)
            }
    }
}
