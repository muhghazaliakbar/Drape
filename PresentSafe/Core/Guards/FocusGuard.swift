import SwiftUI

/// Turns on a Focus while Present Mode is active, by running a Shortcut.
///
/// Covering banners is a second-best answer; not receiving them is the real
/// one. macOS has no supported API for it — `INFocusStatus.isFocused` is
/// read-only, `INFocusStatusCenter` governs only permission to *read* the
/// status, and the Do Not Disturb database is SIP-protected. All three checked
/// against the macOS 27 SDK rather than assumed.
///
/// What does exist is Shortcuts: its "Set Focus" action can turn a Focus on and
/// off, and `shortcuts run` invokes it. That needs the user to build two
/// shortcuts once, which is why this guard ships disabled and explains itself
/// rather than failing quietly.
@MainActor
final class FocusGuard: PresentGuard {
    let id = "focus"
    let title = "Turn on a Focus"
    let summary = "Runs a Shortcut, the only supported way to silence notifications."
    let symbolName = "moon.fill"
    let isEnabledByDefault = false

    private let preferences: Preferences
    private var didRun = false

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func activate() async throws {
        guard let name = preferences.focusShortcutOnPresent, !name.isEmpty else {
            throw GuardError.notConfigured("Choose a Shortcut in Settings.")
        }

        let result = try await Command.run("/usr/bin/shortcuts", ["run", name])
        guard result.succeeded else {
            throw GuardError.systemRefused("the Shortcut “\(name)” did not run")
        }
        didRun = true
    }

    func deactivate() async {
        guard didRun else { return }
        didRun = false

        guard let name = preferences.focusShortcutOnRelease, !name.isEmpty else { return }
        try? await Command.run("/usr/bin/shortcuts", ["run", name])
    }

    var configuration: AnyView? {
        AnyView(FocusGuardConfiguration(preferences: preferences))
    }
}

private struct FocusGuardConfiguration: View {
    @ObservedObject var preferences: Preferences
    @State private var shortcuts: [String] = []

    var body: some View {
        Group {
            picker("On", selection: $preferences.focusShortcutOnPresent)
            picker("Off", selection: $preferences.focusShortcutOnRelease)

            if shortcuts.isEmpty {
                Text("No Shortcuts found. Create two in the Shortcuts app using the “Set Focus” action — one that turns a Focus on, one that turns it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { shortcuts = await ShortcutsCatalog.available() }
    }

    private func picker(_ label: String, selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(shortcuts, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
        }
    }
}
