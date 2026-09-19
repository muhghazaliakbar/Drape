import AppKit

/// One installed application, as shown in the app picker.
struct CatalogedApp: Identifiable, Hashable, Sendable {
    let id: String   // bundle identifier
    let name: String
    let url: URL

    @MainActor var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Finds the apps installed on this Mac so the picker can offer real choices
/// rather than a free-text bundle identifier field.
enum AppCatalog {
    private static let searchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Scans for `.app` bundles. Runs off the main thread: reading a few hundred
    /// Info.plists is fast but not free, and the picker should never hitch.
    static func installedApps() async -> [CatalogedApp] {
        await Task.detached(priority: .userInitiated) {
            var found: [String: CatalogedApp] = [:]

            for path in searchPaths {
                let directory = URL(fileURLWithPath: path)
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for entry in entries where entry.pathExtension == "app" {
                    guard let bundle = Bundle(url: entry),
                          let bundleID = bundle.bundleIdentifier else { continue }
                    let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                        ?? entry.deletingPathExtension().lastPathComponent
                    // First match wins, so /Applications beats /System/Applications.
                    if found[bundleID] == nil {
                        found[bundleID] = CatalogedApp(id: bundleID, name: name, url: entry)
                    }
                }
            }

            return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }
}
