import AppKit
import SwiftUI

/// Covers a sensitive app that the user brought back while Present Mode is on.
///
/// The first version simply hid the app again the instant it appeared. That
/// worked, and it felt broken: an app that bounces off the screen with no
/// explanation reads as a crash, and the sudden switch of frontmost app is
/// disorienting in the middle of a presentation.
///
/// Covering instead keeps everything still. The app stays where the user put
/// it, the screen says plainly what happened, and there is a way out. The app
/// is only put away once the user moves on of their own accord.
///
/// Unlike the confirmation HUD, this one is *not* excluded from screen capture.
/// Hiding it from the shared screen would defeat the entire point: it is the
/// thing standing between the audience and a private conversation.
@MainActor
final class BlockedAppOverlay {
    static let shared = BlockedAppOverlay()

    private var windows: [NSWindow] = []
    private(set) var blockedApp: NSRunningApplication?

    var isShowing: Bool { !windows.isEmpty }

    func show(for app: NSRunningApplication) {
        // Already covering this app: leave the existing windows alone rather
        // than rebuilding them under the user.
        if blockedApp == app, isShowing { return }

        dismiss()
        blockedApp = app

        let name = app.localizedName ?? app.bundleIdentifier ?? "This app"
        let icon = app.icon

        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(
                rootView: BlockedAppView(appName: name, icon: icon)
            )
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)
            return window
        }

        for window in windows {
            window.orderFrontRegardless()
        }
        // Take key status so the button is usable. Without this the overlay
        // sits inert on top of an app that still owns the keyboard.
        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        blockedApp = nil
    }
}

/// A borderless window will not become key unless it says it can, and without
/// key status the button inside it cannot be clicked.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct BlockedAppView: View {
    let appName: String
    let icon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 18)
            }

            Text("\(appName) is hidden while you present")
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Present Mode is on, so this app stays out of the way.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Button {
                PresentModeController.shared.toggle()
            } label: {
                Text("Turn Off Present Mode")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 22)

            Spacer()

            Text("Switch to another app and this one will be put away.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
