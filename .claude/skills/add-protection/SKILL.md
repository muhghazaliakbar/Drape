---
name: add-protection
description: Add a new protection (a PresentGuard) to PresentSafe. Use when asked to make Present Mode do something additional while it is on — hide something, cover something, change a system setting — or when reviewing a guard someone else wrote.
---

# Adding a protection

A protection is one file conforming to `PresentGuard` plus one line in the registry.
If a change needs more than that, the architecture is being worked around — stop and
reconsider rather than spreading the feature across the app.

## Steps

1. **Write the guard** in `PresentSafe/Core/Guards/<Name>Guard.swift`.

   ```swift
   @MainActor
   final class SomethingGuard: PresentGuard {
       let id = "something"                // stable; it is the preferences key
       let title = String(localized: "…")  // String(localized:), not a bare literal
       let summary = String(localized: "…")
       let symbolName = "…"                // SF Symbol, fine in UI
       let isEnabledByDefault = false      // true only if it has no visible side effect

       func activate() async throws { … }
       func deactivate() async { … }
   }
   ```

2. **Register it** in `PresentModeController.init`, in the `guards` array. That is the
   only edit outside the new file.

3. **If it changes anything that outlives the process** — a `defaults` key, another
   app's state, a system setting — implement `recoverAfterUncleanShutdown()` to undo it
   unconditionally. The controller calls it at launch when a previous run died without
   tearing down. `DesktopIconsGuard` is the worked example.

4. **If it needs settings of its own**, return them from `configuration`. They appear
   under the guard's row, only while it is enabled. `HideAppsGuard` is the example.

5. **Add the strings** to `PresentSafe/Localizable.xcstrings`. Verify with a *clean*
   export — the exporter serves stale results otherwise, and returns the union of
   extracted strings and the existing catalogue, so it cannot tell you what is missing
   unless you diff against it yourself.

## What the review should catch

- **Does `deactivate()` work when `activate()` never ran or threw partway through?**
  It is called during teardown regardless. This is the single most important question.
- **Does it keep watching?** A guard that acts once at activation and stops paying
  attention has failed every time so far — apps launch, displays get plugged in,
  windows move. Observe the relevant notification, or poll.
- **Does it gate on a return value that lies?** `hide()` and `terminate()` report
  failure in cases where the operation still lands. Log them; never branch on them.
- **Does it need Accessibility?** Then it does not ship. Find another route.
- **Does it touch Text Input Sources off the main thread?** That aborts the process.

## Verifying

`xcodebuild test` proves it compiles and that pure logic holds. It does not prove the
guard works — activating Present Mode needs a real keypress.

For anything depending on macOS timing or undocumented behaviour, write a small Swift
program in the scratchpad and measure it. Several guards here are shaped by findings no
amount of reasoning would have produced. Log at `.notice`, not `.info`, so the result of
a user's test can be read back afterwards.

Then say plainly which parts were verified and which were not.
