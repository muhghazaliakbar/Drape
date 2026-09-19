import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await PresentModeController.shared.recoverFromPreviousRun()
        }
        HotKeyCenter.shared.start()
    }

    /// An accessory app has no Dock icon and no windows, so launching it again
    /// would otherwise do nothing at all. Showing Settings is the useful answer,
    /// and it gives the user a way in that does not depend on finding a small
    /// icon in a crowded menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    /// Never quit while guards are still engaged. Leaving someone's password
    /// manager hidden and their desktop icons gone, because they hit Quit, is
    /// the single worst thing this app could do.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PresentModeController.shared.isActive else { return .terminateNow }

        Task { @MainActor in
            await PresentModeController.shared.tearDownForTermination()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
