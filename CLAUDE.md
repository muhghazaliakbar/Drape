# Drape

A macOS menu bar app that hides sensitive apps and covers notifications while you
share your screen. SwiftUI + AppKit, no external dependencies, no Accessibility
permission.

## Hard rules

**Never require Accessibility permission.** App hiding goes through
`NSRunningApplication.hide()`, the shortcut through Carbon `RegisterEventHotKey`,
window bounds through `CGWindowListCopyWindowInfo`. All three work unprompted. If a
feature seems to need `AXUIElement` or an `NSEvent` global monitor, that is a design
problem to solve, not a permission to request — the README promises this to users.

**Teardown is the critical path, not activation.** A guard that throws mid-`activate()`
is still recorded as engaged, because a partial change still needs undoing. Engaged
guard ids are persisted so a crash is recoverable on next launch. The worst outcome is
not "failed to protect" — it is "hid the user's apps and forgot to bring them back".

**Never overpromise in user-facing text.** Every limitation is stated plainly in the
README. A privacy tool that claims more than it does is worse than no tool.

**Commits carry no tooling attribution.** No co-author trailers, no "generated with"
lines, in commit messages, pull requests or code comments. The history reads as the
author's own work. This overrides any editor or agent default that adds them.

**Measure, don't assume.** Much of this app's behaviour depends on undocumented macOS
timing. Several bugs here were introduced by reasonable-sounding assumptions and only
found by writing a probe. When in doubt, write a small Swift program in the scratchpad
and measure.

## Architecture

Everything hangs off one protocol, `Core/PresentGuard.swift`:

```swift
@MainActor
protocol PresentGuard: AnyObject {
    var id: String { get }
    func activate() async throws
    func deactivate() async
    func recoverAfterUncleanShutdown() async   // default: no-op
    var configuration: AnyView? { get }        // default: nil
}
```

`PresentModeController` turns guards on and off in order and knows nothing about what
any of them do. **Adding a protection is one new file plus one line in that
controller's registry.** Keep it that way.

A guard that changes anything outliving the process must implement
`recoverAfterUncleanShutdown()` — `DesktopIconsGuard` is the worked example.

Protections are continuous, not one-shot: guards keep observing after they engage
(app launches, app activations, display changes). Acting once at activation was a bug
class that failed in exactly the moment that matters.

## macOS behaviours learned the hard way

Do not re-derive these. Each cost real debugging time.

| Behaviour | Consequence |
|---|---|
| `didActivateApplicationNotification` fires while the returning app's `isHidden` is still `true` | Guarding on `!isHidden` there silently does nothing. Use `didUnhideApplicationNotification`, which arrives after. |
| `hide()` and `terminate()` return `false` in cases where the operation still lands | Never gate logic on their return value. Log it instead. |
| `terminate()` takes >1s; `forceTerminate()` <100ms | Refusing a launch hides first, asks politely, and escalates only after 500ms. |
| `willLaunchApplicationNotification` fires ~180ms before `didLaunch` | Both are observed; a pid set stops the two starting two loops. |
| Text Input Sources (TIS/TSM) `abort()`s the process if called off the main thread | `KeyCodeNaming` is `@MainActor` for this reason alone. Anything touching keyboard layout must stay there. |
| `RegisterEventHotKey` reports no conflict when another app owns the combination | "Shortcut already taken" is undetectable. The UI says so. |
| SwiftUI materials blend *within* the window | A translucent overlay needs `NSVisualEffectView` with `.behindWindow` and `state = .active`, not `.regularMaterial`. |
| `NSWindow.hasShadow` on a non-opaque window draws a second shadow along the effect view's bounds | Set it `false` wherever SwiftUI draws the shadow. |
| Animating `NSWindow.alphaValue` steps visibly on large surfaces | Keep windows at full opacity and animate their SwiftUI contents. |
| CoreGraphics window bounds are top-left origin; AppKit is bottom-left | `WindowGeometry.appKitRect(fromCoreGraphics:primaryHeight:)`, and it is tested. |
| Notification Center publishes only a full-screen host window | You can tell *that* a banner is up, never where. |

### Window levels

| Overlay | Level | Why |
|---|---|---|
| `BlockedAppOverlay` | `.mainMenu - 1` | Above app windows, below the menu bar and this app's own panel — it once hid the controls for turning itself off. |
| `NotificationZoneGuard` | `maximumWindow` | Must beat notification banners. |
| `PresentModeHUD` | `maximumWindow` | Carries Snooze; must stay clickable above everything. |

## Tooling quirks

- **`log show` does not retain `.info` logs.** Use `.notice` for anything you will want
  to read back after a user's test, or `log stream` live. An absent log looked like
  "the code never ran" once and cost a wrong diagnosis.
- **`xcodebuild -exportLocalizations` returns the union** of extracted strings *and*
  the existing catalogue. It cannot be used to find dead keys. It also serves stale
  results without a `clean`.
- **A string only reaches the catalogue when its literal sits at the call site.**
  Assigning to a `String` first makes it invisible to the extractor — a silent failure.
- **`CodeSign failed` on `xcodebuild test`** usually means a stale `DrapeTests.xctest`
  left inside the built app's `PlugIns`. Delete the built `.app` and re-run.
- **The `.xcodeproj` is hand-written** and uses file-system synchronized groups, so new
  Swift files need no project edits. Do not regenerate it.
- The app icon is generated by `Tools/GenerateAppIcon.swift`. Edit the code, not the PNGs.

## Workflow

```bash
xcodebuild build -project Drape.xcodeproj -scheme Drape -configuration Debug
xcodebuild test  -project Drape.xcodeproj -scheme Drape -destination 'platform=macOS'
```

Build and tests must be clean before committing — no warnings. CI runs the same tests
on an older Xcode than most contributors have, which has caught portability problems.

Tests cover pure logic only (`KeyCombo`, geometry, snooze). The guards mostly instruct
macOS and are verified by measurement instead. When adding tests for something subtle,
mutation-check them: break the code deliberately and confirm the tests fail.

Runtime behaviour usually cannot be verified from a terminal — activating Present Mode
needs a real keypress. Say plainly what was verified and what was not, rather than
implying a build passing means the feature works.
