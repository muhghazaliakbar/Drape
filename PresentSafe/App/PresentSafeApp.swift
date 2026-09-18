import SwiftUI

@main
struct PresentSafeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = PresentModeController.shared
    @StateObject private var preferences = Preferences.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(controller)
                .environmentObject(preferences)
        } label: {
            // The icon is the only always-visible signal that Present Mode is
            // on. It must be unmistakable at a glance, mid-call, on a laptop
            // display someone else is watching.
            Image(systemName: controller.isActive ? "eye.slash.circle.fill" : "eye.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
