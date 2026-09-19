import AppKit

/// Bridges CoreGraphics window bounds into AppKit screen coordinates.
enum WindowGeometry {
    /// Windows below this are toolbars, tooltips and other scraps that are not
    /// worth covering — and covering them would blanket the screen in slivers.
    private static let minimumInterestingSize = CGSize(width: 120, height: 80)

    /// CoreGraphics reports window bounds with the origin at the **top-left** of
    /// the primary display, Y increasing downwards. AppKit puts the origin at
    /// the **bottom-left**, Y increasing upwards. Getting this backwards puts
    /// covers on the wrong half of the screen, and on a secondary display it
    /// puts them nowhere at all.
    static func appKitRect(fromCoreGraphics rect: CGRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// The height AppKit measures from: the primary display, which is the one
    /// whose origin is zero — not necessarily `NSScreen.main`, which follows the
    /// key window and moves between displays.
    static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero }
        return (primary ?? NSScreen.screens.first)?.frame.height ?? 0
    }

    /// The on-screen windows belonging to a process, in AppKit coordinates.
    ///
    /// Owner pid and bounds come back from `CGWindowListCopyWindowInfo` without
    /// Screen Recording permission — only window *titles* are withheld — which
    /// keeps this inside the app's no-permissions rule.
    static func windows(ofProcess pid: pid_t) -> [NSRect] {
        guard let listed = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let height = primaryHeight

        return listed.compactMap { window -> NSRect? in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  // Layer 0 is an ordinary document window. Anything above is
                  // a panel, a menu or a shadow helper.
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= minimumInterestingSize.width,
                  rect.height >= minimumInterestingSize.height
            else { return nil }

            return appKitRect(fromCoreGraphics: rect, primaryHeight: height)
        }
    }
}
