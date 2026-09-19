import SwiftUI

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()
            details
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 8) {
            appMark

            Text(Self.appName)
                .font(.system(size: 22, weight: .semibold))

            Text(Self.version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("One shortcut, pressed three seconds before you share your screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The bundle's own icon, so this screen cannot drift away from what the
    /// Dock and the Finder show. It used to draw a stand-in, because the app
    /// shipped without an icon and the generic placeholder macOS hands out read
    /// as an unfinished app.
    private var appMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
    }

    // MARK: - Details

    private var details: some View {
        Form {
            Section {
                LabeledContent("Developer", value: "Muh Ghazali Akbar")
                LabeledContent("Website") {
                    Link("justghali.dev", destination: URL(string: "https://justghali.dev")!)
                }
                LabeledContent("Source Code") {
                    Link("GitHub", destination: Self.repository)
                }
                LabeledContent("Licence") {
                    Link("MIT", destination: Self.repository.appending(path: "blob/main/LICENSE"))
                }
            }

            Section {
                Link("Report an Issue", destination: Self.repository.appending(path: "issues"))
            } footer: {
                Text("© 2026 Muh Ghazali Akbar. Open source, and free to use and modify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bundle

    private static let repository = URL(string: "https://github.com/muhghazaliakbar/PresentSafe")!

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PresentSafe"
    }

    /// Read from the bundle rather than hardcoded, so a release bump cannot
    /// leave this screen quietly claiming the wrong version.
    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(localized: "Version \(short) (\(build))")
    }
}
