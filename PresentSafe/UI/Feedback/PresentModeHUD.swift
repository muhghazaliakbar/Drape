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
///
/// Two things keep the motion smooth, both learned by getting them wrong first:
/// the windows sit at full opacity and animate their *contents*, because
/// animating `NSWindow.alphaValue` drives a full-screen surface through the
/// window server and visibly steps; and the glow is drawn with gradients rather
/// than a blurred stroke, which on a 4K display was expensive enough to stutter
/// on its own.
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

    /// Drives every HUD window's content animation from one place, so the glow
    /// and the card move together instead of drifting apart.
    @MainActor
    final class Phase: ObservableObject {
        @Published var isVisible = false
    }

    private var windows: [NSWindow] = []
    private var phase = Phase()
    private var lifecycle: Task<Void, Never>?

    private static let hold = Duration.milliseconds(1600)
    private static let appear = Animation.easeOut(duration: 0.34)
    private static let disappear = Animation.easeInOut(duration: 0.55)
    private static let disappearDuration = Duration.milliseconds(560)

    func show(_ state: State) {
        guard Preferences.shared.showsOnScreenConfirmation else { return }

        // A second toggle mid-animation must replace the first outright, not
        // race it. Everything below belongs to this invocation only.
        lifecycle?.cancel()
        closeWindows()

        let phase = Phase()
        self.phase = phase

        windows = NSScreen.screens.map { makeGlowWindow(on: $0, tint: state.tint, phase: phase) }
        windows.append(makeToastWindow(for: state, phase: phase))

        for window in windows {
            // Full opacity from the start: the content is what fades, so there
            // is nothing here for the window server to animate.
            window.alphaValue = 1
            window.orderFrontRegardless()
        }

        lifecycle = Task { [weak self] in
            // Let SwiftUI commit the hidden state once before animating away
            // from it, otherwise the first frame is already fully drawn and the
            // fade-in is skipped entirely.
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(Self.appear) { phase.isVisible = true }

            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }
            withAnimation(Self.disappear) { phase.isVisible = false }

            try? await Task.sleep(for: Self.disappearDuration)
            guard !Task.isCancelled else { return }
            self?.closeWindows()
        }
    }

    private func closeWindows() {
        for window in windows { window.orderOut(nil) }
        windows = []
    }

    // MARK: - Windows

    private func makeGlowWindow(on screen: NSScreen, tint: Color, phase: Phase) -> NSWindow {
        let window = makeOverlayWindow(frame: screen.frame)
        window.contentView = NSHostingView(rootView: EdgeGlowView(tint: tint).environmentObject(phase))
        return window
    }

    private func makeToastWindow(for state: State, phase: Phase) -> NSWindow {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        // Roomy enough for the card to slide without being clipped.
        let size = NSSize(width: 300, height: 90)
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let window = makeOverlayWindow(frame: frame)
        window.contentView = NSHostingView(rootView: ToastView(state: state).environmentObject(phase))
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
/// Four gradients rather than one blurred stroke. A blur across a 4K surface is
/// recomputed every frame and was expensive enough to stutter on its own.
///
/// The bands are mitred like a picture frame rather than laid over each other.
/// Overlapping full-length bands compound their alpha in the corners, which
/// reads as an uneven glow — brighter at the corners than along the middle of
/// each edge. Cut to 45° they tile the border exactly once, and the joins are
/// invisible because at the diagonal a point is equally far from both edges, so
/// both gradients resolve to the same value there.
private struct EdgeGlowView: View {
    /// Tuning lives here. The glow has to register at the edge of vision while
    /// the user is looking at something else entirely — noticeable, never a
    /// wash over the screen they are about to present.
    private static let maxDepth: CGFloat = 100
    private static let depthRatio: CGFloat = 0.085
    private static let innerOpacity: Double = 0.22
    private static let midOpacity: Double = 0.05

    let tint: Color
    @EnvironmentObject private var phase: PresentModeHUD.Phase

    var body: some View {
        GeometryReader { proxy in
            let depth = min(Self.maxDepth, min(proxy.size.width, proxy.size.height) * Self.depthRatio)

            ZStack {
                band(.top, depth: depth)
                band(.bottom, depth: depth)
                band(.leading, depth: depth)
                band(.trailing, depth: depth)
            }
            // Easing the whole glow slightly outwards as it leaves reads as the
            // light receding, rather than a rectangle being switched off.
            .scaleEffect(phase.isVisible ? 1 : 1.035)
            .opacity(phase.isVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func band(_ edge: Edge, depth: CGFloat) -> some View {
        let gradient = LinearGradient(
            stops: [
                .init(color: tint.opacity(Self.innerOpacity), location: 0),
                .init(color: tint.opacity(Self.midOpacity), location: 0.38),
                .init(color: .clear, location: 1),
            ],
            startPoint: edge.glowStart,
            endPoint: edge.glowEnd
        )

        let isHorizontal = edge == .top || edge == .bottom

        return Rectangle()
            .fill(gradient)
            .frame(
                width: isHorizontal ? nil : depth,
                height: isHorizontal ? depth : nil
            )
            .clipShape(MitredBand(edge: edge))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
    }
}

/// One side of the frame, cut back at 45° where it meets its neighbours.
private struct MitredBand: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch edge {
        case .top:
            let depth = rect.height
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY))
        case .bottom:
            let depth = rect.height
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.minY))
        case .leading:
            let depth = rect.width
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + depth))
        case .trailing:
            let depth = rect.width
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - depth))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + depth))
        }

        path.closeSubpath()
        return path
    }
}

private extension Edge {
    /// The gradient runs inwards from the screen edge.
    var glowStart: UnitPoint {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var glowEnd: UnitPoint {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private struct ToastView: View {
    let state: PresentModeHUD.State
    @EnvironmentObject private var phase: PresentModeHUD.Phase

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
        .frame(height: 62)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .padding(.horizontal, 5)
        // Dropping in from under the menu bar, rather than appearing in place.
        .offset(y: phase.isVisible ? 8 : -34)
        .opacity(phase.isVisible ? 1 : 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}
