import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ProtectionsSettingsView()
                .tabItem { Label("Protections", systemImage: "shield") }
            SensitiveAppsSettingsView()
                .tabItem { Label("Apps", systemImage: "app.badge") }
        }
        .frame(width: 460, height: 420)
    }
}

struct ProtectionsSettingsView: View {
    @EnvironmentObject private var controller: PresentModeController
    @EnvironmentObject private var preferences: Preferences
    @ObservedObject private var hotKeyCenter = HotKeyCenter.shared

    var body: some View {
        Form {
            Section {
                ForEach(controller.guards, id: \.id) { activeGuard in
                    Toggle(isOn: Binding(
                        get: { preferences.isEnabled(activeGuard) },
                        set: { preferences.setEnabled($0, for: activeGuard) }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activeGuard.title)
                                Text(activeGuard.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: activeGuard.symbolName)
                        }
                    }
                }
            } header: {
                Text("What happens in Present Mode")
            }

            Section {
                LabeledContent("Toggle Present Mode") {
                    ShortcutRecorder(combo: $preferences.hotKeyCombo)
                }
                if let error = hotKeyCenter.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("If the shortcut does nothing, another app probably claimed it first. macOS does not report that conflict, so the only fix is to try a different combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct SensitiveAppsSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var apps: [CatalogedApp] = []
    @State private var query = ""
    @State private var isLoading = true

    private var visibleApps: [CatalogedApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // A search field of our own rather than `.searchable(.toolbar)`.
            // The toolbar placement collides with the enclosing TabView's tab
            // strip: the field ends up sharing that row, and the list then
            // scrolls underneath both with nothing separating them.
            searchField
            Divider()

            if isLoading {
                ProgressView("Looking for installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleApps.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleApps) { app in
                    Toggle(isOn: binding(for: app)) {
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(app.name)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.inset)
            }

            Divider()
            Text("^[\(preferences.sensitiveBundleIDs.count) app](inflect: true) will be hidden when Present Mode is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .task {
            apps = await AppCatalog.installedApps()
            isLoading = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func binding(for app: CatalogedApp) -> Binding<Bool> {
        Binding(
            get: { preferences.sensitiveBundleIDs.contains(app.id) },
            set: { isOn in
                if isOn {
                    preferences.sensitiveBundleIDs.insert(app.id)
                } else {
                    preferences.sensitiveBundleIDs.remove(app.id)
                }
            }
        )
    }
}
