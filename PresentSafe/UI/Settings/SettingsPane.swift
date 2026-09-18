import AppKit
import SwiftUI

/// One page of Settings, and everything the window needs to present it.
///
/// Panes carry their own ideal size because a macOS preferences window resizes
/// to fit the pane you pick rather than settling on one size that suits none of
/// them — a short list of switches and a scrolling list of every installed app
/// want very different shapes.
enum SettingsPane: String, CaseIterable, Identifiable {
    case protections
    case apps
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protections: "Protections"
        case .apps: "Apps"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .protections: "shield.lefthalf.filled"
        case .apps: "square.grid.2x2"
        case .about: "info.circle"
        }
    }

    var idealSize: NSSize {
        switch self {
        case .protections: NSSize(width: 520, height: 400)
        case .apps: NSSize(width: 520, height: 520)
        case .about: NSSize(width: 520, height: 470)
        }
    }

    var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("settings.\(rawValue)")
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .protections: ProtectionsPane()
        case .apps: SensitiveAppsPane()
        case .about: AboutPane()
        }
    }
}
