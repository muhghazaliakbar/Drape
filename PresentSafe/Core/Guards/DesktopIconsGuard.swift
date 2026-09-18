import AppKit

/// Clears the desktop of icons for the duration of Present Mode.
///
/// macOS exposes no API for this, so the only route is the `CreateDesktop`
/// Finder default plus a Finder restart. That restart is visible and briefly
/// closes Finder windows, which is why this guard ships disabled by default —
/// a protection that surprises the user is a protection they turn off for good.
@MainActor
final class DesktopIconsGuard: PresentGuard {
    let id = "desktopIcons"
    let title = "Clear the desktop"
    let summary = "Hides desktop icons. Restarts Finder, so windows will flicker."
    let symbolName = "macwindow.on.rectangle"
    let isEnabledByDefault = false

    private var didHide = false

    func activate() async throws {
        try await setDesktopIconsVisible(false)
        didHide = true
    }

    func deactivate() async {
        guard didHide else { return }
        didHide = false
        try? await setDesktopIconsVisible(true)
    }

    private func setDesktopIconsVisible(_ visible: Bool) async throws {
        try await run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", visible ? "true" : "false"])
        try await run("/usr/bin/killall", ["Finder"])
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GuardError.systemRefused("could not run \(launchPath)")
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
