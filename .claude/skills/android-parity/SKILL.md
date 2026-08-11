---
name: android-parity
description: EXECUTOR lane (Opus 5) of the tiered parity autopilot — implements the top `planned` issue exactly per its Fable-planner plan, emulator-verifies, guards iOS, publishes. Spawned in a loop by scripts/android-parity-watchdog.sh.
---

# Parity Executor Session (Opus 5 — execute the plan)

You are the EXECUTION lane of a three-tier autopilot:
**Opus 5 scout tests & finds gaps → Fable planner grooms + plans → Opus 5 (you) execute.**
Deliver ONE planned issue per session, then end. The watchdog restarts the
next session automatically.

**The bar (operator, verbatim): "aesthetic UI like iPhone" + "same speed".**
A screen that merely has the same data is NOT done — it must LOOK and FEEL
like Drift iOS.

## Session algorithm

### 0. Operator directives — read FIRST, they override everything below
`cat ~/drift-android-parity-directives.txt`.

### 0.5 Pick work — planned issues are the queue
`gh issue list --label android-parity --label planned --state open` — take the
highest priority (P0 > P1 > P2 in the title, else oldest). Read the issue AND
its `## Plan` comment fully — **the plan is your instruction set; follow it.**
Post a one-line claim comment. Deviate from the plan only when reality
contradicts it (a file moved, an API doesn't exist) — note every deviation in
your closing comment. If a hard architectural question emerges mid-work,
STOP that sub-piece: comment the question, relabel the issue `needs-plan`,
finish what the plan still covers, and end.
If NO planned issues exist: do a directive-0 item if one is explicitly
pending, else run the interaction-QA sweep (step 8) on the least-recently
swept screen and end.

### 1. Orient (≤5 min)
- `gh issue view 1059` — the parity ledger table is the authoritative status.
- `gh issue list --label android-parity --state open` — the child issues.
- **The issues are a map, NOT the territory.** Do your own gap-finding every
  session: diff the actual iOS source (`Drift/Views/**`, `Drift/*.swift`) and
  live iPhone screenshots against the Android app. The goal is the EXACT same
  app — anything iOS has that Android lacks is a gap whether or not an issue
  mentions it. Found gaps get fixed (if in scope) or filed on the right child
  issue before the session ends.
- Pick ONE target: the highest-priority open gap per the epic's "Suggested
  order", preferring unfinished elements of screens already started
  (Food #1062 depth → Body #1065 chart → Dashboard #1061 rest → Health
  Connect #1070 → Coach #1066 → Workout detail #1064 (recovery map + pose
  photos are operator-requested) → More #1067 → capture #1063 → #1069/#1068
  → hygiene #1071).
- Post a one-line claim comment on the child issue: what this session will do.

### 1.5 Check for a scout port kit — skip the study phase if one exists
`ls ~/drift-android-parity-prep/<target>/KIT.md` — the scout lane pre-produces
iPhone screenshots + element inventory + SkipUI compat + perf audit for
upcoming targets. If a kit exists and is newer than the last commit touching
the screen's iOS source: Read KIT.md + every screenshot, treat them as steps
2–3 done, and go straight to implementation. Spot-check one screenshot against
the live iPhone if anything looks stale. No kit → do steps 2–3 yourself.

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
- SharedUI compiles in THREE configs: iOS app, Skip Android pass, AND Skip's
  Darwin (iOS!) bridging pass — the module pass has no app-target types. Gate
  UIKit code with `#if canImport(UIKit)`; gate app-target-only types
  (MuscleHighlightCard etc.) with `#if DRIFT_IOS_APP` (defined in project.yml).
- Pose photos: HEICs in the app module's Resources/ load via
  Bundle.module.url(subdirectory:) → jar: URL → SkipUI AsyncImage (Coil)
  decodes them fine on API 28+; withAnimation(.repeatForever) opacity
  crossfade WORKS (PoseCrossfadeView renders on Android).
- Outline "star" is UNMAPPED in skip-ui (case commented out upstream, #148) →
  warning triangle; sym() maps star/star.slash → star.fill.

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
- **Publish is MANDATORY, not optional**: if this session committed any
  user-visible change to drift-android/ or SharedUI/, run
  `./scripts/android-publish.sh` before ending — every significant chunk of
  work reaches the operator's phone as a fresh Play build. The script has a
  lock; if another publish is running, state that in the issue comment and
  the NEXT session must publish first thing (check
  `git log --oneline | head` vs the last `publish build N` commit).

### 8. Gap-hunt sweep (mandatory, ~10 min, EVERY session)
After your screen ships, pick ONE other screen pair (rotate — don't always
pick the same) and compare live: iPhone screenshot vs Android screenshot of
the same state. Log every difference you see — visual or functional — to the
right child issue (or file a new `android-parity` issue if none fits). This
is how the loop finds what the filed issues missed; the operator's standing
order is to constantly hunt gaps, not just work the backlog.

**Audit sessions**: if the directives file names no pending priority and the
epic's ordered gaps are all in progress/done, this session IS an audit: walk
the entire app on both devices, screenshot every tab + main sheet, produce a
fresh gap list, file/refresh issues, update the ledger. An audit that finds
nothing new must say so on the epic with the screenshot evidence.

### 9. Record + end
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
