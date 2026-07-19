---
name: android-parity
description: One autonomous Android-parity session — pick ONE screen gap from epic #1059, match the iPhone pixel-for-pixel with mandatory screenshot comparison, ship it to Play, update the ledger. Spawned in a loop by scripts/android-parity-watchdog.sh.
---

# Android Parity Session

You are one session in a continuous loop. Deliver ONE completed, aesthetically
iPhone-matching screen (or one scoped chunk of a large screen) per session,
then end. The watchdog restarts the next session automatically.

**The bar (operator, verbatim): "aesthetic UI like iPhone — so far UI matching
is lame, it doesn't look nice, it's very basic."** A screen that merely has the
same data is NOT done. It must LOOK like Drift iOS.

## Session algorithm

### 1. Orient (≤5 min)
- `gh issue view 1059` — the parity ledger table is the authoritative status.
- `gh issue list --label android-parity --state open` — the child issues.
- Pick ONE target: the highest-priority open gap per the epic's "Suggested
  order", preferring unfinished elements of screens already started
  (Food #1062 depth → Body #1065 chart → Dashboard #1061 rest → Health
  Connect #1070 → Coach #1066 → Workout detail #1064 (recovery map + pose
  photos are operator-requested) → More #1067 → capture #1063 → #1069/#1068
  → hygiene #1071).
- Post a one-line claim comment on the child issue: what this session will do.

### 2. iPhone reference FIRST — never port from source alone
- iOS simulator "iPhone 17 Pro" (`xcrun simctl list devices booted`; boot +
  `xcrun simctl launch booted com.drift.health` if needed).
- Drive it to the target screen (mobile-mcp tools; device id from
  `mobile_list_available_devices`; iOS clicks use POINTS = pixels/3).
- `mobile_save_screenshot` EVERY state of the screen (default, filled, empty,
  sheets open). These are the ground truth — Read each one and STUDY it:
  layout, spacing, type sizes/weights, colors, corner radii, shadows,
  iconography, empty-state copy.

### 3. Read the iOS source end-to-end
The child issue lists the files. Read them fully (views + their ViewModels +
shared components they use). Enumerate EVERY visual element, sheet, gesture,
empty/loading/error state into a checklist. No silent omissions — every gap
you can't port this session gets named in the issue comment.

### 4. Implement on Android
- Rules from CLAUDE.md + epic #1059 conventions: SharedUI single-source where
  the file can be shared; Theme tokens ONLY (never hardcode colors/sizes);
  `sym()` in Symbols.swift for every SF Symbol (check SkipUI's map in
  `drift-android/.build/checkouts/skip-ui/.../Components/Image.swift`;
  unmapped glyph = warning triangle = instant fail); SkipUICompat.swift for
  API shims; `@State` never `private`; DB warm-up off-main via
  `CoreResourcesBootstrap.warmUpDatabase()` then @MainActor services.
- Build: `cd drift-android && JAVA_HOME=/opt/homebrew/opt/openjdk ANDROID_HOME=/opt/homebrew/share/android-commandlinetools skip app launch --android --plain`.
- SkipUI facts learned so far: Circle().trim().stroke() rings WORK;
  matchedGeometryEffect, Font.monospacedDigit, TextField(axis:), listRowInsets,
  UIKit haptics do NOT (shim or skip); skipstone does not follow symlinks
  (SharedUI is materialized by scripts/android-sync-core-resources.sh).

### 5. Drive + screenshot the emulator
`adb shell input tap/text` through the SAME states you captured on iOS;
`adb exec-out screencap -p` each one. If the app crashes: `adb logcat -d -b
crash` has the abort message; fix and rebuild.

### 6. AESTHETIC GATE (the step that kills "lame")
Read the iOS and Android screenshots side by side and grade honestly:
- Same element inventory? (count the cards/chips/rows — missing = fail)
- Same visual hierarchy — type scale, weights, section headers, spacing rhythm?
- Theme colors correct (goal-aware green/red, accent, soft tints)?
- Zero warning-triangle icons? Zero big barren regions iOS doesn't have?
- Would a designer say these are the same app? If no → iterate. Up to 3
  refine→rebuild→rescreenshot loops. Still short after 3: ship the improvement
  anyway, file the residual gap on the child issue explicitly.

### 7. Verify + ship
- If SharedUI/ or DriftCore/ changed: iOS must build too
  (`xcodebuild build -project Drift.xcodeproj -scheme Drift -destination
  'platform=iOS Simulator,name=iPhone 17 Pro'`); DriftCore changes also need
  `cd DriftCore && swift test` + `./scripts/android-build-check.sh`.
- Commit with explicit paths (concurrent sessions exist), push.
- Publish when a user-visible screen changed: `./scripts/android-publish.sh`
  (has a lock; if it reports another publish running, skip — next session gets it).

### 8. Record + end
- Comment on the child issue: shipped elements, commit hash, build number,
  residual gaps (each named), aesthetic-gate verdict.
- Update the epic #1059 ledger row for the screen (gh issue edit — patch only
  your row).
- Close the child issue ONLY when its checklist is 100% or every remaining
  item is linked out.
- End the session. Do not start a second screen.

## Guardrails
- Never touch iOS behavior without running the iOS suite.
- Never run two `skip app launch` or two publishes concurrently.
- If the emulator is dead: `$ANDROID_HOME/emulator/emulator -avd drift-emulator
  -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &` and wait for
  `adb shell getprop sys.boot_completed` = 1.
- If truly blocked (missing credential, broken main), comment the blocker on
  the child issue and end — the watchdog will bring the next session.
