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
            Logger(subsystem: "dev.justghali.PresentSafe", category: "Preferences")
                .notice("""
                    First run: seeded \(seeded.count) of \(Self.suggestedBundleIDs.count) suggestions \
                    in \(elapsed, privacy: .public) — \(seeded.sorted().joined(separator: ", "), privacy: .public)
                    """)
        }
        self.hotKeyCombo = Self.loadCombo(from: defaults) ?? .default
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

    private enum Keys {
        static let sensitiveBundleIDs = "sensitiveBundleIDs"
        static let hotKeyCombo = "hotKeyCombo"
        static let focusShortcutOnPresent = "focusShortcutOnPresent"
        static let focusShortcutOnRelease = "focusShortcutOnRelease"
        static func guardEnabled(_ id: String) -> String { "guard.\(id).enabled" }
    }
}
