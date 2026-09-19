import AppKit
import Combine
import OSLog

/// User-facing settings, backed by `UserDefaults`.
///
/// Guard enablement is keyed by the guard's own `id` rather than by a fixed set
/// of properties, so adding a guard needs no change here at all.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.adoptLegacySettings(into: defaults)
        // A stored empty array is a real choice — the user deselected
        // everything — and must not be re-seeded. Only a missing key means
        // first run.
        if let stored = defaults.stringArray(forKey: Keys.sensitiveBundleIDs) {
            self.sensitiveBundleIDs = Set(stored)
        } else {
            let start = ContinuousClock.now
            let seeded = Self.installedSuggestions()
            let elapsed = start.duration(to: .now)
            self.sensitiveBundleIDs = seeded
            Logger(subsystem: "dev.justghali.Drape", category: "Preferences")
                .notice("""
                    First run: seeded \(seeded.count) of \(Self.suggestedBundleIDs.count) suggestions \
                    in \(elapsed, privacy: .public) — \(seeded.sorted().joined(separator: ", "), privacy: .public)
                    """)
        }
        self.hotKeyCombo = Self.loadCombo(from: defaults) ?? .default
        self.keepsSensitiveAppsHidden = defaults.object(forKey: Keys.keepsSensitiveAppsHidden) as? Bool ?? true
        self.showsOnScreenConfirmation = defaults.object(forKey: Keys.showsOnScreenConfirmation) as? Bool ?? true
        self.focusShortcutOnPresent = defaults.string(forKey: Keys.focusShortcutOnPresent)
        self.focusShortcutOnRelease = defaults.string(forKey: Keys.focusShortcutOnRelease)
    }

    @Published var sensitiveBundleIDs: Set<String> {
        didSet { defaults.set(Array(sensitiveBundleIDs), forKey: Keys.sensitiveBundleIDs) }
    }

    @Published var focusShortcutOnPresent: String? {
        didSet { defaults.set(focusShortcutOnPresent, forKey: Keys.focusShortcutOnPresent) }
    }

    @Published var focusShortcutOnRelease: String? {
        didSet { defaults.set(focusShortcutOnRelease, forKey: Keys.focusShortcutOnRelease) }
    }

    @Published var keepsSensitiveAppsHidden: Bool {
        didSet { defaults.set(keepsSensitiveAppsHidden, forKey: Keys.keepsSensitiveAppsHidden) }
    }

    @Published var showsOnScreenConfirmation: Bool {
        didSet { defaults.set(showsOnScreenConfirmation, forKey: Keys.showsOnScreenConfirmation) }
    }

    @Published var hotKeyCombo: KeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(hotKeyCombo) else { return }
            defaults.set(data, forKey: Keys.hotKeyCombo)
        }
    }

    /// A stored shortcut that no longer decodes — an older build's format, or a
    /// corrupted value — falls back to the default rather than leaving the app
    /// with no shortcut at all.
    private static func loadCombo(from defaults: UserDefaults) -> KeyCombo? {
        guard let data = defaults.data(forKey: Keys.hotKeyCombo) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    func isEnabled(_ aGuard: any PresentGuard) -> Bool {
        defaults.object(forKey: Keys.guardEnabled(aGuard.id)) as? Bool ?? aGuard.isEnabledByDefault
    }

    func setEnabled(_ enabled: Bool, for aGuard: any PresentGuard) {
        defaults.set(enabled, forKey: Keys.guardEnabled(aGuard.id))
        objectWillChange.send()
    }

    /// Candidates for the first-run selection: the categories that leak
    /// something personal the instant a screen goes up — credentials, private
    /// conversations, mail.
    ///
    /// Everyone's Mac holds a different subset, so this errs on the side of
    /// breadth. It costs nothing to be generous: an identifier matching nothing
    /// installed is silently dropped at seeding, so a wrong or obsolete entry
    /// is inert rather than harmful. Missing apps are a good first contribution.
    ///
    /// Deliberately excludes notes and project tools (Notes, Notion, Linear).
    /// Those are as likely to *be* the thing being presented as to leak, and a
    /// tool that hides the user's own slides on first run gets uninstalled.
    static let suggestedBundleIDs: [String] = [
        // Password managers — the highest-cost leak on this list.
        "com.1password.1password",              // 1Password 8
        "com.agilebits.onepassword7",           // 1Password 7
        "com.apple.Passwords",
        "com.apple.keychainaccess",             // Keychain Access
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",              // KeePassXC
        "com.dashlane.Dashlane",
        "in.sinew.Enpass-Desktop",
        "me.proton.pass.electron",              // Proton Pass
        "com.nordpass.macos",

        // Messaging — private conversations, and notification previews.
        "com.tinyspeck.slackmacgap",            // Slack
        "com.hnc.Discord",
        "ru.keepcoder.Telegram",                // Telegram for macOS
        "com.tdesktop.Telegram",                // Telegram Desktop
        "net.whatsapp.WhatsApp",
        "com.apple.MobileSMS",                  // Messages
        "org.whispersystems.signal-desktop",    // Signal
        "com.microsoft.teams2",                 // Teams
        "com.microsoft.teams",                  // Teams classic
        "com.facebook.archon",                  // Messenger
        "jp.naver.line.mac",                    // LINE
        "com.tencent.xinWeChat",                // WeChat
        "com.viber.osx",                        // Viber
        "com.skype.skype",

        // Mail
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.SparkDesktop.appstore",    // Spark
        "com.readdle.smartemail-Mac",           // Spark, direct download
        "it.bloop.airmail2",                    // Airmail
        "org.mozilla.thunderbird",
        "ch.protonmail.desktop",                // Proton Mail
        "io.canarymail.mac",                    // Canary Mail
        "com.mimestream.Mimestream",
    ]

    /// The first-run selection: suggestions filtered down to what this Mac
    /// actually has.
    ///
    /// Seeding the raw list instead would leave the stored set non-empty on a
    /// Mac with none of these apps — and a non-empty set is exactly what stops
    /// `HideAppsGuard` from reporting that nothing is configured. The user would
    /// switch Present Mode on, watch the icon change, and be told nothing while
    /// nothing at all was hidden. Filtering here is what keeps that failure
    /// loud.
    ///
    /// `urlForApplication(withBundleIdentifier:)` is a LaunchServices lookup,
    /// not a directory scan, so running it for every suggestion at launch is
    /// cheap enough to do synchronously.
    static func installedSuggestions() -> Set<String> {
        Set(
            suggestedBundleIDs.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
        )
    }

    // MARK: - Rename

    /// The app was called PresentSafe until 0.2.0. Renaming it changed the
    /// bundle identifier, and `UserDefaults` is keyed by that — so anyone who
    /// had already chosen their sensitive apps and their shortcut would have
    /// opened Settings to find it blank, with no hint that their old choices
    /// were still on disk under another name.
    ///
    /// Every key is copied, rather than a known list, because guard enablement
    /// is keyed by each guard's own id: a fixed list here would silently drop
    /// the settings of any guard added after this was written.
    ///
    /// Safe to delete once no Mac is still running a pre-rename build.
    static func adoptLegacySettings(
        into defaults: UserDefaults,
        ownDomain: String = Bundle.main.bundleIdentifier ?? "dev.justghali.Drape",
        from legacyDomain: String = "dev.justghali.PresentSafe"
    ) {
        // Named domains rather than `object(forKey:)`, because a UserDefaults
        // search list also covers the running app's own domain — which makes
        // "has this install been used yet?" unanswerable from a test running
        // inside that very app, and the answer would depend on whether the
        // developer happens to have used it.
        guard defaults.persistentDomain(forName: ownDomain)?.isEmpty ?? true,
              let legacy = defaults.persistentDomain(forName: legacyDomain),
              !legacy.isEmpty
        else { return }

        defaults.setPersistentDomain(legacy, forName: ownDomain)
        Logger(subsystem: "dev.justghali.Drape", category: "Preferences")
            .notice("Adopted \(legacy.count, privacy: .public) settings from \(legacyDomain, privacy: .public)")
    }

    private enum Keys {
        static let sensitiveBundleIDs = "sensitiveBundleIDs"
        static let hotKeyCombo = "hotKeyCombo"
        static let keepsSensitiveAppsHidden = "keepsSensitiveAppsHidden"
        static let showsOnScreenConfirmation = "showsOnScreenConfirmation"
        static let focusShortcutOnPresent = "focusShortcutOnPresent"
        static let focusShortcutOnRelease = "focusShortcutOnRelease"
        static func guardEnabled(_ id: String) -> String { "guard.\(id).enabled" }
    }
}
