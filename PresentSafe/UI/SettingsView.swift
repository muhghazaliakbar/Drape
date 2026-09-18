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
                LabeledContent("Toggle Present Mode", value: GlobalHotKey.defaultDisplayString)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Customising the shortcut is coming in a later release.")
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
            if isLoading {
                ProgressView("Looking for installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleApps) { app in
                    Toggle(isOn: binding(for: app)) {
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .searchable(text: $query, placement: .toolbar, prompt: "Search apps")
            }

            Divider()
            Text("^[\(preferences.sensitiveBundleIDs.count) app](inflect: true) will be hidden when Present Mode is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .task {
            apps = await AppCatalog.installedApps()
            isLoading = false
        }
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
