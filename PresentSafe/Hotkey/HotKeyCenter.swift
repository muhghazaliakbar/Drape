import AppKit
import Combine
import OSLog

/// Keeps the registered system shortcut in sync with the user's preference.
///
/// This exists mainly for one reason: while the user is *recording* a new
/// shortcut, the old one must stop working. Carbon hot keys are consumed before
/// the event ever reaches the app, so without `suspend()` a user trying to
/// re-record over their current shortcut would toggle Present Mode instead of
/// typing it into the recorder.
@MainActor
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()

    /// Set when the chosen combination could not be claimed — almost always
    /// because another app got there first. Surfaced in Settings so the user
    /// learns it now, rather than during a presentation.
    @Published private(set) var registrationError: String?

    private let hotKey = GlobalHotKey()
    private let preferences: Preferences
    private var cancellables = Set<AnyCancellable>()
    private var isSuspended = false
    private let logger = Logger(subsystem: "dev.justghali.PresentSafe", category: "HotKey")

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    func start() {
        preferences.$hotKeyCombo
            .sink { [weak self] combo in
                // `@Published` fires from `willSet`, so the stored property is
                // still the old value here — always register the value the
                // publisher handed over, never `preferences.hotKeyCombo`.
                // The hop exists because `sink` runs non-isolated.
                Task { @MainActor in self?.apply(combo) }
            }
            .store(in: &cancellables)
    }

    /// Stops the shortcut from firing, so it can be typed into a recorder.
    func suspend() {
        isSuspended = true
        hotKey.unregister()
    }

    func resume() {
        isSuspended = false
        apply(preferences.hotKeyCombo)
    }

    private func apply(_ combo: KeyCombo) {
        guard !isSuspended else { return }
        do {
            try hotKey.register(combo) {
                PresentModeController.shared.toggle()
            }
            registrationError = nil
            logger.info("Registered shortcut \(combo.displayString, privacy: .public)")
        } catch {
            registrationError = error.localizedDescription
            logger.error("Could not register \(combo.displayString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
