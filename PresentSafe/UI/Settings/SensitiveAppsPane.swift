import SwiftUI

struct SensitiveAppsPane: View {
    @EnvironmentObject private var preferences: Preferences

    @State private var apps: [CatalogedApp] = []
    @State private var query = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, prompt: "Search apps")
            Divider()
            content
            Divider()
            footer
        }
        .task {
            apps = await AppCatalog.installedApps()
            isLoading = false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Looking for installed apps…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearching {
            searchResults
        } else {
            partitionedList
        }
    }

    private var searchResults: some View {
        Group {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(matches) { AppRow(app: $0, isOn: binding(for: $0)) }
                    .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Selected apps are lifted to their own section rather than left scattered
    /// through several hundred rows. The point of this pane is answering "what
    /// will disappear when I present?", and that should not require scrolling.
    private var partitionedList: some View {
        List {
            if !selected.isEmpty {
                Section("Hidden when presenting") {
                    ForEach(selected) { AppRow(app: $0, isOn: binding(for: $0)) }
                }
            }

            Section(selected.isEmpty ? "Installed apps" : "Other apps") {
                ForEach(unselected) { AppRow(app: $0, isOn: binding(for: $0)) }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            if !selected.isEmpty {
                Button("Deselect All") {
                    for app in selected {
                        preferences.sensitiveBundleIDs.remove(app.id)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private var isSearching: Bool { !query.isEmpty }

    private var matches: [CatalogedApp] {
        apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selected: [CatalogedApp] {
        apps.filter { preferences.sensitiveBundleIDs.contains($0.id) }
    }

    private var unselected: [CatalogedApp] {
        apps.filter { !preferences.sensitiveBundleIDs.contains($0.id) }
    }

    /// Counts only apps that are actually installed.
    ///
    /// The stored set is seeded with common password managers and chat clients,
    /// most of which any given Mac will not have. Counting the raw set would
    /// promise to hide eight apps while showing two ticks.
    private var footerText: String {
        switch selected.count {
        case 0: "No apps will be hidden yet."
        case 1: "1 app will be hidden when Present Mode is on."
        default: "\(selected.count) apps will be hidden when Present Mode is on."
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

private struct AppRow: View {
    let app: CatalogedApp
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                // App icons are the fastest thing to recognise in a list this
                // long — far quicker than reading names — so they are worth the
                // row height. 28pt also hits a real icon representation rather
                // than forcing macOS to downscale.
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)

                Text(app.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 3)
        }
        .toggleStyle(.checkbox)
    }
}

/// A compact search field.
///
/// `.searchable(placement: .toolbar)` is the obvious choice and the wrong one
/// here: it competes for the toolbar that the settings window already uses as
/// its pane switcher.
private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
