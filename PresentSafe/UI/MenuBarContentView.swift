import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var controller: PresentModeController
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            primaryAction

            if let error = controller.lastError {
                warning(error)
            }

            Divider()
            protectionSummary
            Divider()
            commands
        }
        .padding(10)
        .frame(width: 258)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.isActive ? "eye.slash.circle.fill" : "eye.circle")
                .font(.system(size: 20))
                // Accent, not red. An active Present Mode means the screen is
                // covered — that is the state the user wanted, and colouring it
                // like a warning tells them the opposite.
                .foregroundStyle(controller.isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

            VStack(alignment: .leading, spacing: 0) {
                Text("PresentSafe")
                    .font(.system(size: 13, weight: .semibold))
                Text(controller.isActive ? "Protecting your screen" : "Idle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Text(preferences.hotKeyCombo.displayString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // Prominent only for the action that starts protection. Tinting the "off"
    // button red made the safe state look like an alarm, and a filled red
    // capsule is not something macOS puts in a menu bar panel.
    @ViewBuilder
    private var primaryAction: some View {
        if controller.isActive {
            Button(action: controller.toggle) {
                Text("Turn Off Present Mode").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button(action: controller.toggle) {
                Text("Turn On Present Mode").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func warning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Protections

    private var protectionSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Protections")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(controller.guards, id: \.id) { activeGuard in
                let enabled = preferences.isEnabled(activeGuard)
                HStack(spacing: 7) {
                    // The guard's own symbol rather than a generic tick: it says
                    // which protection this is, not merely that something is on.
                    Image(systemName: activeGuard.symbolName)
                        .font(.system(size: 11))
                        .frame(width: 14)
                        .foregroundStyle(enabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

                    Text(activeGuard.title)
                        .font(.system(size: 12))
                        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))

                    Spacer(minLength: 0)

                    if !enabled {
                        Text("Off")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Commands

    private var commands: some View {
        VStack(alignment: .leading, spacing: 1) {
            MenuCommand("Settings…") { SettingsWindowController.shared.show() }
            MenuCommand("Quit PresentSafe") { NSApplication.shared.terminate(nil) }
        }
    }
}

/// A row that behaves like a menu item: full-width accent highlight on hover,
/// which is how every other menu on the system reads. Link-styled blue text was
/// borrowed from the web and looks foreign here.
private struct MenuCommand: View {
    let title: LocalizedStringKey
    let action: () -> Void

    @State private var isHighlighted = false

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHighlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHighlighted = $0 }
    }
}

