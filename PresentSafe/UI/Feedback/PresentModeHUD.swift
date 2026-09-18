import AppKit
import SwiftUI

/// The on-screen confirmation shown when Present Mode is switched.
///
/// A menu bar icon changing shape is not enough feedback for an action taken
/// seconds before an audience sees your screen. This is the reassurance that
/// the shortcut landed: a brief glow around every display, and a card naming
/// the new state.
///
/// The windows ask to be excluded from screen capture. The confirmation is for
/// the person at the keyboard; the room does not need to watch a green flash.
/// Exclusion is best-effort — a capturer can build its own content filter — but
/// the worst case is cosmetic, not a leak.
@MainActor
final class PresentModeHUD {
    static let shared = PresentModeHUD()

    enum State {
        case activated(protections: Int)
        case deactivated

        var title: String {
            switch self {
            case .activated: "Present Mode on"
            case .deactivated: "Present Mode off"
            }
        }

        var subtitle: String {
            switch self {
            case .activated(let count):
                count == 1 ? "1 protection active" : "\(count) protections active"
            case .deactivated:
                "Everything restored"
            }
        }

        var symbolName: String {
            switch self {
            case .activated: "checkmark.circle.fill"
            case .deactivated: "eye.circle.fill"
            }
        }

        /// Green for protected. Amber for the moment protection ends — if the
        /// shortcut is hit by accident mid-presentation, that is precisely when
        /// the user needs to notice.
        var tint: Color {
            switch self {
            case .activated: .green
            case .deactivated: .orange
            }
        }
    }

    private var glowWindows: [NSWindow] = []
    private var toastWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?

    private static let holdDuration = Duration.milliseconds(1700)
    private static let fadeIn = 0.16
    private static let fadeOut = 0.34

    func show(_ state: State) {
        guard Preferences.shared.showsOnScreenConfirmation else { return }

        // A second toggle while the first is still fading must not leave the
        // old card on screen, or race the new one off it.
        dismissTask?.cancel()
        teardown()

        glowWindows = NSScreen.screens.map { makeGlowWindow(on: $0, tint: state.tint) }
        toastWindow = makeToastWindow(for: state)

        for window in glowWindows + [toastWindow].compactMap(\.self) {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        animateAlpha(to: 1, duration: Self.fadeIn)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        let windows = glowWindows + [toastWindow].compactMap(\.self)
        animateAlpha(to: 0, duration: Self.fadeOut) {
            for window in windows { window.orderOut(nil) }
        }
        glowWindows = []
        toastWindow = nil
    }

    private func teardown() {
        for window in glowWindows { window.orderOut(nil) }
        toastWindow?.orderOut(nil)
        glowWindows = []
        toastWindow = nil
    }

    private func animateAlpha(to value: CGFloat, duration: Double, completion: (() -> Void)? = nil) {
        let windows = glowWindows + [toastWindow].compactMap(\.self)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            for window in windows { window.animator().alphaValue = value }
        } completionHandler: {
            completion?()
        }
    }

    // MARK: - Windows

    private func makeGlowWindow(on screen: NSScreen, tint: Color) -> NSWindow {
        let window = makeOverlayWindow(frame: screen.frame)
        window.contentView = NSHostingView(rootView: EdgeGlowView(tint: tint))
        return window
    }

    private func makeToastWindow(for state: State) -> NSWindow {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 290, height: 62)
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 10,
            width: size.width,
            height: size.height
        )

        let window = makeOverlayWindow(frame: frame)
        window.contentView = NSHostingView(rootView: ToastView(state: state))
        return window
    }

    private func makeOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Keep the confirmation off the shared screen. See the type's note.
        window.sharingType = .none
        window.setFrame(frame, display: false)
        return window
    }
}

/// A soft inward glow around the edge of a display.
///
/// Drawn as a thick stroked border that is then blurred: the blur spreads the
/// colour inwards and the window clips whatever escapes outwards, which gives a
/// falloff without hand-building a gradient for each edge.
private struct EdgeGlowView: View {
    let tint: Color

    var body: some View {
        Rectangle()
            .strokeBorder(tint.opacity(0.85), lineWidth: 46)
            .blur(radius: 36)
    }
}

private struct ToastView: View {
    let state: PresentModeHUD.State

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: state.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(state.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(state.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
