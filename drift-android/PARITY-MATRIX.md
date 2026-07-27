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
| Workout tab root | resume banner ("Workout in progress — Resume") — renders same-process only; on-disk persistence broken | ok | #1102 |
| Workout tab root | past-workout log sheet → ActiveWorkoutView(pastDate:) w/ Jul-26 date badge; close-confirm fires | ok | save path not driven |
| Workout tab root | voice/text log sheet: typed entry → parse → review card → Log CTA (see ExerciseVoiceLogSheet rows) | ok | parse=LOCAL tier; Nebius residual 0-AI-LADDER |
| Workout tab root | scan workout sheet (`showingScan` → WorkoutScanSheet, iOS-only file) | missing | #1095 |
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
| ActiveWorkoutView | implausible-weight confirmation dialog ("really heavy") | ok | |
| ActiveWorkoutView | set row: prev-weight ghost values + prefill | ok | |
| ActiveWorkoutView | set row: done toggle ✓, per-exercise kg/lbs header menu ✓ (flip re-labels, doesn't rewrite field text — identical shared code); per-set warmup flag not driven | ok | |
| ActiveWorkoutView | rest-time chip Menu: opens w/ 6 options 0:30–3:00 | ok | chip-update after select unverified — lane collision (#1100) killed app; cheap re-check |
| ActiveWorkoutView | set done → green tint + inline rest timer countdown + coach toast | ok | |
| ActiveWorkoutView | exercise ⋮ (xmark.circle) menu: Favorite / Track by Time (drawn clock) / Remove — the Android contextMenu replacement | ok | |
| ActiveWorkoutView | command strip: tap → focus + IME with send action (parse path = Nebius residual, 0-AI-LADDER) | ok | |
| ActiveWorkoutView | exercise row → NavigationLink ExerciseDetailView | unknown | |
| ActiveWorkoutView | finish → options sheet (save-as-template/favorite) → completion card + share text | ok | |
| ActiveWorkoutView | mid-workout kill + resume — SavedSession NEVER persists on Android (UserDefaults Data write dropped by Skip bridge); whole workout lost on process death, both kill variants | broken | #1102 |
| ActiveWorkoutView | resume drops Previous-column ghosts (shows "—") — re-verify after #1102 lands (process-death resume currently unreachable) | deviation | #1098 |
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
| Food tab root | date strip + Select Date calendar sheet (`showingDatePicker`, logged-dots) | unknown | |
| Food tab root | macro rings / donut summary | unknown | |
| Food tab root | meal timeline sections + entry rows | unknown | |
| Food tab root | entry row edit sheet (`editingEntry` → EditFoodEntrySheet) | unknown | |
| Food tab root | serving stepper in edit sheet | unknown | |
| Food tab root | add-food search sheet — **Android stand-in `AndroidFoodSearchSheet`, iOS FoodSearchView NOT ported** | deviation | #1062 |
| Food tab root | barcode scanner fullScreenCover (`showingScanner`) | missing | #1063 |
| Food tab root | recipe builder sheet | unknown | |
| Food tab root | combos sheet + combo log sheet (`comboToLog`) | unknown | |
| Food tab root | goal setup sheet (`showingGoalSetup`) | unknown | |
| Food tab root | plant points detail sheet | unknown | |
| Food tab root | confirm-log sheet (`showingConfirmLog`) | unknown | |
| Food tab root | suggestion chips → `suggestionFoodToLog` sheet | unknown | |
| FoodSearchView (iOS) | search-first UX, sections, manual entry, recipe edit/rebuild sheets | missing | #1062 |
| QuickAddView | ingredient picker + manual ingredient sheets | missing | #1062 |
| CombosView | combo CRUD + log sheets + alerts | unknown | |
| MealReviewSheet / PhotoLogReviewView | editable review (all logging funnels through it on iOS) | missing | #1063 |
| VoiceLogSheet (food) | voice food logging | missing | #1063 |
| ManualFoodEntrySheet | manual macro entry | unknown | |
| LogMealSheet | meal logging sheet | unknown | |

## Today (epic #1061 · Android-only re-creation: TodayTab.swift — NOT the iOS DashboardView)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Dashboard | whole screen is a re-creation, not iOS DashboardView port | deviation | #1061 |
| Dashboard | quick actions: Describe / Search / Recent / Snap | broken | #1093 |
| Dashboard | rings/donut (TodayDonutView, V6Rings) | ok | #1061 |
| Dashboard | coaching cards (CoachingBriefCard, V6CoachingNudge) | unknown | #1061 |
| Dashboard | sleep/recovery card (SleepRecoveryView, full NavigationLink row) | unknown | #1061 |
| Dashboard | workout consistency card (WorkoutConsistencyCard) | unknown | #1061 |
| Dashboard | 3-tile summary row (BodySummaryCardsRow: WEIGHT/SLEEP/READINESS, spec-pinned empty states #821) | deviation | #1061 |
| Dashboard | backup settings sheet | missing | #1094 |
| Dashboard | brand mark header still a drawn "D" circle (BrandMark asset not mirrored) | deviation | directive 8 |

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
| Progress photos | gallery / viewer overlays / timer camera / add entry | missing | #1069 |

## More / Settings (epic #1067 · Android-only re-creation: MoreTab.swift, 63 lines vs iOS hub)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| More tab | settings hub rows (iOS MoreTabView) | deviation | #1067 |
| More tab | goal setup / GoalView + profile | missing | #1067 |
| More tab | algorithm settings | missing | #1067 |
| More tab | backup/restore (BackupSettingsView, RestorePickerView, onboarding sheet) | missing | #1094 |
| More tab | photo-log settings | missing | #1067 |
| More tab | web search settings card | missing | #1067 |
| More tab | Apple-Health sync dialog (→ Health Connect equivalent) | missing | #1070 |
| Health Connect | connection flow + permission grant | unknown | #1070/#1090 |

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
| Workout scan | photo/PDF → template or session (WorkoutScanSheet + ReviewView) | missing | #1095 |

## Health sub-screens (epic #1068 · iOS-only)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Biomarkers | tab, detail, lab report upload/detail | missing | #1068 |
| Glucose | GlucoseTabView | missing | #1068 |
| Cycle | CycleView | missing | #1068 |
| Supplements | tab + add/edit sheets | missing | #1068 |

## App shell

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Tab bar | 5 tabs, pill highlight, food glyph reads fork-knife (cart FIXED) | ok | |
| Navigation | push/sheet transition speed + font stability | deviation | #1074 |
| Theme | dark/light, goal-aware green/red, Material accent leak | unknown | |
