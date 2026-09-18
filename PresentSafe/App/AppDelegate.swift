import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await PresentModeController.shared.recoverFromPreviousRun()
        }
        HotKeyCenter.shared.start()
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
