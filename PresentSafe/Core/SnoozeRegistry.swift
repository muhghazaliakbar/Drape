import Foundation

/// Tracks which apps the user has temporarily allowed through.
///
/// Snoozing is the pressure valve. Without it the only way past a block is to
/// switch protection off entirely, which is the wrong trade when someone needs
/// one message mid-presentation — they turn the whole thing off and forget to
/// turn it back on.
@MainActor
final class SnoozeRegistry {
    static let shared = SnoozeRegistry()

    /// Long enough to read a message and reply, short enough that forgetting
    /// about it is not a problem.
    static let duration: TimeInterval = 3 * 60

    private var deadlines: [String: Date] = [:]

    func snooze(_ bundleID: String, now: Date = .now) {
        deadlines[bundleID] = now.addingTimeInterval(Self.duration)
    }

    func isSnoozed(_ bundleID: String, now: Date = .now) -> Bool {
        guard let deadline = deadlines[bundleID] else { return false }
        return deadline > now
    }

    func remaining(_ bundleID: String, now: Date = .now) -> TimeInterval {
        guard let deadline = deadlines[bundleID] else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// Snoozes last for one session of Present Mode, not for ever. Turning
    /// protection off and on again is a deliberate act, and it should mean what
    /// it says.
    func clear() {
        deadlines.removeAll()
    }
}
