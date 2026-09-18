import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var controller: PresentModeController
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Button(action: controller.toggle) {
                Text(controller.isActive ? "Turn Off Present Mode" : "Turn On Present Mode")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(controller.isActive ? .red : .accentColor)

            if let error = controller.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            guardSummary
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.isActive ? "eye.slash.circle.fill" : "eye.circle")
                .font(.title2)
                .foregroundStyle(controller.isActive ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("PresentSafe").font(.headline)
                Text(controller.isActive ? "Protecting your screen" : "Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(GlobalHotKey.defaultDisplayString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var guardSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controller.guards, id: \.id) { activeGuard in
                let enabled = preferences.isEnabled(activeGuard)
                Label {
                    Text(activeGuard.title)
                        .font(.callout)
                        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                } icon: {
                    Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(enabled ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { openSettings() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}
