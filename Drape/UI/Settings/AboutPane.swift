import SwiftUI

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()
            details
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 8) {
            appMark

            Text(Self.appName)
                .font(.system(size: 22, weight: .semibold))

            Text(Self.version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("One shortcut, pressed three seconds before you share your screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The bundle's own icon, so this screen cannot drift away from what the
    /// Dock and the Finder show. It used to draw a stand-in, because the app
    /// shipped without an icon and the generic placeholder macOS hands out read
    /// as an unfinished app.
    private var appMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
    }

    // MARK: - Details

    private var details: some View {
        Form {
            Section {
                LabeledContent("Developer", value: "Muh Ghazali Akbar")
                LabeledContent("Website") {
                    Link("justghali.dev", destination: URL(string: "https://justghali.dev")!)
                }
                LabeledContent("Source Code") {
                    Link("GitHub", destination: Self.repository)
                }
                LabeledContent("Licence") {
                    Link("MIT", destination: Self.repository.appending(path: "blob/main/LICENSE"))
                }
            }

            Section {
                Link("Report an Issue", destination: Self.repository.appending(path: "issues"))
            }

            Section {
                coffeeButton
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Free and MIT licensed, and it stays that way. If Drape has saved you from sharing something you would rather not have, you are welcome to say thanks.")
                    Text("© 2026 Muh Ghazali Akbar. Open source, and free to use and modify.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// Buy Me a Coffee hand out a PNG for this. It is drawn natively instead: a
    /// fixed 217×60 raster cannot be sharp on every display, ignores the
    /// window's appearance, and reads as a foreign object dropped into a grouped
    /// Form. Their yellow and their wording, our rendering.
    private var coffeeButton: some View {
        Link(destination: Self.coffee) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                Text("Buy me a coffee")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Self.coffeeYellow, in: Self.coffeeShape)
            .overlay(Self.coffeeShape.strokeBorder(.black.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Buy me a coffee"))
        .onHover { inside in
            // A Link styled .plain loses the pointing hand it would otherwise get.
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Bundle

    private static let repository = URL(string: "https://github.com/muhghazaliakbar/Drape")!
    private static let coffee = URL(string: "https://www.buymeacoffee.com/justghali.dev")!

    /// Buy Me a Coffee's brand yellow, #FFDD00. Fixed in both appearances,
    /// because it is their colour and not a colour this app gets to reinterpret.
    private static let coffeeYellow = Color(red: 1, green: 0.867, blue: 0)

    /// Their button is a rounded rectangle, not a capsule; continuous curvature
    /// is the macOS reading of the same shape.
    private static let coffeeShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Drape"
    }

    /// Read from the bundle rather than hardcoded, so a release bump cannot
    /// leave this screen quietly claiming the wrong version.
    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(localized: "Version \(short) (\(build))")
    }
}
