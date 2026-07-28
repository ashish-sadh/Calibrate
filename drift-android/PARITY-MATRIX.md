# Android Parity Matrix

Owned by the **parity scout** (Fable lane). One row per screen/sub-surface.
Status ∈ `ok` / `deviation` / `missing` / `broken` / `ios-only-by-design` / `unknown`.
`unknown` = enumerated from iOS source, not yet verified on the emulator.
Issue column: the GitHub issue tracking the gap (blank when ok/unknown).
Structural ground truth: Android hosts SharedUI single-source files for
**Workout** (WorkoutTab → WorkoutView) and **Food** (FoodTab → FoodTabView);
**Today / Body / More** are still Android-only re-creations (TodayTab.swift,
WeightTab.swift, MoreTab.swift). Capture + Coach + health sub-screens are
not ported at all.

## Session notes (append-only)

- **2026-07-28 (scout #7):** SOURCE-ONLY structural diff of **Today** (epic #1061) — ps-check
  found BOTH sibling lanes live (executor PID 67317 3:37AM + planner PID 72510 3:45AM), emulator
  untouched per the scout-#3 collision lesson. Full `DashboardView.swift` + `DashboardView+Cards.swift`
  → `TodayTab.swift` (410 ln) diff: **9 coarse rows → 25 granular rows**, ordered to match iOS `body`.
  Every gap classified DriftCore-portable-NOW vs health-seam-gated (#1070). Filed **4 scoped
  portable-now ports**: **#1129** Daily Average energy-balance card (`tdeeCard`: eating/deficit/burning
  ring + target line + explainer, all DriftCore) / **#1130** proactive coaching nudge + behavior insights
  (`BehaviorInsightService` = DriftCore; the on-brand coach surface — Ask-AI wires to the already-ported
  floating chat) / **#1131** meal list swipe-to-delete + dot-rail (`MealTimelineSection` — Android
  `mealsCard` has **NO delete**, a real functional gap) / **#1132** weekly Workout Consistency card
  (DriftCore, NOT health-gated). #1061 demoted to INDEX. **Staleness corrections (verify, don't trust
  the matrix):** row `broken #1093` was STALE — **#1093 CLOSED**, Describe/Search/Recent chips work; the
  residual is **Snap** (camera glyph opens Coach chat, not capture → #1063/#1128). Health-seam rows
  (Activity: Active/Steps + AH `workoutCard`; Recovery: sleep/HRV/RHR) stay `missing`→#1070 because Android
  correctly **HIDES** them (no fake zeros, [[android_hide_unwired_integration_ui]]) rather than render empty —
  NOT new ports until the seam lands. Nav-gated deviations point at existing ports (profile nudge→#1116,
  goal card→#1117, tdee nav→#1118, feedback banner→#1114, backup banner→#1094, Voice method→#1126). Confirmed
  the floating Coach button **IS** ported (`ChatIconButton`→AIChatView, AppShell + ContentView) — Coach-entry
  row flipped to `ok`. No code touched (matrix only); worker WIP left alone. Emulator-drive debt unchanged
  (food compiled-shared rows + scout #3's 5 workout leftovers + Supplements device-verify) — still needs an
  uncontended window; the 4 new Today ports are source-verified, not device-verified.

- **2026-07-28 (scout #6):** SOURCE-ONLY sweep — ps-check found BOTH sibling lanes live
  (executor `/android-parity` PID 74920 + planner PID 74936, all started 1:49AM), so the
  emulator was untouched per the scout-#3 collision lesson (executor reinstalls the APK
  mid-drive → phantom app-died). Area: **Health sub-screens (#1068)**, the operator's
  0-EVERY-SCREEN mandate and the last big coarse area after scout #5 did More. Enumerated
  the full iOS tree from source (Biomarkers Tab/Detail/LabReportUpload/Detail 1595 ln,
  GlucoseTabView 517, CycleView 647): **4 coarse rows → 24 granular rows**. Filed 3 scoped
  needs-plan ports: **#1122** Biomarkers (donut/patterns/reports/search/grouped-list/trend +
  lab-OCR seam) / **#1123** Glucose (zone chart + SAF CSV import + HC glucose read) / **#1124**
  Cycle (phase timeline + 2 charts — **HARD-blocked on #1070**: 100% Health-driven,
  empty-state-only until Health Connect grows cycle reads; flagged for planner plan-vs-block).
  **#1068 demoted to INDEX** (comment recorded) so the planner never chews the 4-screen
  ~2,800-line monolith (same as #1067→#1114–1119). **Two staleness corrections (verify,
  don't trust the matrix): Supplements is DONE** — ported to SharedUI + wired `MoreTab:146`,
  was #1068's 4th sub-screen, dropped from the queue (row → ok); **Progress Photos** → deviation
  (`ProgressGalleryAndroid.swift` exists + wired `MoreTab:147` — Android re-creation, not the
  SharedUI port). More-hub HEALTH-rows note refreshed (2 of 7 dests now landed). Portability
  baked into every row: all data/logic services are DriftCore; recurring seams = `Charts`/`Canvas`
  Skip-absent (Path port, precedent `WeightChartAndroid`), `fileImporter`→SAF (#1109), HealthKit
  →Health Connect (#1070); `LabReportOCR` (Vision/PDFKit)→Nebius per 0-AI-LADDER, no key UI. No
  code touched (matrix only); worker WIP tree was clean. Harness: the per-turn iOS `PAUSE` +
  `#1043 P0` hook injections are the parked iOS lane leaking in (parity control=RUN) — false
  stops. Emulator-drive debt unchanged (food compiled-shared rows + scout #3's 5 workout
  leftovers + now Supplements device-verify) — still needs an uncontended window.

- **2026-07-27 (scout #5, Fable):** SOURCE-ONLY sweep #2 — ps-check found BOTH sibling
  lanes live (executor with #1097 WIP on the tree, planner mid-session), so the emulator
  was untouched; picked the operator's 0-EVERY-SCREEN mandate (More tab) over the food
  rotation — More had zero sub-screen rows. Enumerated the ENTIRE iOS More tree from
  source (MoreTabView.swift 1098 lines + 8 Settings/ files, ~3.5k lines): hub (11 nav
  rows), SettingsView (7 sections), NotificationsSettingsView, UsageInsightsView,
  ProfileView, GoalView + GoalSetupView, AlgorithmSettingsView, backup stack, BYOK.
  More section rewritten 8 coarse → 40 granular rows. Filed 6 scoped needs-plan ports:
  **#1114** hub / **#1115** Settings screen / **#1116** Profile / **#1117** Goal+Setup
  (also flips FoodTabView's iOS-gated goal affordances — food rows repointed) /
  **#1118** Algorithm / **#1119** Notifications page + scheduling seam (the one real
  architecture decision). **#1067 demoted to INDEX (needs-plan removed)** so the planner
  never chews the 3.5k-line monolith in one pass. Policy calls baked into rows: BYOK
  screen + WebSearchSettingsCard = ios-only-by-design (0-AI-FOCUS bans ALL key-entry UI
  on Android); hub HEALTH rows stay hidden until #1068/#1069 destinations land (no dead
  taps, #1093 lesson); every "persists across relaunch" acceptance inherits #1108.
  Portability verified from source: TDEEEstimator / WeightGoal / WeightTrendCalculator /
  ChatTelemetryService / FeatureUsage are all DriftCore; goal flow is Chart-free
  (GoalView's `import Charts` is vestigial); iOS-only deps = NotificationService
  (→ #1119 seam), BackupService (→ #1094/#1109), AIChatInsightsView (hide link),
  HealthNutritionSyncService (hide behind HC-write capability). Queued for a future
  Fable session, NOT absorbed here (one sweep per session): needs-fable escalations
  #1105 (Skip collection-persistence audit) + #1109 (SAF bridge design). Emulator drive
  debt unchanged: food compiled-shared rows + scout #3's 5 workout leftovers still need
  an uncontended window. No code touched; worker WIP left alone.

- **2026-07-27 (scout #4, Fable):** SOURCE-ONLY sweep — ps-check found the executor
  lane live (16+ min in, #1108 WIP on the tree) so the emulator was never touched
  (scout #3's collision lesson applied). (1) Post-manual-window enumeration refresh:
  operator checkpoint e8821123 (07-26) added the SetEntrySanity set-done dialog to
  shared ActiveWorkoutView — reconciled: scout #1's "implausible-weight" ok row IS
  this dialog's ceiling variant (build 44 postdates the 22:56 checkpoint; builds 46+
  published 01:55+); annotated the un-driven variants (3× jump-from-last, reps>100,
  duration>90m, "Let me fix it" path) + the bare-"form tips"→current-exercise
  refinement. (2) WorkoutScan tracking hole closed: #1095 closed descoping scan to
  #1063, but #1063 never enumerated workout scan and carries no needs-plan label —
  the operator-flagged gap (0-RESUME.b) sat in no lane's queue. Filed **#1110 P2
  needs-plan** (scoped port: picker/streaming seams, hardening-commit inventory,
  DriftCore-extraction question, done-when); both scan rows repointed #1095→#1110.
  (3) Food area sharpened from source (next in rotation, most unknowns): FoodTabView
  gating is DISCIPLINED — every iOS-only sheet's entry affordance is gated with it
  (no #1093-class dead taps found in source). 8 unknown rows → missing (recipe
  builder, combos+combo-log, goal setup, plant points detail, confirm-log,
  CombosView, ManualFoodEntrySheet, LogMealSheet — all under #1062/#1067),
  suggestion chips → deviation (Android quick-logs directly w/ toast undo,
  documented interim), 2 rows added (Snap shortcut missing #1063; entry-row
  contextMenu with Log Again + Move Up/Down as real residuals). Compiled-shared
  rows (calendar sheet, edit sheet, timeline, donut, serving stepper) stay unknown
  pending an uncontended-emulator drive — that's the next scout's food work, plus
  the 5 leftover workout drive-throughs from scout #3. 1 issue filed, no code
  touched, worker WIP (DriftAndroidApp.swift, AndroidPrefsFacade.kt) left alone.

- **2026-07-27 (executor, Sonnet):** Executed #1102's plan exactly: `WorkoutService.
  saveSession`/`loadSession` switched from `UserDefaults` `Data` to `String` (JSON),
  with a legacy-Data read fallback. 2 new Tier-0 tests, full DriftCore + iOS suites
  green (516f85cd, pushed). **On-device verification found the fix insufficient** —
  filed **#1108 P0**: UserDefaults writes made during app *runtime* never reach
  `shared_prefs/defaults.xml` on this build, for ANY value type, not just Data.
  Proven 5 ways: scenePhase-background persist (HOME press, confirmed real
  onPause/onStop via dumpsys — no write), 30s auto-save tick (90s undisturbed
  foreground wait — no write), the explicit synchronous "Minimize" button call
  (write demonstrably executes in-process — Resume banner shows — but still never
  hits disk after 90s), the mandated `am force-stop` + relaunch repro (session
  genuinely lost, no banner), and an unrelated control test — the More tab weight-
  unit lbs/kg toggle (plain String/enum preference, zero relation to WorkoutService)
  — which visibly recomposes in the UI but never touches `defaults.xml` either.
  `shared_prefs/` mtime stayed frozen at the last fresh-install timestamp through
  the entire ~30min session. Root cause unknown (Skip Fuse bridge's disk-flush
  mechanism, not the Swift-side code) — `needs-plan`, not a mechanical fix. Flagged
  **#1104** (same String pattern, was `planned`) directly and relabeled it
  `needs-plan` — it would very likely hit the identical wall since its own
  Done-When requires the same `am force-stop` survival test. #1102 relabeled
  `planned` → `blocked` (dependency #1108); do not close until #1108 lands and the
  Variant A/B repro is re-verified. No publish this session (DriftCore-only change,
  no user-visible improvement yet given #1108).

- **2026-07-27 (scout #3, Fable):** Workout unknown-row burn-down, part 2, on build 48
  (verified f5ceecc9 in-binary first). Drove: past-workout sheet (pastDate badge Jul 26 +
  close-confirm), voice/text sheet end-to-end (typed → LOCAL parse → review; #1079 holds —
  canonical names, no junk-create; unmatched → "Not in library" resolve → picker → Add
  applies), Import alert (Load Package I → "Added 0", name-dedup DB-safe), picker
  leading-swipe Favorite full round-trip (Favorites section materializes; star.slash
  collapses to star.fill → noted on #1099), custom-exercise sheet (name + 7-part Targets
  menu; canceled unsaved — no custom-delete API exists), rest-chip menu (6 options
  0:30–3:00; post-select chip state unverified, see below). 10 rows resolved. Filed
  **#1106 P1** (Fuse keeps the sheet's @State viewModel alive across presentations —
  Cancel → reopen resumes the stale parsed session and exercises ACCUMULATE across
  canceled sessions; double-log risk; iOS resets by construction) and **#1107 P2** (two
  pre-#1079 raw-utterance customs — "3x10 bench press at 135" ×2 — permanently pollute
  "Your Exercises"; no delete path). **Session cut at ~60%: the executor lane
  (claude -p /android-parity, live since 05:53) reinstalled the APK mid-drive — logcat
  "Package REPLACED" 06:10:42 + 2× "app died, no saved state" (06:08:34, 06:10:01)
  killed my active-workout sheet; evidence + proposed emulator mutex commented on #1100.
  Aborted device work rather than bank phantom evidence — next scout: ps-check for a
  live executor BEFORE driving.** Still unknown: per-set warmup flag, active-row→detail
  nav, WorkoutDetailView edit-set/swipe-delete/menu drive-throughs, browser custom CTA,
  BodyMap tap→template. New harness datum: cold-launch FIRST composition can exceed 5s
  on SwiftShader — full-screen mangled intermediate (1-char-wide vertical text columns)
  at 5s post-launch, settled at ~8s; the 2.5s popup rule extends to whole-screen first
  composition — never file a render bug off a first screenshot (checked: #1093 is about
  dead TAPS, unaffected). DB left clean: voice sessions canceled (and died with the
  process — nothing persists, per #1102's own mechanics), custom sheet canceled,
  favorite round-tripped, package load added 0, in-flight workouts never saved.

- **2026-07-27 (scout #2, Fable):** Workout unknown-row burn-down (0-FOCUS): drove
  the full create-template flow (name → picker multi-select → edit-exercise sheet:
  stepper bounds, rest dropdown, warmup toggle → sectioned save), template preview
  actions (row→detail, Start, Edit, Favorite↔Unfavorite, Delete), templates ⋮ menu,
  active-workout close dialog, exercise ⋮ menu, kg/lbs unit menu, command-strip
  focus. 19 rows updated (13 unknown→ok, 3 resolved from source as dead-code/
  ios-only-by-design: Rename + Delete-Template alerts unreachable on BOTH platforms,
  Delete-Workout alert iOS-only). **Filed #1102 P0: SavedSession never persists on
  Android — `UserDefaults.set(Data)` is dropped by Skip's SharedPreferences bridge
  (prefs dump has no session key; `__unrepresentable__` marker precedent), so any
  process death loses the whole workout; proven with two controlled kills (with and
  WITHOUT a prior background transition). Flipped the kill+resume row ok→broken —
  scout #1's pass evidently exercised the same-process path only.** Filed #1103 P1:
  set-done toggle pops the IME with a cursor dropped into the notes/Tip TextField
  (screenshot-evidenced; ties to executor #2's set-row x-range breadcrumb). Infra:
  the emulator's qemu process crashed twice mid-session (host-side, snapshot
  auto-saved; ~20-30min uptime each) — earlier "spontaneous sheet dismissal"
  anomalies attributed to that, not to app menus (deliberate slow re-drive survived
  all menu interactions). SwiftShader first-composition of any popup takes >1s —
  screenshot 2.5s+ after popup-triggering taps or you record a false negative.
  Not driven (left unknown): Import alert, rest-chip menu options, picker/browser
  custom-exercise sheets, per-set warmup flag, active-row→detail nav, voice-log
  sheet (Nebius residual per 0-AI-LADDER). DB left as found (ScoutQA template
  created, driven, deleted; test workouts discarded; the two crash-lost sessions
  left no rows by the very bug filed).

- **2026-07-27 (scout #1, Fable):** Matrix created from full iOS source scan
  (Drift/Views/** + SharedUI/**: every .sheet/.fullScreenCover/.contextMenu/
  .swipeActions/.alert/NavigationLink). Area swept on-device: WORKOUT (0-FOCUS)
  — full end-to-end drive on emulator build 44: root, browser (chips FIXED,
  live search, tap-through), detail (crossfade works), picker (multi-select +
  batch add), active workout (set edit, rest timer, implausible-weight dialog,
  finish/completion/share), history → WorkoutDetailView (⋮ menu complete),
  template preview (warmups + rest times), kill+resume. 27 rows updated.
  Filed: #1096 P0 (first-set-done relaunches MainActivity → dumped to Today),
  #1097 P1 (numeric fields insert-not-replace; NumericFieldSelectAll has no
  Android equivalent), #1098 P2 (resume loses Previous ghosts), #1099 P2
  (detail equipment chip wrench). Commented #1095: streak card + history rows
  VERIFIED WORKING (descoped); scan entry + fetchRecentWorkouts=[] +
  show-all-10 remain. #1079 (junk custom exercise from raw utterance) is
  closed-fixed; the "3x10 bench press at 135" row visible in picker is
  leftover pre-fix data, not a live bug.

- **2026-07-27 (executor #1, Sonnet):** No `planned` issue existed yet (planner
  lane hadn't caught up); per 0-RESUME-2026-07-26(a) re-audited Workout root +
  the two surfaces the operator hand-edited this week (TemplatePreviewSheet,
  ActiveWorkoutView close/finish). Fresh iPhone-vs-emulator side-by-side
  confirmed root/template-preview/active-workout structure already matches
  (corroborates scout's pass above). **Found + FIXED a real gap the scout's
  content-level pass wouldn't catch: iOS 26 draws system glass chrome (gray
  capsule behind toolbar TEXT buttons, near-white shadowed circle behind
  ICON buttons) that Drift's source never draws explicitly (bare
  `Button("Close")` / `Image(systemName: "xmark.circle")`) — Android's
  in-content header ports (#1089 pattern) rendered these as flat
  text/icon with zero chrome, looking chrome-less next to iOS.** Added
  `toolbarPillChrome()` / `toolbarCircleChrome()` to SkipUICompat.swift
  (Android-gated; circle variant avoids real `.shadow()` per #1074 — a single
  offset-fill layer, not a blur pass) and applied at the two Android-gated
  call sites (TemplatePreviewSheet's Close, ActiveWorkoutView's X/Finish) —
  the shared `closeButton`/`finishButton` properties themselves are untouched
  so iOS's real toolbar is byte-identical. Verified via rebuild + fresh
  screenshot both call sites; matches iPhone closely. iOS suite 1274 green,
  Core 2331 green, android-build-check green, `skip app launch` green both
  before/after. Independently re-derived the Apple-Health-band root cause
  (`HealthConnectService.fetchRecentWorkouts` hardcoded `{ [] }`) — matches
  the row already in this table, good corroboration. Also chased "3 of 7
  exercises show a silhouette instead of a photo in the Full Body template"
  (TRX Rows/Wrist Extension/Wrist Flexion) to ground: assets ARE bundled
  (1790/1790 synced), `registerCustomExercises()` is add-only-if-missing-by-
  name (never backfills an existing record's imageUrl), so this is the SAME
  class of stale pre-fix local dev-DB row as the scout's "3x10 bench press"
  note above, not a live code bug — leaving as-is rather than "fixing" test
  data. Residual scout-filed chrome-adjacent work still open: #1096 P0
  (MainActivity relaunch on first-set-done, needs-plan — did not attempt,
  needs real investigation into Skip's notification-permission bridge),
  #1097/#1098/#1099.

- **2026-07-27 (executor #2, Sonnet):** Claimed the Opus plan on #1096 and
  shipped it verbatim: Skip Fuse *shims* `UserNotifications`, so
  `canImport(UserNotifications)` was true on Android and the real rest-end
  notification branch (lazy `requestAuthorization`) compiled into the app —
  that lazy permission ask is what relaunched `drift.android.MainActivity`
  (harness-skip-permission-relaunches-mainactivity). Fix: two guards in
  `SharedUI/ActiveWorkoutView.swift` tightened to
  `#if canImport(UserNotifications) && !os(Android)`, routing Android to the
  pre-existing `#else` no-op stubs — a pure narrowing, iOS byte-identical.
  Verified on-device from a `pm revoke POST_NOTIFICATIONS` (notDetermined)
  state: mark set 1 done → single MainActivity (`dumpsys activity
  activities`), zero `requestAuthorization`/`UNUserNotification` in logcat,
  rest bar counts down in-sheet; Finish ~2s later opens the completion sheet
  ("Nice work!"), matching scout capture `23-finish-retry.png` — capture
  `19-finish-options.png` (misnamed; its actual content is the dumped-to-
  Today bug) never reproduced. iOS suite 1274/1274 green before commit.
  Commit f5ceecc9. Also root-caused (did not fix, out of scope for this
  plan) why the row-1 "done" toggle and "delete set" controls sit at
  adjacent-but-distinct x-ranges in the same cell (~851-917 vs ~917-1043) —
  a blind coordinate tap on the delete sub-range removed a *different* row
  than the one tapped, worth a look if #1076's set-row interaction sweep
  revisits this view (not reproduced carefully enough this session to file
  with confidence — noting as a breadcrumb, not a bug report).

  **Gap-hunt sweep (Today tab, rotated off Workout per directive 7):**
  confirmed rings/donut is `ok` — the small colored dot at each ring's 12
  o'clock position at 0% progress is CORRECT, not an Android artifact: it's
  `Circle().trim(from:0,to:0).stroke(...lineCap:.round)` drawing its round
  cap even at zero length (both iOS sim and Android emulator show the same
  dot at 0%, matching skipui-fuse-perf-facts' "Circle().trim().stroke()
  rings WORK"). Found a real, well-evidenced gap: iOS's Dashboard 3-tile
  row under the meals list is `BodySummaryCardsRow` (Drift/Views/
  BodySummaryCardsRow.swift) — ALWAYS three fixed cards, WEIGHT / SLEEP /
  READINESS, each with spec-pinned empty-state copy ("Log your weight to
  track progress" / "Connect Apple Health for sleep data" / "Connect Whoop
  or log a manual score", pinned by #821 Done-When #2). Android's row in
  the same position (confirmed via this session's own element dump: text
  "WEIGHT"/"157.9 lbs", "WORKOUTS"/"1"/"this week", "STREAK"/"3w") shows
  WEIGHT / WORKOUTS / STREAK instead — not a re-skin, a different
  component entirely; Android has no SLEEP or READINESS tile anywhere in
  this row, so a user with Health Connect sleep/HRV data would never see
  it surfaced here the way an iPhone user with HealthKit data does. Logged
  as a new `deviation` row rather than fixed (out of scope for this
  session's plan); needs #1070 (Health Connect adapter) for real data
  before a port is meaningful, but the row could ship its empty states
  today. Not filing a new issue — #1061 already scopes "unknown" Today-tab
  sub-components and is the natural owner.

## Workout (epic #1064 · single-source: SharedUI/WorkoutView.swift hosted by WorkoutTab)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Workout tab root | template grid (cards; "Show all N" affordance, caps at 5) | ok | #1095 verified non-gap: loaded 11 templates on emulator, "Show all 11" appears + expands, shared code unmodified |
| Workout tab root | streak card (conditional: current > 0) | ok | |
| Workout tab root | burn chips (active cal / steps; gated on DriftPlatform.health) | ok | |
| Workout tab root | Health Connect workouts band (fetchRecentWorkouts real data via readWorkoutsJson facade) | ok | #1095 shipped: header Android-gated to person glyph + "Health Connect" label (iOS unchanged, heart.fill + "Apple Health"); device-verified w/ seeded session (type/duration/calories correct, DESC sort) |
| Workout tab root | history collapsible + rows → WorkoutDetailView (auto-expand on save) | ok | |
| Workout tab root | history row .contextMenu (delete) — gated off in source :423; Android path = detail ⋮ menu (verified) | ios-only-by-design | |
| Workout tab root | Templates ⋮ menu (New Template / Load Packages I–IV / Remove All; Import iOS-only) | ok | |
| Workout tab root | Start Empty Workout → ActiveWorkoutView sheet | ok | |
| Workout tab root | Muscle Recovery body map + per-group chips (soreness data) | ok | |
| Workout tab root | resume banner ("Workout in progress — Resume") — renders same-process only; on-disk persistence broken | broken | #1108 |
| Workout tab root | past-workout log sheet → ActiveWorkoutView(pastDate:) w/ Jul-26 date badge; close-confirm fires | ok | save path not driven |
| Workout tab root | voice/text log sheet: typed entry → parse → review card → Log CTA (see ExerciseVoiceLogSheet rows) | ok | parse=LOCAL tier; Nebius residual 0-AI-LADDER |
| Workout tab root | scan workout sheet (`showingScan` → WorkoutScanSheet, iOS-only file; scan-primary entry REPLACED voice/text on iOS — Android still shows the legacy voice/text sheet) | missing | #1110 (#1095 closed-descoped) |
| Workout tab root | create template sheet (`showingCreateTemplate` → CreateTemplateView) | ok | |
| Workout tab root | edit template sheet (`editingTemplateForEdit`; via preview Edit, prefilled + Update CTA) | ok | |
| Workout tab root | exercise browser sheet (`showingExerciseBrowser`) | ok | |
| Workout tab root | template preview sheet (warmups, pose thumbs, rest times, start/edit/favorite/delete) | ok | |
| Workout tab root | Rename Template alert — `showingRenameAlert` set nowhere: dead code on BOTH platforms | ok | |
| Workout tab root | Delete Template alert — dead code both platforms (preview deletes immediately, same as iOS); Remove All alert reachable via ⋮ (menu verified, alert itself not driven) | ok | |
| Workout tab root | Delete Workout alert — trigger lives in the iOS-only history contextMenu; Android deletes via detail ⋮ | ios-only-by-design | |
| Workout tab root | Import alert: ⋮ Load Package I → "Added 0 Drift Package I templates" + OK (name-dedup, DB-safe) | ok | |
| ActiveWorkoutView | FIRST set-done → notif-permission moment relaunches MainActivity, dumps to Today | ok (fixed f5ceecc9) | #1096 |
| ActiveWorkoutView | close → confirmationDialog (Minimize / Discard workout / Keep going + message) | ok | |
| ActiveWorkoutView | set done ALSO pops keyboard + cursor into notes/Tip TextField (iOS is silent) | deviation | #1103 |
| ActiveWorkoutView | add exercises → ExercisePickerView sheet | ok | |
| ActiveWorkoutView | set row: decimal-pad keyboard appears, value commits | ok | |
| ActiveWorkoutView | set row: focus does NOT select-all — typing inserts (185+200 → 120085) | deviation | #1097 |
| ActiveWorkoutView | SetEntrySanity set-done dialog (operator e8821123 07-26; the driven "really heavy" = its absolute-ceiling variant). Un-driven variants share the mechanism: 3× jump-from-last (+100 lb floor), reps>100, duration>90m, "Let me fix it" cancel path; markSetDone now stable-ID (survives index shifts across the confirm round-trip) | ok | ceiling variant driven post-checkpoint (build 44) |
| ActiveWorkoutView | set row: prev-weight ghost values + prefill | ok | |
| ActiveWorkoutView | set row: done toggle ✓, per-exercise kg/lbs header menu ✓ (flip re-labels, doesn't rewrite field text — identical shared code); per-set warmup flag not driven | ok | |
| ActiveWorkoutView | rest-time chip Menu: opens w/ 6 options 0:30–3:00 | ok | chip-update after select unverified — lane collision (#1100) killed app; cheap re-check |
| ActiveWorkoutView | set done → green tint + inline rest timer countdown + coach toast | ok | |
| ActiveWorkoutView | exercise ⋮ (xmark.circle) menu: Favorite / Track by Time (drawn clock) / Remove — the Android contextMenu replacement | ok | |
| ActiveWorkoutView | command strip: tap → focus + IME with send action (parse path = Nebius residual, 0-AI-LADDER; e8821123 refinement: bare "form tips" resolves to the current exercise — Tier-0-tested, no new UI surface) | ok | |
| ActiveWorkoutView | exercise row → NavigationLink ExerciseDetailView | unknown | |
| ActiveWorkoutView | finish → options sheet (save-as-template/favorite) → completion card + share text | ok | |
| ActiveWorkoutView | mid-workout kill + resume — SavedSession NEVER persists on Android; whole workout lost on process death, both kill variants. #1102's Data→String fix landed (516f85cd) but did NOT resolve it — deeper bug, see #1108 | broken | #1108 |
| ActiveWorkoutView | resume drops Previous-column ghosts (shows "—") — re-verify after #1108 lands (process-death resume currently unreachable) | deviation | #1098 |
| ExercisePickerView | search field: autofocus, live results, tap result w/ keyboard up | ok | |
| ExercisePickerView | recent/your/all sections + last-weight decoration | ok | |
| ExercisePickerView | row .swipeActions(leading): swipe reveals Favorite, tap → Favorites section appears; Unfavorite restores | ok | star.slash→star.fill collapse noted on #1099 |
| ExercisePickerView | multi-select circles + "Add N Exercises" batch CTA | ok | |
| ExercisePickerView | custom exercise sheet: name field + Targets menu (7 parts) + Add/Cancel | ok | save-path not driven (no custom-delete API; junk-averse) |
| ExercisePickerView | "Your Exercises" carries pre-#1079 raw-utterance customs ×2; no delete path exists | deviation | #1107 |
| ExerciseBrowserView | body-part filter chips row visible + filtering (bugsweep-A FIXED) | ok | |
| ExerciseBrowserView | search field live filter (char-by-char, combined w/ chip) | ok | |
| ExerciseBrowserView | rows: pose photo thumbnails + distinct equipment glyphs | ok | |
| ExerciseBrowserView | row → NavigationLink ExerciseDetailView (works w/ keyboard up) | ok | |
| ExerciseBrowserView | custom-exercise CTA (+ top-right) sheet | unknown | |
| ExerciseDetailView | pose crossfade photos (-0/-1 HEIC animate) | ok | |
| ExerciseDetailView | muscle diagrams primary/secondary + name/level chips | ok | |
| ExerciseDetailView | equipment chip glyph = wrench for barbell (rows are correct) | deviation | #1099 |
| ExerciseDetailView | per-exercise history / PR (est. 1RM per row) | ok | |
| TemplatePreviewSheet | warmup + exercise sections, pose thumbs, per-exercise rest, notes | ok | |
| TemplatePreviewSheet | exercise rows → NavigationLink detail (crossfade, muscles, PR) | ok | |
| TemplatePreviewSheet | Start Workout / Edit / Favorite↔Unfavorite / Delete Template (immediate, no confirm — same as iOS) | ok | |
| CreateTemplateView | add exercises via picker sheet (nested sheet, multi-select, batch CTA; catalog fills async ~2-3s on emulator) | ok | |
| CreateTemplateView | per-exercise sets Stepper bounds (+/- work, floor clamps at 1) | ok | |
| CreateTemplateView | edit-exercise sheet: sets stepper, Rest dropdown 0:15–3:00, warmup toggle → WARMUP section round-trip, Track-by, notes, Remove | ok | |
| WorkoutDetailView | header stats + set rows w/ per-set 1RM | ok | |
| WorkoutDetailView | ⋮ menu: Share / Edit Name & Notes / Save as Template / Delete | ok | |
| WorkoutDetailView | set row .swipeActions(trailing) delete | unknown | |
| WorkoutDetailView | Edit Set (iOS alert / Android sheet stand-in) | unknown | |
| WorkoutDetailView | menu actions drive-through (rename/delete/save/share sheets) | unknown | |
| ExerciseVoiceLogSheet | typed parse → review: "3x10 bench press at 135" → canonical Bench Press card (#1079 re-verified live) | ok | parse=LOCAL tier; Nebius wiring residual (0-AI-LADDER) |
| ExerciseVoiceLogSheet | resolve-target: unmatched name → "Not in library — tap to pick" → full picker → select+Add applies name to row | ok | |
| ExerciseVoiceLogSheet | Cancel keeps parsed session — reopen resumes stale review, exercises accumulate (iOS resets) | deviation | #1106 |
| BodyMapView (recovery) | muscle figure colored by soreness (front+back render) | ok | |
| BodyMapView (recovery) | tap muscle → suggested recovery template | unknown | |
| MuscleHighlightCard | only render site is ExerciseDetailView muscle diagrams (device-verified ok above); "per-workout" premise stale | ok | source-resolved |

## Food (epic #1062 · single-source: SharedUI/FoodTabView.swift hosted by FoodTab)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Food tab root | date strip + Select Date calendar sheet (`showingDatePicker`, logged-dots) — compiled-in (shared, os(Android) branches :410) | unknown | needs drive |
| Food tab root | macro rings / donut summary | unknown | |
| Food tab root | meal timeline sections + entry rows | unknown | |
| Food tab root | entry row edit sheet (`editingEntry` → EditFoodEntrySheet — SharedUI, compiled both; beware stale SharedUICopy dupe, #1071) | unknown | needs drive |
| Food tab root | serving stepper in edit sheet | unknown | |
| Food tab root | add-food search sheet — **Android stand-in `AndroidFoodSearchSheet`, iOS FoodSearchView NOT ported** | deviation | #1062 |
| Food tab root | barcode scanner fullScreenCover (`showingScanner`) | missing | #1063 |
| Food tab root | recipe builder sheet — DRIFT_IOS_APP-gated :204, no Android trigger exists in source | missing | #1062 |
| Food tab root | combos sheet ("···" entry iOS-gated :787) + combo log sheet (`comboToLog` iOS-gated :210; Android combo chips log DIRECTLY w/ toast undo — documented interim :753) | missing | #1062 |
| Food tab root | goal setup sheet (`showingGoalSetup`) — sheet + BOTH macro-card tap affordances iOS-gated (:600/:612); gates flip in the GoalSetupView port | missing | #1117 (was #1067) |
| Food tab root | plant points detail sheet — static row renders on Android (LeafShape stand-in), tap + chevron iOS-gated :634-641 | missing | #1062 |
| Food tab root | confirm-log sheet (`showingConfirmLog`) — only trigger is the iOS-only contextMenu "Log Again" :1115 | missing | #1062 |
| Food tab root | suggestion chips: iOS → FoodLogSheet/ComboLogSheet review; Android quick-logs DIRECTLY + toast undo (deliberate interim :753-781) — quick-log write needs drive | deviation | #1062 |
| Food tab root | entry-row contextMenu (Edit/Favorite/Log Again/Copy-to-Today/Move) — Darwin-only by house rule, equivalents mapped (Edit=row tap, Delete=✕, Favorite/Copy=edit sheet); Log Again + Move Up/Down have NO Android path | deviation | #1062 |
| Food tab root | Snap shortcut (safeAreaInset camera.viewfinder → PhotoLog) — DRIFT_IOS_APP :128-156 | missing | #1063 |
| FoodSearchView (iOS) | search-first UX, sections, manual entry, recipe edit/rebuild sheets | missing | #1062 |
| QuickAddView | ingredient picker + manual ingredient sheets | missing | #1062 |
| CombosView | combo CRUD + log sheets + alerts — iOS-target file (Drift/Views/Food/), no Android entry | missing | #1062 |
| MealReviewSheet / PhotoLogReviewView | editable review (all logging funnels through it on iOS) | missing | #1063 |
| VoiceLogSheet (food) | voice food logging | missing | #1063 |
| ManualFoodEntrySheet | manual macro entry — iOS-target file (Drift/Views/Food/) | missing | #1062 |
| LogMealSheet | meal logging sheet — iOS-target file (Drift/Views/Food/) | missing | #1062 |

## Today (epic #1061 = INDEX · Android-only re-creation: TodayTab.swift 410 ln vs iOS DashboardView.swift + DashboardView+Cards.swift · scoped ports #1129–#1132)

Source-enumerated 2026-07-28 (scout #7): full iOS→Android structural diff, no emulator
(both sibling lanes live). Rows ordered top→bottom matching iOS `DashboardView.body`.
Data classified DriftCore-portable-NOW vs health-seam-gated (#1070). Android correctly
HIDES health sections (no fake zeros, [[android_hide_unwired_integration_ui]]) rather than
render them empty — those stay `missing`→#1070, not new ports. Shared components all live
in iOS-only `Drift/Views/` (LogMethodCardsRow, BodySummaryCardsRow, MealTimelineSection,
V6CoachingNudge, WorkoutConsistencyCard, GoalProgressCard, TodayDonutView, V6Rings).

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Chrome | brand header: iOS = `BrandMark` **asset** in the **nav toolbar** (principal); Android draws a "D" **circle IN scroll content** — wrong element AND wrong placement | deviation | #1121/dir-8 |
| Chrome | privacy banner — Android `lock.fill` vs iOS `lock.shield.fill`; Android adds a trailing Spacer (iOS is leading-aligned) | deviation | #1061 |
| Chrome | pull-to-refresh (`.refreshable`) — Android TodayTab has none | deviation | #1061 |
| Chrome | 180s auto-refresh poll — Android reloads on `.foodEntryAdded` + onAppear instead (acceptable interim) | ok | #1061 |
| Banners | profile-incomplete nudge → ProfileView ("Add age, sex & height…") — Android none | missing | #1116 |
| Banners | 7-day feedback banner (#759, days 7–14 → More/Report-a-bug; xmark dismiss) — Android none | missing | #1114 |
| Banners | stale-backup banner (#561, >3d → Backup settings sheet) — Android none | missing | #1094 |
| Nutrition hero | iOS `calorieBalanceCard` = `TodayDonutView` (goal path) + no-goal fallback (eaten + P/C/F/Fiber chips); Android `intakeCard` re-creates 3 concentric rings + legend but is ALWAYS ring-mode (no no-goal fallback) | deviation | #1061 |
| Nutrition hero | skeleton while loading (`SkeletonCalorieBalanceCard`) — Android has no skeleton (shared TodayStore mitigates the cold "0 kcal" flash, #1075) | deviation | #1075 |
| Log methods | iOS `LogMethodCardsRow` = Snap · **Voice** · Search · Recent; Android = Snap · **Describe** · Search · Recent (Voice→text substitute) | deviation | #1126 |
| Log methods | **Snap chip**: iOS opens photo capture; Android's camera-glyph chip opens **Coach chat** (`showingCoachInfo`→AIChatView) — no capture, misleading glyph | deviation | #1063/#1128 |
| Log methods | Describe / Search / Recent chips wired (was `broken` #1093, now CLOSED) → DescribeMealSheet / AndroidFoodSearchSheet / AndroidRecentMealsSheet | ok | #1093 (closed) |
| Meal timeline | iOS `MealTimelineSection` = dot-rail + **swipe-to-delete** (`onDelete`) + `onAdd` nudge; Android `mealsCard` = flat list, **NO delete** (can't remove a mis-log from Today), empty→Food tab | deviation | #1131 |
| Meal timeline | skeleton while loading (`SkeletonMealTimelineSection`) — Android none | deviation | #1075 |
| Body summary row | iOS `BodySummaryCardsRow` = WEIGHT / **SLEEP / READINESS** (goal-aware WEIGHT, spec empty states #821); Android `statTrio` = WEIGHT / **WORKOUTS / STREAK** (SLEEP+READINESS dropped — health-gated; workout cols are a DriftCore substitute) | deviation | #1070 |
| Coaching nudge | iOS `V6CoachingNudge` (topmost proactiveAlert, Ask-AI pill, 24h dismiss; `BehaviorInsightService` = DriftCore) — Android none | missing | #1130 |
| Behavior insights | iOS `insightsCard` (BehaviorInsight list under "Insights") — Android none | missing | #1130 |
| Goal progress | iOS `goalCard` (`GoalProgressCard` → GoalView) / empty "No weight goal set" — Android none (statTrio has WEIGHT value only, no progress card) | missing | #1117 |
| Daily Average (TDEE) | iOS `tdeeCard` (eating/deficit/burning ring, target line, source pills, explainer → AlgorithmSettings) — Android none; all DriftCore, portable NOW | missing | #1129 |
| Activity section | iOS "Activity" header + `healthRow` (Active cal / Steps → Exercise tab) — Android hides (HealthKit seam) | missing | #1070 |
| Activity | iOS Apple-Health `workoutCard` (burned N cal, ≤3 workouts) when today workouts exist — Android none (HealthKit seam) | missing | #1070 |
| Activity | iOS `WorkoutConsistencyCard` (weekly, 24h dismiss; `BehaviorInsightService.workoutConsistencyVariant` + WorkoutService = DriftCore, NOT health-gated) — Android none | missing | #1132 |
| Recovery section | iOS "Recovery" header + `sleepRecoveryCard` (Recovery/Sleep scores, HRV/RHR, → SleepRecoveryView) / empty "Body Rhythm" — Android none (sleep/HRV/RHR = HealthKit seam) | missing | #1070/#1061 |
| Recovery | iOS `supplementCard` (N/M taken → SupplementsTabView) when supplements configured — Android none (Supplements TAB is ported #1068; dashboard entry not) | missing | #1061 |
| Coach entry | floating `ChatIconButton` → AIChatView — PORTED (AppShell.swift + ContentView.swift), matches iOS single AI access point | ok | #1066 |

## Body / Weight (epic #1065 · Android-only re-creation: WeightTab.swift)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Body tab | whole screen is a re-creation, not iOS WeightTabView port | deviation | #1065 |
| Body tab | Log Weight save button | broken | #1091 |
| Body tab | weight chart (WeightChartView parity) | missing | #1092 |
| Body tab | insights: body fat / BMI / water chart sheets | missing | #1065 |
| Body tab | add body-comp sheet (BodyCompEntryView) | missing | #1065 |
| Body tab | entry edit sheet + log list (WeightLogListView) | unknown | #1065 |
| Body summary cards row | summary cards | unknown | #1065 |
| DEXA overview | DEXAOverviewView + detail | missing | #1069 |
| Progress photos | gallery / viewer overlays / timer camera / add entry — Android-only re-creation `ProgressGalleryAndroid.swift` EXISTS + wired (`MoreTab.swift:147`), NOT the SharedUI ProgressGalleryView port; viewer/timer-camera/add-entry parity unverified (source-only session) | deviation | #1069 |

## More / Settings (epic #1067 = INDEX · Android stub: MoreTab.swift 90 lines vs iOS ~3.5k-line tree · scoped ports #1114–#1119)

Source-enumerated 2026-07-27 (scout #5); `missing` rows are source-verified (no Android
route exists), not emulator-driven. Persistence acceptance on every ported control
inherits #1108. KEY POLICY (0-AI-FOCUS): no key-entry UI of any kind ships on Android.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| More hub (MoreTabView :4-193) | hub layout: HEALTH/APP sections, navRow chrome (36pt icon tile, subtitle, chevron, contentShape), inline title | missing | #1114 |
| More hub | HEALTH rows ×7: Body Rhythm→SleepRecoveryView, Cycle→CycleView (conditional `hasCycleData` via health seam), Supplements, Body Composition→DEXAOverviewView, Progress Photos→ProgressGalleryView, Glucose, Biomarkers — destinations: Supplements + Progress Photos now LANDED (wired in Android More stub TRACKING section, `MoreTab.swift:146-147`); remaining dests #1122 (Biomarkers) / #1123 (Glucose) / #1124 (Cycle) / #1069 (Body Comp) / #1061 (Body Rhythm). Full-hub port keeps rows HIDDEN until each dest lands (no dead taps, #1093) | missing | #1114 |
| More hub | APP row Profile → ProfileView | missing | #1114/#1116 |
| More hub | APP row Weight Goal → GoalView | missing | #1114/#1117 |
| More hub | APP row "Bring Your Own Key" → PhotoLogSettingsView — `#if !os(Android)`, no replacement row | ios-only-by-design | KEY POLICY |
| More hub | APP row Settings → SettingsView | missing | #1114/#1115 |
| More hub | footer: "Report a bug" external Link + version line (Android keeps build stamp, gated) | missing | #1114 |
| More hub | pop-to-root on tab reselect (`navId` reset via selectedTab onChange) | missing | #1114 |
| More hub (stub today) | PREFERENCES weight-unit picker — live on Android; iOS home is Settings→UNITS (stub order lbs,kg vs iOS kg,lbs) | deviation | #1115 |
| More hub (stub today) | HEALTH CONNECT connect/sync card — live; iOS equivalent is Settings→HEALTH SOURCES with status text | deviation | #1115/#1070 |
| More hub (stub today) | privacy blurb + "coming to Android" list — Android-only interim, retires with hub port | deviation | #1114 |
| SettingsView (:195-898) | UNITS: Body Weight Unit segmented kg/lbs + "exercise weights stay in lbs" caption | missing | #1115 |
| SettingsView | HEALTH SOURCES: "Sync from Apple Health" one-action full resync + body-comp import + 3s status line (HC wording on Android, #1095 header precedent) | missing | #1115/#1070 |
| SettingsView | HEALTH SOURCES: Write Nutrition toggle (#934; foreign-app-detect / auth-denied / unavailable states, auto-disable reason line) — needs HC WRITE; hidden until seam grows writes | missing | #1115/#1070 |
| SettingsView | HEALTH SOURCES: "Sync Past Data…" confirmationDialog (30/90/all, skip-foreign-days) — write-gated, same hiding | missing | #1115/#1070 |
| SettingsView | iCloud Backup NavigationLink row — Android backup screen is #1094/#1109's deliverable; row hidden until it exists | missing | #1094/#1109 |
| SettingsView | DATA: Export Workouts CSV + Export Food Logs CSV (DriftCore-built CSV; UIActivityViewController → Android share seam, coordinate w/ #1109 SAF bridge) | missing | #1115 |
| SettingsView | PRIVACY: Online Food Search toggle + conditional "only search terms sent" caption | missing | #1115 |
| SettingsView | PRIVACY: WebSearchSettingsCard — Google key+cx / Brave key fields, expand/collapse, active-provider line: pure key-entry UI; Android web_search runs keyless/provisioned tier with NO settings surface | ios-only-by-design | KEY POLICY |
| SettingsView | PRIVACY: Usage Insights row → UsageInsightsView (counter rows, ShareLink export, Reset counts, empty state; FeatureUsage = DriftCore) | missing | #1115 |
| SettingsView | NOTIFICATIONS row → NotificationsSettingsView; hidden until #1119 lands | missing | #1115/#1119 |
| SettingsView | ADVANCED: AI Chat Telemetry card — staged-intent toggle (enable-confirm alert, revert-on-cancel binding :548-562), delete-confirm alert, turns count, Export JSON, Delete all (ChatTelemetryService = DriftCore) | missing | #1115 |
| SettingsView | ADVANCED: telemetry "View insights" → AIChatInsightsView (iOS-target file) — link hidden on Android until an AI-insights port exists | missing | #1115 (hide) |
| SettingsView | ADVANCED: Algorithm row → AlgorithmSettingsView | missing | #1115/#1118 |
| SettingsView | ADVANCED: Refresh food database button (idle / refreshing / refreshed-N / failed states, 0-count = real error) | missing | #1115 |
| SettingsView | Danger Zone: Factory Reset + destructive confirm alert + Reset Complete alert (AppDatabase.factoryReset + UserDefaults key sweep — #1108 interaction) | missing | #1115 |
| NotificationsSettingsView (:910-1025) | 4 toggle cards: Health Nudges / Smart Meal (+ conditional "Use my eating patterns" sub-toggle) / Medication Dose / GLP-1 Weekly — setters write DriftCore Preferences then NotificationService.refreshScheduledAlerts() (iOS-only service) | missing | #1119 |
| Android notification seam | DriftPlatform.notifications-shaped seam: channels model, explicit POST_NOTIFICATIONS flow (#1096: Skip's UserNotifications shim must NEVER compile in; no lazy permission asks) | missing | #1119 |
| ProfileView (GoalView+Profile :43-327) | sex segmented Male/Female/N-A — N/A sets `sexUndisclosed`, counts complete, auto-fill never overwrites it | missing | #1116 |
| ProfileView | age range menu picker (Not set + 6 ranges → midpoint) | missing | #1116 |
| ProfileView | height cm↔ft/in segmented mode switch; 1 vs 2 numberPad fields, 50–300cm clamp, silent save | missing | #1116 |
| ProfileView | weight decimal field: unit flip mid-edit reconverts via TEXT as source of truth; commit on FOCUS LOSS → real WeightEntry + trend refresh (Android IME commit trigger must be defined; #1097 select-all remedy applies) | missing | #1116 |
| ProfileView | "Changes save automatically" / Saved flash; health auto-fill on appear when incomplete | missing | #1116 |
| GoalView (GoalView.swift, Chart-free) | profile card row w/ completeness badge (check vs "Improve accuracy") | missing | #1117 |
| GoalView | GoalProgressCard + Update Goal → GoalSetupView sheet | missing | #1117 |
| GoalView | macro-target pills (kcal/P/C/F) + derivation explanation line + fat-minimum note | missing | #1117 |
| GoalView | Pace (required vs actual, on-track status color) / Daily Target deficit pair (goal-aware sign-based color) / Projection (early / behind / on-schedule / wrong-direction states) | missing | #1117 |
| GoalView | Clear Goal + empty state ("No Goal Set" + Set Weight Goal prominent CTA); custom back chevron | missing | #1117 |
| GoalSetupView (sheet, iOS Form) | target weight decimal + kg/lbs segmented; Diet Style radio list (DietPreference cases + subtitles) | missing | #1117 |
| GoalSetupView | custom-macros section (3 numberPad gram fields; footer auto-computes blanks within calorie target; fat-clamp warning) | missing | #1117 |
| GoalSetupView | Calorie Target field w/ 1200 floor (red footer + Save disabled) OR implied-kcal readout when all 3 macros set | missing | #1117 |
| GoalSetupView | Timeline stepper 1–24 months + live "This means:" projection (auto + macro-vs-TDEE variants, exceeds/below warnings, >1000 kcal "Aggressive" note) | missing | #1117 |
| GoalSetupView | Save validation (no parseable target = disabled) + "Log your current weight first" alert; edit mode prefills all fields | missing | #1117 |
| AlgorithmSettingsView (478) | TDEE hero (live cachedOrSync) + target/goal context + Required-vs-Current pair; "Set goal" NavigationLink fallback | missing | #1118 |
| AlgorithmSettingsView | accordion (one-open): Activity slider 22–36 + Reset-to-29; Profile sex/age/height fields (auto-expand while editing); Fine-tune slider ±500 step 25 + Reset — Slider-on-Fuse fidelity is a named plan question | missing | #1118 |
| AlgorithmSettingsView | Advanced disclosure: active-source chips + AH resting/active/steps line (hide when seam nil — no fake zeros); Estimation Style presets ×3 (config-equality detection); How-it-works rows; conditional Reset All | missing | #1118 |
| BackupSettingsView (228) | auto-backup toggle + last-backed-up line, Back Up Now w/ live phase text, Restore picker entry, "What's in my backup?" disclosure, iCloud-unavailable alert — iCloud substrate is Apple-only; Android substrate = #1094/#1109 (SAF) | missing | #1094/#1109 |
| RestorePickerView (163) | backup list, destructive restore confirm, atomic restore + relaunch prompt, empty/loading states | missing | #1094/#1109 |
| BackupOnboardingSheet (115) | app-level onboarding prompt (trigger: DriftApp.swift:67 → Android trigger would live in DriftAndroidApp) | missing | #1094 |
| PhotoLogSettingsView (323) | ENTIRE screen — provider picker, model picker, SecureField key entry + Paste/Save/Replace/Clear, Keychain storage, Test Connection ping: all key management. Android photo AI = provisioned Nebius (#1111) + local Google tier | ios-only-by-design | KEY POLICY |
| Health Connect | connection flow + permission grant | confirmed missing: `onLaunch()` calls `requestAuthorization()` silently, no settings-hub entry, sync failures swallowed by `try?` — worse than iOS's explicit "Sync from Apple Health" button + status text + past-sync dialog | #1070/#1090 |

## Coach / AI chat (epic #1066 · iOS-only: Drift/Views/AI/**)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Coach chat | full chat UI (bubbles, input bar, streaming) | unknown | #1066 |
| Coach chat | tool cards, clarification card, insights | missing | #1066 |
| Coach chat | food search / workout / barcode / recipe / manual / review sheets from chat | missing | #1066 |
| Coach chat | voice talk-mode (ImmersiveVoiceView, ListeningCircle) | missing | #1066 |
| Coach entry points | dashboard + tab entries open real chat (not teaser) | unknown | #1066 |

## Capture (epic #1063 · iOS-only: Drift/Views/PhotoLog/**, BarcodeScannerView)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Photo log | capture view (camera, settings, barcode sheets) | missing | #1063 |
| Photo log | flow + review (PhotoLogFlowView/PhotoLogReviewView) | missing | #1063 |
| Barcode scanner | scan → food match → log | missing | #1063 |
| Workout scan | photo/PDF → template or session (WorkoutScanSheet + ReviewView) | missing | #1110 (#1095 closed-descoped; #1063 shares the camera seam) |

## Health sub-screens (epic #1068 = INDEX · iOS-only: Drift/Views/{Biomarkers,Glucose,Cycle}/** · scoped ports #1122–#1124)

Source-enumerated 2026-07-28 (scout #6). All data/logic services are DriftCore (portable, views
only render): `BiomarkerService`, `GlucoseService`, `CycleCalculations`, `BiomarkerKnowledgeBase`,
`BiomarkerInsights`, `AIScreenTracker`, `SupplementService`. Three recurring seams: (1) `import Charts`
+ `Canvas` are **Skip-absent** → Path port, precedent `WeightChartAndroid.swift` / `TodayDonutView`
trim-rings; (2) `fileImporter`/`UniformTypeIdentifiers` → Android SAF (#1109); (3) HealthKit reads →
Health Connect (#1070). **No Android UI route exists** for Biomarkers/Glucose/Cycle (verified: only
`HealthConnectService` stubs + seed `biomarkers.json`); honest interim placeholder present (`MoreTab`
"COMING TO ANDROID": "Sleep, cycle & biomarkers detail screens") so no dead taps (#1093). **Supplements
is DONE** — ported to SharedUI, wired `MoreTab.swift:146`; removed from the port queue.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Biomarkers tab (BiomarkersTabView 513) | empty state (cross.case.fill + Upload CTA) | missing | #1122 |
| Biomarkers tab | status **donut** (`DonutRing`=`Canvas` arc → trim/stroke Path port) + optimal/sufficient/out-of-range legend + last-updated | missing | #1122 |
| Biomarkers tab | PATTERNS cards (`BiomarkerInsights.patterns` — DriftCore; iron/metabolic/thyroid/lipid/inflammation) | missing | #1122 |
| Biomarkers tab | LAB REPORTS list → NavigationLink LabReportDetailView | missing | #1122 |
| Biomarkers tab | search field (live filter name/category) + filter chips (All / Out of Range / Sufficient / Optimal) | missing | #1122 |
| Biomarkers tab | grouped biomarker list (status sections) → NavigationLink BiomarkerDetailView; row = value + status badge + AI-parsed badge + `RangeBar` (GeometryReader — per-scroll recompose, keep cheap) | missing | #1122 |
| Biomarkers tab | toolbar Upload → .sheet LabReportUploadView | missing | #1122 |
| LabReportUploadView (325) | `.fileImporter([.pdf])` → `LabReportOCR.extract(fromPDF:)` (iOS Vision/PDFKit) → preview → Save (`BiomarkerService.save*`, DriftCore). Android = SAF PDF pick (#1109) + Nebius parse (0-AI-LADDER) + local Google tier; NO key UI | missing | #1122 (seam #1109/#1070-adj) |
| BiomarkerDetailView (567) | trend `Chart` (LineMark history — Skip-absent, Path port) + all-recordings list + impact categories/knowledge | missing | #1122 |
| LabReportDetailView (190) | results list + **Delete Report** destructive `.alert` → `BiomarkerService.deleteLabReport` + `LabReportStorage.delete` | missing | #1122 |
| Glucose tab (GlucoseTabView 517) | source Picker (Apple Health / Imported; AH→"Health Connect" on Android per #1095) | missing | #1123 |
| Glucose tab | range chips 1D / 3D / 1W / 2W / 1M / All | missing | #1123 |
| Glucose tab | empty state (waveform.path.ecg; source-specific copy) | missing | #1123 |
| Glucose tab | **glucose Chart**: zone RectangleMarks (70-100 / 100-140 / 140-200) + zone-colored LineMark + spike/dip PointMarks + horizontal ScrollView (Skip-absent → Path port; `UIScreen.main` width iOS-gate) | missing | #1123 |
| Glucose tab | stats card (Average / Range / In Zone) + Fasting/Fat-Burning analysis + Glucose Events (spikes/dips) — all DriftCore logic | missing | #1123 |
| Glucose tab | toolbar Import → `.fileImporter([.csv,.txt])` → `GlucoseService.importLingoCSV` (DriftCore); Android = SAF CSV pick (#1109) | missing | #1123 |
| Glucose tab | Apple Health source → `DriftPlatform.health.fetchGlucoseReadings` — `HealthConnectService` returns [] today | missing | #1123 (dep #1070) |
| Cycle (CycleView 647) | hero/summary (Day N, phase, last/avg/next period) | missing | #1124 |
| Cycle | phase timeline bar (GeometryReader segments + fertile overlay + position dot) + phase labels | missing | #1124 |
| Cycle | Body Signals `Chart` (HRV/RHR multi-series LineMark, catmullRom — Skip-absent, Path port) | missing | #1124 |
| Cycle | Cycle Length trend `Chart` (BarMark + 28-day RuleMark + annotations — Skip-absent, bar port) | missing | #1124 |
| Cycle | Recent Periods history + Advanced Insights `Toggle` (→ `Preferences.cycleFertileWindow`) + fertile-window card + privacy note | missing | #1124 |
| Cycle | ALL data via `DriftPlatform.health` (cycle/ovulation/BBT/spotting/HRV/RHR/sleep) — `HealthConnectService` implements NONE; **empty-state-only until #1070 grows cycle reads** | missing | #1124 (HARD dep #1070) |
| Supplements (SharedUI/SupplementsTabView) | tab + add/edit/delete + adherence bars — **PORTED** (SharedUICopy + `MoreTab.swift:146` sheet) | ok | #1121 (source-confirmed; device-verify pending uncontended window) |

## App shell

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Tab bar | 5 tabs, pill highlight, food glyph reads fork-knife (cart FIXED) | ok | |
| Navigation | push/sheet transition speed + font stability | deviation | #1074 |
| Theme | dark/light, goal-aware green/red, Material accent leak | unknown | |
