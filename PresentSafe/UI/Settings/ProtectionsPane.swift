import SwiftUI

struct ProtectionsPane: View {
    @EnvironmentObject private var controller: PresentModeController
    @EnvironmentObject private var preferences: Preferences
    @ObservedObject private var hotKeyCenter = HotKeyCenter.shared

    var body: some View {
        Form {
            Section {
                ForEach(controller.guards, id: \.id) { activeGuard in
                    GuardRow(activeGuard: activeGuard)

                    // Only while the guard is on: configuration for something
                    // switched off is noise.
                    if preferences.isEnabled(activeGuard), let configuration = activeGuard.configuration {
                        configuration
                    }
                }
            } header: {
                Text("When Present Mode is on")
            }

            Section {
                LabeledContent("Toggle Present Mode") {
                    ShortcutRecorder(combo: $preferences.hotKeyCombo)
                }

                if let error = hotKeyCenter.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("If the shortcut does nothing, another app claimed it first. macOS does not report that conflict, so the only fix is a different combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// One protection, as a switch with its own explanation.
///
/// The subtitle is not decoration: every guard here trades something away —
/// a Finder restart, a best-effort cover — and the switch is only an informed
/// choice if that cost is visible at the moment of deciding.
private struct GuardRow: View {
    @EnvironmentObject private var preferences: Preferences
    let activeGuard: any PresentGuard

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isEnabled(activeGuard) },
            set: { preferences.setEnabled($0, for: activeGuard) }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: activeGuard.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeGuard.title)
                    Text(activeGuard.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
    }
}
