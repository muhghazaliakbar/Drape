import AppKit
import SwiftUI

/// Covers the windows of a sensitive app the user brought back while Present
/// Mode is on.
///
/// Hiding the app on sight worked and felt broken: an app that vanishes with no
/// explanation reads as a crash, and the abrupt change of frontmost app is
/// disorienting mid-presentation. A cover holds everything still, says what
/// happened, and offers a way through.
///
/// Sized to each window rather than the whole screen. A full-screen blackout
/// hides far more than the thing being protected, including the slides the user
/// is in the middle of presenting.
///
/// Unlike the confirmation HUD, these are deliberately **not** excluded from
/// screen capture. Hiding them from the shared screen would defeat the point:
/// they are what stands between the audience and a private conversation.
@MainActor
final class BlockedAppOverlay {
    static let shared = BlockedAppOverlay()

    private static let followInterval = Duration.milliseconds(250)

    private var covers: [NSWindow] = []
    private var coveredRects: [NSRect] = []
    private var followTask: Task<Void, Never>?

    private(set) var blockedApp: NSRunningApplication?

    var isShowing: Bool { !covers.isEmpty }

    /// Covers every window the app has on screen.
    ///
    /// Returns `false` when there is nothing to cover — an app just launched,
    /// or one whose windows are all closed — leaving the caller to fall back to
    /// the toast on its own.
    @discardableResult
    func cover(_ app: NSRunningApplication) -> Bool {
        let rects = WindowGeometry.windows(ofProcess: app.processIdentifier)
        guard !rects.isEmpty else { return false }

        if blockedApp == app, coveredRects == rects { return true }

        blockedApp = app
        rebuild(over: rects, for: app)
        startFollowing(app)

        // Key status, or the buttons are inert under an app that still owns the
        // keyboard.
        NSApp.activate()
        covers.first?.makeKeyAndOrderFront(nil)
        return true
    }

    func dismiss() {
        followTask?.cancel()
        followTask = nil
        for cover in covers { cover.orderOut(nil) }
        covers = []
        coveredRects = []
        blockedApp = nil
    }

    // MARK: - Following

    /// Windows move, resize and open while covered. Without this the cover
    /// drifts off its window and quietly exposes what it was put there to hide.
    private func startFollowing(_ app: NSRunningApplication) {
        followTask?.cancel()
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.followInterval)
                guard !Task.isCancelled, let self, self.blockedApp == app else { return }

                let rects = await Task.detached(priority: .userInitiated) {
                    WindowGeometry.windows(ofProcess: app.processIdentifier)
                }.value

                guard !Task.isCancelled, self.blockedApp == app else { return }
                guard rects != self.coveredRects else { continue }

                if rects.isEmpty {
                    self.dismiss()
                } else {
                    self.rebuild(over: rects, for: app)
                }
            }
        }
    }

    private func rebuild(over rects: [NSRect], for app: NSRunningApplication) {
        for cover in covers { cover.orderOut(nil) }
        covers = []
        coveredRects = rects

        let name = app.localizedName ?? app.bundleIdentifier ?? "This app"
        let bundleID = app.bundleIdentifier
        // Only the biggest window carries the explanation and the buttons.
        // Repeating them on every window of a multi-window app is clutter.
        let primary = rects.max { $0.width * $0.height < $1.width * $1.height }

        covers = rects.map { rect in
            // `.titled` rather than `.borderless`, with the title bar hidden.
            //
            // A borderless window has square corners, so the cover poked out
            // past the rounded corners of the window beneath it. A titled
            // window is given the system's own corner radius, which means the
            // shape matches whatever macOS is drawing this year instead of a
            // number hardcoded here that goes stale at the next release.
            let window = NSWindow(
                contentRect: rect,
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.remove(.resizable)
            window.isMovable = false
            window.isMovableByWindowBackground = false
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            // The window it covers already casts a shadow; a second one would
            // darken the edge twice over.
            window.hasShadow = false
            window.contentView = NSHostingView(
                rootView: BlockedWindowCover(
                    appName: name,
                    icon: app.icon,
                    showsControls: rect == primary,
                    onSnooze: { [weak self] in
                        if let bundleID { SnoozeRegistry.shared.snooze(bundleID) }
                        self?.dismiss()
                    },
                    onTurnOff: { PresentModeController.shared.toggle() }
                )
            )
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            // Just below the menu bar, not at the top of the world.
            //
            // A cover only has to sit above the windows of the app it is
            // covering, and those are ordinary windows. Parking it at the
            // maximum level put it above Drape's own menu bar panel, so
            // the cover hid the controls for turning it off — a block the user
            // could see but not answer.
            //
            // Below `.mainMenu` also keeps it under the system menu bar, the
            // status bar and every pop-up menu, which is where it belongs: this
            // app covers applications, not macOS itself.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setFrame(rect, display: false)
            return window
        }

        for cover in covers { cover.orderFrontRegardless() }
    }
}

private struct BlockedWindowCover: View {
    let appName: String
    let icon: NSImage?
    let showsControls: Bool
    let onSnooze: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        GeometryReader { proxy in
            // A cover is only as big as the window it sits on, and some of those
            // are small. Below these sizes the explanation is dropped rather
            // than crushed.
            let compact = proxy.size.height < 260 || proxy.size.width < 420

            VStack(spacing: compact ? 10 : 16) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: compact ? 40 : 60, height: compact ? 40 : 60)
                }

                Text("\(appName) is blocked")
                    .font(.system(size: compact ? 15 : 20, weight: .semibold))
                    .multilineTextAlignment(.center)

                if !compact {
                    Text("Drape is hiding it while you present.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                if showsControls {
                    HStack(spacing: 10) {
                        Button("Snooze for 3 minutes", action: onSnooze)
                        Button("Turn Off Present Mode", action: onTurnOff)
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(compact ? .small : .regular)
                    .padding(.top, compact ? 0 : 4)
                }
            }
            .padding(compact ? 12 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
