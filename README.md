# PresentSafe

[![CI](https://github.com/muhghazaliakbar/PresentSafe/actions/workflows/ci.yml/badge.svg)](https://github.com/muhghazaliakbar/PresentSafe/actions/workflows/ci.yml)

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
| **Hide sensitive apps** | Apps you pick (1Password, Slack, Mail…) are hidden, then brought back afterwards. Open one while presenting and its window is covered; launch one that was closed and it does not open at all. Snooze for three minutes if you really need it. |
| **Cover the notification corner** | Watches for banners and covers the corner only while one is up, on every display. |
| **Clear the desktop** | Desktop icons disappear for the duration. *Off by default — it restarts Finder.* |

Switching Present Mode on or off flashes a glow around every display and a card naming
the new state, so you know the shortcut landed without hunting for the menu bar icon.
Those are hidden from screen capture — the confirmation is for you, not the room.

Each protection is independent. Turn on only what you want.

On first launch PresentSafe ticks the sensitive apps you already have, drawn from a
built-in list of password managers, messaging clients and mail apps — so it protects
something before you configure anything. Only apps actually installed on your Mac are
ever selected, and everything is yours to change in Settings. Missing an app? That list
is [one file](PresentSafe/Settings/Preferences.swift) and a good first contribution.

## What it does not do

Being straight about the limits, because a privacy tool that overpromises is worse
than no tool at all:

- **It does not detect that you started sharing.** You press the shortcut. macOS has no
  supported API that tells an app "a screen capture just began", and the heuristics that
  approximate it are unreliable enough that shipping them would give you false confidence.
  Auto-detection for the major conferencing apps is planned, as a hint — never as the
  only line of defence.
- **It cannot silence notifications by itself.** There is no supported API: `INFocusStatus`
  is read-only, `INFocusStatusCenter` governs only permission to *read* your Focus, and the
  Do Not Disturb database is SIP-protected — all three checked against the macOS 27 SDK.
  Running a Shortcut is the only sanctioned route. That is written and works, but is not
  shipped yet — it is useless until you have built two Shortcuts by hand, and a protection
  that sets homework before it does anything is a poor first impression.
- **Covering the notification corner is best-effort.** macOS publishes a full-screen host
  window for Notification Center, never the banner's own frame, so PresentSafe can tell
  *that* a banner is up but not exactly where. The covered region is a well-placed estimate.
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

To run the tests:

```bash
xcodebuild test -project PresentSafe.xcodeproj -scheme PresentSafe -destination 'platform=macOS'
```

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

Four decisions worth calling out:

**Teardown is treated as the critical path, not activation.** If a guard throws halfway
through `activate()`, the controller still records it as engaged, because a partial change
still needs undoing. Quitting the app while Present Mode is on goes through
`.terminateLater` so guards finish restoring before the process dies. And because a crash
skips teardown entirely, the engaged guards are written to disk: the next launch undoes
whatever the dead process left switched on. The worst outcome for this app is not "failed
to protect" — it is "hid your apps and then forgot to bring them back".

**Protection is continuous, not a one-shot.** Guards keep watching after they engage. A
sensitive app launched mid-presentation gets hidden as it appears, and a display connected
after Present Mode is already on gets covered. Both were bugs first: the original guards
acted once at activation and then stopped paying attention, which failed in exactly the
moment that matters — the one where you plug in the projector.

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
- [ ] Focus integration via Shortcuts (written, not yet enabled)
- [ ] Best-effort detection of Zoom / Meet / Teams sharing, as a reminder
- [ ] Per-display curtains, and user-drawn cover regions
- [x] An app icon
- [ ] Signed, notarised release builds + Homebrew cask

## Languages

PresentSafe follows the language macOS is set to, and falls back to English. It ships in
English and Indonesian today.

You can also set it per app, without changing your whole system: System Settings →
General → Language & Region → Applications.

Adding a language is a translation job, not a coding one. Open
`PresentSafe/Localizable.xcstrings` in Xcode, pick your language from the `+` button, and
fill in the column. Nothing in the code needs to change.

One rule if you *do* touch the code: a string only reaches the catalog when its literal
sits at the call site. Assigning it to a `String` variable first makes it invisible to the
extractor, which is a silent failure — the app compiles, runs, and is simply never
translated. `xcodebuild -exportLocalizations` is the way to check what actually got picked
up.

## Contributing

New protections are the most useful contribution: conform to `PresentGuard`, add it to
the registry, done. If your guard changes anything that outlives the process, implement
`recoverAfterUncleanShutdown()` too.

Pure logic is unit-tested (see `PresentSafeTests`); the guards themselves are not, since
they mostly instruct macOS to do things. Issues and PRs welcome.

## Support

PresentSafe is free and MIT licensed, and it stays that way. If it has saved you from
sharing something you would rather not have, you are welcome to say thanks:

<a href="https://www.buymeacoffee.com/justghali.dev" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="48" width="173"></a>

Reporting a bug or adding an app to the sensitive list is worth just as much.

## Licence

MIT — see [LICENSE](LICENSE).
