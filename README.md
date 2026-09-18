# PresentSafe

**One shortcut, pressed three seconds before you share your screen.**

Your password manager, your DMs, the `.env` file open in your editor, the notification
that arrives mid-demo — screen sharing exposes all of it, and the moment you notice is
always the moment after everyone else has.

PresentSafe is a macOS menu bar app that puts a curtain over the leaky parts of your
screen. Hit `⌃⌥⌘P` (or whatever shortcut you set), share with confidence, hit it again
when you're done.

> **Status: early.** v0.1 works and is useful, but the scope is deliberately small.
> See [What it does not do](#what-it-does-not-do) before you rely on it.

## What it does

| Protection | What happens |
|---|---|
| **Hide sensitive apps** | Apps you pick (1Password, Slack, Mail…) are hidden, then brought back afterwards. |
| **Cover the notification corner** | An opaque window parks over the region where banners appear, on every display. |
| **Clear the desktop** | Desktop icons disappear for the duration. *Off by default — it restarts Finder.* |

Each protection is independent. Turn on only what you want.

## What it does not do

Being straight about the limits, because a privacy tool that overpromises is worse
than no tool at all:

- **It does not detect that you started sharing.** You press the shortcut. macOS has no
  supported API that tells an app "a screen capture just began", and the heuristics that
  approximate it are unreliable enough that shipping them would give you false confidence.
  Auto-detection for the major conferencing apps is planned, as a hint — never as the
  only line of defence.
- **Covering the notification corner is best-effort.** The banner region is not a
  documented rectangle. If Apple moves it, the cover misses.
- **Sharing a single window instead of a whole screen bypasses the cover.** The cover is a
  window of its own, so it is captured only when the whole screen is.
- **It does not suppress notification sounds**, or stop notifications from reaching
  Notification Center.
- **It cannot tell you when your shortcut is already taken.** Two apps can register the
  same global shortcut and macOS reports no conflict to either — verified, not assumed.
  If your shortcut does nothing, another app claimed it first; pick a different one.

## Install

Requires macOS 14 or later.

```bash
git clone https://github.com/muhghazaliakbar/PresentSafe.git
cd PresentSafe
open PresentSafe.xcodeproj
```

Then build and run (`⌘R`). Signed release builds will arrive once the feature set settles.

No Accessibility permission is required. That is a design constraint, not an
accident — see below.

## How it is put together

The whole app is organised around one protocol:

```swift
@MainActor
protocol PresentGuard: AnyObject {
    var id: String { get }
    var title: String { get }
    func activate() async throws
    func deactivate() async
}
```

`PresentModeController` knows how to turn guards on and off in order. It knows nothing
about what any of them actually do. Adding a protection means adding one file and one
line to the registry in the controller's initialiser.

Two decisions worth calling out:

**Teardown is treated as the critical path, not activation.** If a guard throws halfway
through `activate()`, the controller still records it as engaged, because a partial change
still needs undoing. Quitting the app while Present Mode is on goes through
`.terminateLater` so guards finish restoring before the process dies. The worst outcome
for this app is not "failed to protect" — it is "hid your apps and then forgot to bring
them back".

**Shortcuts are stored by physical key position, not by character.** A shortcut recorded
on the key where QWERTY has `P` keeps working after switching to AZERTY — and the label
in Settings updates to whatever that key actually prints, by asking the active keyboard
layout through `UCKeyTranslate`.

**No Accessibility permission.** Hiding apps uses `NSRunningApplication.hide()` and the
shortcut uses Carbon's `RegisterEventHotKey`, both of which work without prompting. The
modern alternatives (`AXUIElement`, `NSEvent` global monitors) are nicer APIs that would
send every new user to System Settings before the app did anything useful. For a tool you
reach for *seconds* before you present, that trade is worth it.

## Roadmap

- [x] Configurable shortcut
- [ ] Best-effort detection of Zoom / Meet / Teams sharing, as a reminder
- [ ] Per-display curtains, and user-drawn cover regions
- [ ] Focus mode integration via Shortcuts
- [ ] Signed, notarised release builds + Homebrew cask

## Contributing

New protections are the most useful contribution: conform to `PresentGuard`, add it to
the registry, done. Issues and PRs welcome.

## Licence

MIT — see [LICENSE](LICENSE).
