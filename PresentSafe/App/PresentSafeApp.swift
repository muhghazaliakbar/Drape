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
            // The only always-visible signal that Present Mode is on. It has to
            // be unmistakable at a glance, mid-call, on a laptop display
            // someone else is watching.
            Image(nsImage: MenuBarIcon.image(covering: controller.isActive))
        }
        .menuBarExtraStyle(.window)
    }
}
