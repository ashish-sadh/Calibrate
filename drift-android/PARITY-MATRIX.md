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

- **2026-08-03 (scout #14, Opus 5):** **BODY COMPOSITION (#1069)** — the coarsest node left on the
  board, and the one scout #12 named as remaining. It was two matrix rows standing in for ~1,750 lines
  of iOS source across 6 files (`Drift/Views/BodyComposition/**`), and — the finding that mattered most —
  **#1069 carried only the `android-parity` label, no `needs-plan`, so the planner lane could not see it
  at all.** An entire feature area was invisible to the pipeline. Now decomposed into 7 scoped children
  on the #1114–#1119 / #1142–#1145 pattern. **Cost-changing structural finding:** the whole DEXA +
  measurement-analysis data layer is *already in DriftCore and compiles for Android today*
  (`Models/DEXAScan`, `Models/DEXARegion`, `Domain/Health/DEXAService`, `BodyCompositionAnalysis`,
  `BodyMeasurementAnalysis`, and `AppDatabase.fetchProgressEntries()` public at
  `AppDatabase+Progress.swift:113`) — #1185 and #1189 are pure view ports with zero seam work; only PDF
  import (#1191) is genuinely blocked (PDFKit is iOS-only *and* it needs the #1175 file-in seam).
  **Device window opened mid-session** (executor's `xcodebuild test` finished, emulator-5554 came up) so
  the 5-session device-verify debt was partly discharged — first scout device drive since #12. Confirmed
  on build 79: the progress-photo thumbnail is a **DEAD TAP** (screen pixel-identical before/after —
  #1187, the whole viewer/compare payoff surface is unreachable), cards render **raw ISO `2026-07-30`**
  instead of `Jul 30, 2026`, no weight, no measurement line, a single lonely thumb instead of 4 pose
  slots, `lock.fill` for `lock.shield.fill`, bare `+` for `plus.circle.fill`. Zero crashes across the
  drive (0-NO-CRASH clean); emulator restored to the More tab as found. **Device-only find** the source
  sweep would have missed: the More tab's "COMING TO ANDROID" card is a hardcoded string array
  advertising **already-shipped** Coach chat and photo logging as unshipped — a floating Coach button
  sits one card below the text saying Coach is coming (#1192). Rows changed: **27** (2 coarse rows →
  25 enumerated across two new sub-sections + 1 More row + section header). Issues filed: **8** (#1185
  DEXA screen+manual entry, #1186 P1 gallery data defects, #1187 P1 dead-tap viewer, #1188 gallery
  structure, #1189 Trends sheet, #1190 DEXA charts, #1191 blocked PDF import, #1192 stale COMING card) —
  at budget, all `needs-plan`. #1069 commented as an INDEX with a suggested sequencing. No code touched
  (matrix only). **Residual device debt:** the ≥2-entry states (timeline scrubber, Compare/Trends row)
  and the metric-unit + measurement-only-entry cases in #1186 need seeded fixtures — Android has no UI
  to create them until #1166.

- **2026-08-03 (executor, Sonnet), #1111:** Shipped Snap meal photo logging shell — completed WIP inherited from an earlier watchdog-restarted executor session on this same ticket (`NebiusMealPhotoLogger.swift` + Tier-0 tests + `CameraCaptureFacade.kt` + manifest/`Main.kt` wiring were already present, uncommitted). Added: FileProvider `<provider>` block + `res/xml/file_paths.xml` (was MISSING — `CameraCaptureFacade.launch()` would have crashed with `IllegalArgumentException` on the first "Take Photo" tap, never previously exercised), `CameraCaptureService.swift` (Swift-side facade wrapper mirroring `ImagePickerService.swift`, handles the permission-request→poll→launch→poll→result state machine), `SnapMealSheet.swift` (capture/analyzing/review/error phases, mirrors `DescribeMealSheet`'s review-row style verbatim rather than extracting a shared `MealReviewList` per the plan's speculative File #6 — only 2 occurrences, CLAUDE.md's anti-premature-abstraction tenet, and LAUNCH HARDENING's "no speculative refactors" all argue against touching the already-shipped Describe sheet), `PhotoStackShape` drawn glyph (skip-ui has zero `photo.*`/gallery/album SF Symbol mappings at all — checked `composeSymbolName` directly), `TelemetrySurface.snapMeal` constant, TodayTab wiring (Snap chip now opens the real sheet; the `showingCoachInfo`/`AIChatView` placeholder it used to open is DELETED — was 100% dead after the repoint, Coach remains reachable via the floating `ChatIconButton` in `ContentView.swift`). Both capture paths device-verified working end-to-end THROUGH TO THE CLOUD CALL: camera permission prompt → grant → system camera → confirm → app resume (no crash, no duplicate-MainActivity); gallery picker → pick → app resume. 5 rapid background/foreground cycles clean, zero crashes, zero ANRs (0-NO-CRASH). Tier-0 8/8 new + 2686/2686 total green; `android-build-check.sh` green; full iOS suite 1274/1274 green (DriftCore touch is ADD-ONLY, zero iOS behavior change).
  **RESIDUAL — blocks the happy path, filed as #1177 (P1, needs-plan):** the cloud vision round-trip itself returns HTTP 200 with only the first (empty, role-announcement) SSE chunk — 4105 bytes, byte-identical size across two completely different test images — before the connection is cut, so `NebiusMealPhotoLogger.parse` always resolves to nil and the error screen fires (verified working: clean UI, Retry + Retake, no crash). Isolated via a temporary debug capture (added, verified, then fully reverted — `git diff --stat` on the two touched shared files is empty) that a control test (Describe, text-only, same buffered Android transport) succeeds end-to-end on the same build/device, so this is specific to the (slower-to-first-token) vision-call shape, not a general network/config/throttle failure — likely the buffered-path sibling of the exact "idle connection gets reaped" failure class #1133's own code comments already document for the streaming path. Needs real architectural investigation (real-device confirmation beyond the emulator, possibly a `stream:false` request for the buffered path or an OkHttp-Kotlin-facade transport mirroring #1136) — out of scope for a bounded executor session, filed `needs-plan`. Also affects Workout Scan (#1110) once its photo path is device-tested — same shared `RemoteLLMBackend` transport.
  Build: verified via `skip app launch --android` (not yet published — see next session note for the publish outcome). #1100 (Stop-hook lane-scoped skip) also closed this session: fix had already landed (`ff33e89c`) but the issue was never closed — re-verified with a proper decoy-process test (my own self-test hit the documented pgrep ancestor-exclusion caveat) rather than re-implementing.

- **2026-08-03 (scout, Opus):** IMAGE-IN / CAPTURE reconciliation (executor `/android-parity` PID 7297
  Sonnet + planner PID 7330 LIVE on emulator-5554 → Android UNTOUCHED per the scout-#3 collision lesson;
  iPhone sim was uncontended but this was a source + issue-state sweep, no device drive needed). Trigger:
  6 days since scout #12 (2026-07-28) — verify-don't-trust against live `gh`. **Headline: #1128 (image-in
  seam) CLOSED 2026-07-31 (`9aff629f`)** — shipped `DriftPlatform.imagePicker.pickLibraryImage()`
  (`DriftCore/.../Adapters/ImagePicking.swift`), registered on Android (`DriftAndroidApp.swift:53`), wired
  into exactly ONE consumer so far (`ProgressGalleryAndroid.swift:84`). Crucial shape: the seam is
  **photo-LIBRARY only, NOT live camera** — it unblocks Snap-from-library / WorkoutScan-image / Coach
  photo-attach, while barcode + live PhotoLog capture still need a SEPARATE camera seam. This invalidated
  the "blocked on #1128" premise the matrix cited across Food/Today/Coach/Capture + the
  [[project_android_image_in_seam_blocker]] memory (updated this session). **Actions:** (1) filed **#1174
  P1** — Coach input-bar photo-attach, a genuine tracking hole: the `AIChatView+InputBar.swift:121-142`
  comment forward-references #1125 for "photo attach", but **#1125's filed scope is cards + interview
  only** (verified in its body) and #1111 is the Food-tab Snap (a different surface) — so photo-in-chat
  was owned by no issue; now buildable on the landed seam. (2) Refreshed **#1110** (Workout Scan): removed
  stale `blocked` (its #1128 blocker landed → image path buildable now; PDF still #1109-SAF-gated) +
  commented the per-path nuance ([[harness_stale_blocked_label]]). (3) Added a matrix row for **#1137**
  (Coach send button = DEAD TAP, only IME enter sends — `broken`; the old Input-bar row wrongly implied
  "send" worked). Rows changed: **9** (Capture ×4 refined; Coach input-bar repointed #1125→#1174 + NEW
  #1137 send-button row; Food barcode + Snap ×2; Today Snap chip; Progress-photos add-entry; Nav font
  #1165). Issues filed: **1** (#1174). Issues refreshed: **1** (#1110 `blocked` cleared). No code touched
  (matrix only); tree clean, publish lane's `Skip.env` untouched. Confirmed `3b0946cb`'s dashboard
  meal-remove is **iOS-only** (`Drift/Views/MealTimelineSection.swift`) — does NOT close Android #1131;
  iOS pulled slightly further ahead. Device-verify debt unchanged (emulator contended, 4th+ consecutive
  scout) — next uncontended window: the library-seam consumers (#1174/#1111 once built) + the standing
  Food/Coach/Weight `unknown` rows.

- **2026-07-28 (executor, Sonnet), #1100:** Executed #1100's plan exactly: `.claude/hooks/ensure-clean-state.sh`
  now skips the dirty/untracked-file gate for `DRIFT_PARITY_LANE` ∈ {scout, planner} Stop-hook runs when
  `pgrep -f 'android-parity --dangerously'` finds a live executor sibling (the UNPUSHED gate is byte-identical,
  untouched); all three parity watchdogs (`android-parity-watchdog.sh`/`-planner-watchdog.sh`/`-scout-watchdog.sh`)
  now export their own `DRIFT_PARITY_LANE` right after `DRIFT_AUTONOMOUS=1`. Verified all 5 branches with a
  spawned decoy process standing in for "executor sibling live" (see caveat below — NOT this session's own
  PID): `DRIFT_PARITY_LANE=planner`/`scout` + decoy alive → rc=0 (skip fires); `=executor` and no-lane-var
  (iOS autopilot) + decoy alive → rc=2 (full gate kept, unchanged); `planner` with NO decoy alive → rc=2
  (skip does NOT fire when no executor is genuinely live — not a blanket bypass). Discriminator regex
  confirmed via two backgrounded decoys to match an `/android-parity` process and reject an
  `/android-parity-scout` one. **CAVEAT discovered while testing** (also recorded on the scout-deadlock
  memory): macOS `pgrep -f` silently excludes ANY ancestor of the *calling* process from its match set — this
  session's own executor PID (my direct parent, confirmed via `ps -p $PPID`) was invisible to a `pgrep` run
  from a child shell, which would have produced a false-negative on the discriminator test had I not swapped
  to a genuine backgrounded decoy. Irrelevant to production (scout/planner/executor are independent sibling
  process trees spawned by separate watchdogs — never ancestors of each other) but a real trap for future
  self-testing. No Swift/SharedUI/DriftCore touched (infra-only: 2 hook/watchdog dirs + this note), so no
  Android/iOS build or test run required per the plan; `bash -n` clean on all four scripts. Operator must
  restart the three parity watchdogs for the new `export`s to take effect — not done by this session.

- **2026-07-28 (scout #12):** DEVICE-REFERENCE sweep of **Workout** (operator directive 0-SCREEN-BY-SCREEN-WORKOUT).
  ps-check: executor `/android-parity` (PID 62401, Sonnet) LIVE and parked on the ExerciseVoiceLogSheet on
  emulator-5554 device-verifying its own fresh #1106 fix (e979e2c5 / row-487 flip 58a33c43) → the Android emulator
  was left UNTOUCHED per the scout-#3 collision lesson. (adb quirk resolved for the record: the working adb is the
  homebrew one at `/opt/homebrew/bin/adb`; `~/Library/Android/sdk/platform-tools/adb` does NOT exist here — my first
  probes silently no-op'd on the wrong path and looked like a mid-reinstall stall, it wasn't.) iOS control = PAUSE
  (misfiring hook, reads the iOS file only) but `~/drift-android-parity.txt` = RUN → proceeded. **Method:** drove the
  iPhone 17 Pro sim (516EAAC8, uncontended by the Android executor) to capture FRESH references (operator's
  stale-reference concern per 0-RESUME) for 5 workout surfaces — ExerciseDetailView (pose photo + front/back muscle
  diagrams + Chest/barbell/Intermediate chips + primary/secondary), ExerciseBrowserView ("Exercise Database":
  Done + red "+" custom-CTA + search + All/Chest/Back/Legs/Shoulders/Arms/Core chips + pose-thumb rows with red
  muscle-figure + distinct equipment glyphs Barbell/Bands↔/Machine⚙/Dumbbell), Workout root (Start Workout / Coach Me,
  "Scan or Log a Workout" scan-primary card, Log Past Workout, Templates ⋮, Browse Exercises 950+, burn chips, Apple
  Health band, Muscle Recovery), ActiveWorkoutView empty (close-X, title+date+timer, Add Exercise, command strip),
  and the close-confirm dialog (Minimize — resume anytime / Discard workout). **Cross-checked every visible iPhone
  element against the matrix: workout is SATURATED — all tracked as `ok` or an already-filed gap; ZERO new gaps**
  (consistent with scout #11's exhausted source audit). **Verify-don't-trust reconciliation** of all 12 workout-cited
  issues vs live `gh`: fully consistent — #1095/#1096/#1097/#1099/#1102/#1103/#1106/#1108 CLOSED, #1098/#1100/#1107/#1110
  OPEN, every row matches. Noted #1127 (user-facing custom-exercise delete, `needs-fable`, carved from #1107) now
  tracks the delete affordance referenced by the "custom exercise sheet" / "Your Exercises" rows (#1107). Rows changed:
  **0** (executor already flipped #1106 → row 487). Issues filed: **0** (quality>volume — no un-tracked gap exists).
  No code touched (matrix note only); publish-lane `Skip.env` + graphify dirty files left alone. **Device-verify debt**
  (emulator contended for the 3rd+ consecutive scout): the `unknown` rows — ActiveWorkout exercise-row→ExerciseDetail
  nav, ExerciseBrowser custom-CTA sheet, WorkoutDetail swipe-delete / Edit-Set / menu-drive-through — PLUS the
  device-reverify-pending flips (#1103 IME-focus, #1097 numeric select-all). MITIGATION: the EXECUTOR lane is actively
  discharging device-verification (device-verified #1106 + #1102 + #1098 + BodyMap in recent commits), so this debt is
  being worked, not stuck. Next scout: do NOT re-sweep workout source (saturated) — either grab an UNCONTENDED emulator
  window for the `unknown` device-verifies, or rotate to a less-covered area (capture #1063 / DEXA+photos #1069 /
  Supplements remain the coarsest).

- **2026-07-28 (executor, Sonnet):** Executed the `planned` #1106 issue exactly per
  its Opus plan: `SharedUI/ExerciseVoiceLogSheet.swift` `.onDisappear` (line 66) now
  also calls `viewModel.reset()` + clears `draft`/`resolveTarget`, ungated (no-op on
  iOS since its content view + `@State` die on dismiss regardless). New Tier-1
  `DriftTests/ExerciseVoiceLogViewModelTests.swift` pins `reset()` completeness.
  Both builds green (iOS `xcodebuild build` + Android `skip app launch`), full
  iOS suite 1470/1470 passed (verified via `xcresulttool`, not just exit code —
  the tail-piped log truncated the XCTest-style section). Emulator-drove all 7
  plan verification steps + 3 regression guards: fresh reopen after Cancel, no
  accumulation across a second parse, resolve-picker does NOT wipe the
  in-progress session (highest-risk regression, confirmed safe), swipe-to-dismiss
  reopen is fresh, unsubmitted draft clears. Row 459 flipped `deviation`→`ok`.
  Zero crashes/ANRs across the drive + 5 rapid background/foreground cycles.
  Issue closed. **Publish blocked**: `android-publish.sh` failed twice at "Archive
  iOS ipa" with exit 9 (SIGKILL, 2.5s then 45.8s in, zero `.swift error:` lines in
  either export log — matches the known release-archive-OOM signature, not a code
  issue). Killed a stale leftover `xcodebuild test` process and retried once with
  ~2x the free memory (590MB→1.1GB) — still died; stopped retrying per that
  playbook rather than thrash. `Skip.env` reverted both times, no stray
  versionCode bump landed. **Next session should publish first thing** — this fix
  is on `main` (e979e2c5), just not yet on a Play build. Gap-hunt sweep (Today
  tab, rotated off Workout): posted fresh iPhone-vs-Android evidence to #1061 —
  confirms #1129 (Daily Average/Activity/Recovery block, entirely missing on
  Android) and #1130 (proactive "Food logging paused → Ask AI" nudge card,
  missing) with concrete screenshots, plus the still-outstanding directive-8
  brand-mark gap (Android's header still draws the "D" circle stand-in, not the
  real `BrandMark` asset). No new issue filed — existing ones cover it precisely.

- **2026-07-28 (scout #11):** SOURCE-ONLY staleness reconciliation of **Workout** (epic #1064) — operator directive
  0-SCREEN-BY-SCREEN-WORKOUT area. ps-check found BOTH sibling lanes LIVE (executor `/android-parity` PID 19839 Sonnet,
  `.build/skip-export` touched 13:43 = actively building→installing the APK; planner PID 87150 Opus) so the emulator was
  left UNTOUCHED per the scout-#3 collision lesson. iOS control file = PAUSE (the misfiring P0-#1043 + "PAUSE ACTIVE"
  hooks read the iOS control only) but `~/drift-android-parity.txt` = **RUN** → proceeded. **Verify-don't-trust
  staleness sweep:** cross-checked all 68 issue refs in the matrix against live `gh` state — 13 CLOSED. Workout rows
  citing now-closed issues (confirmed closing commits present) FLIPPED: **row 375** resume-banner persistence
  `broken`→`ok` (#1108 f39655f3 durable SQLite KV store), **row 389** set-done IME-focus-theft `deviation`→`ok`
  (#1103 aab2e238), **row 392** numeric select-all `deviation`→`ok` (#1097 066c91bc), **row 402** mid-workout
  process-death session-loss `broken`→`ok` (#1108 f39655f3 — the P0), **row 417** equipment glyph `deviation`→`ok`
  (#1099 f899db8e). The four runtime-behavioral flips (focus/persistence are RUNTIME facts per [Port Kit Stale On
  Wiring Not UI]) are tagged **device-reverify-pending** (emulator contended, not confirmed on-device this session).
  **row 403** (resume drops Previous ghosts, #1098) — blocker #1108 LANDED so the resume path is fully REPLACED +
  now reachable; premise may be stale → left `deviation`, and refreshed #1098: removed its stale `blocked` label
  ([Stale Blocked Label]) + commented it needs a DEVICE re-verify (not planning — the code path it was filed against
  no longer exists). **Source-audit (directive 0 "no ⚠️ triangles"):** read all 114 platform gates + every raw
  `Image(systemName:)` across the 8 workout SharedUI files — glyph parity is CLEAN: every delta is `sym()`-mapped,
  drawn as a custom Shape behind `#if os(Android)` (Dumbbell/Flame/Clock/BarChart), or a deliberate closest-icon;
  ZERO un-handled triangle candidates (the raw literals at WorkoutView 615/624/780/806/985 are the iOS `#else` side
  of handled pairs; `bottomInset` 100-vs-24 is the intentional floating-pill-tab-bar inset). Rows changed: **6**
  (5 flips + 1 note). Issues filed: **0** (no new gaps — quality>volume). Issues refreshed: **1** (#1098 blocked
  cleared). No code touched (matrix only); publish lane's uncommitted `Skip.env` left alone. **Device-verify debt
  handed to the next uncontended scout window:** the 6 `unknown` workout rows — row 400 (ActiveWorkout
  exercise-row→ExerciseDetail nav), 414 (ExerciseBrowser custom-CTA sheet), 427 (WorkoutDetail swipe-delete), 428
  (WorkoutDetail Edit-Set sheet), 429 (WorkoutDetail menu drive-through), 434 (BodyMap tap→recovery-template) — PLUS
  on-device re-confirm of the 5 flips above + #1098's ghost-drop premise on the new keyValueStore resume path.

- **2026-07-28 (scout #10):** SOURCE-ONLY decomposition of **Body / Weight** (epic #1065) — the last coarse
  un-decomposed domain (Today/Food/More/Coach/Health already split by scouts #5-#9). ps-check found BOTH sibling
  lanes live (executor `/android-parity` PID 23525 + planner PID 23540, Opus) and emulator-5554 up but UNTOUCHED
  per the scout-#3 collision lesson (executor reinstalls the APK mid-drive → phantom app-died). Full diff of iOS
  `WeightTabView.swift` (422 ln) + its 6 sub-views (WeightInsightsView 619 / WeightEntryView 127 / WeightLogListView
  154 / BodyCompEntryView 106 / WeightChartView 379 / BodySummaryCardsRow 307) vs Android `WeightTab.swift` (325 ln)
  + `WeightChartAndroid.swift` (269). **Staleness corrections (verify, don't trust the matrix):** `broken #1091`
  (Log Weight save) and `missing #1092` (weight chart) are BOTH **STALE** — #1091 + #1092 are CLOSED; save now
  validates in-action (not `.disabled`, a Fuse-reactivity fix) and `WeightChartAndroid` (Path-based, Charts absent
  on Skip) is wired → flipped both to `ok`. The "Body summary cards row" was **MISFILED** under #1065 —
  `BodySummaryCardsRow` is mounted in `DashboardView` (Today), NOT the Weight tab → reclassified to #1061. **#1065
  demoted to INDEX**, split into 4 scoped `needs-plan` children: **#1142** WeightInsightsView analytics port
  (body-comp cards → metric trend sheets, weekday pattern, weight-changes sparklines — Android has only a thin
  stats header) / **#1143** body-comp entry (Android AddWeightSheet is weight-only; NO body-comp path exists at
  all) / **#1144** edit-a-weigh-in + >10% outlier banner (Android history rows are delete-only, no correction path;
  planner note: iOS exposes Edit via `.contextMenu` which is ABSENT on SkipUI + steals TextField focus → use
  tap-to-edit) / **#1145** residual affordances (Daily/Weekly granularity, collapsible history, milestone
  celebration + haptic, empty state — AH-sync stays hidden till the health seam). All four are DriftCore-portable —
  no health seam, no camera/cloud (unlike #1069 DEXA + progress photos, left un-decomposed this session: capture is
  seam-blocked per the image-in blocker; ProgressGalleryAndroid re-creation already wired). Rows changed:
  Body/Weight 9-coarse → 17-granular. Issues filed: **4** (#1142-#1145). No code touched (matrix only); worker WIP
  + the publish lane's uncommitted `Skip.env` build-63 bump left alone. Device-verify debt grows by the WHOLE Weight
  tab (source-verified only, emulator contended) — still awaiting an uncontended window alongside Food shared
  surfaces + Coach source-rows + scout #3's 5 workout leftovers + Supplements.

- **2026-07-28 (scout #9):** SOURCE-ONLY decomposition of **Food** (epic #1062) — ps-check found BOTH
  sibling lanes live (executor `/android-parity` PID 23525 Sonnet + planner PID 23540 Opus); `adb` showed
  emulator-5554 up but it was left UNTOUCHED per the scout-#3 collision lesson (executor reinstalls the APK
  mid-drive → phantom app-died). Area: Food was the last coarse un-decomposed mega-epic (Today/More/Health/
  Coach already split by scouts #5-#8), is #2 on the operator's 0-AI-FOCUS queue, and its split also unblocks
  Coach **#1135**. Grep-verified all 10 iOS-only `Drift/Views/Food/**` files (FoodSearchView 49KB, QuickAddView
  36KB, CombosView, ComboLogSheet, ManualFoodEntrySheet, FoodLogSheet, LogMealSheet, PlantPointsCardView,
  ServingMultiplierStepper, VoiceLogSheet) have **ZERO** Android presence; Android ships thin stand-ins
  (`FoodTab.swift` AndroidFoodSearchSheet:39 / AndroidRecentMealsSheet:198) + the shared FoodTabView with every
  create/build/combo/goal/confirm path `#if DRIFT_IOS_APP`-gated. **#1062 demoted to INDEX**; split into 4
  scoped children (mirroring #1067→#1114-1119): **#1138** Food Search hub port (FoodSearchView → replace the
  AndroidFoodSearchSheet stand-in; 6 sections + per-result log; #1075 tracks the stand-in returns-nothing
  break) / **#1139** Quick Add + manual entry + recipe builder (no Android manual-add path today) / **#1140**
  Combos & Recipes hub (CombosView + ComboLogSheet CRUD; Android chips log directly, no editor) / **#1141**
  residual iOS-gated affordances (Plant Points expandable detail + "Log Again"). **Staleness corrections
  (verify, don't trust the matrix):** shared FoodTabView surfaces (date strip/rings/timeline/edit/serving)
  are DEVICE-VERIFY DEBT — they compile via the ported ServingInputView/EditFoodEntrySheet/MealCalendarPicker,
  NOT `missing`; the edit-entry row flipped `unknown`→`broken` **#1120** (cal/macro override fields dead to
  tap). Capture rows stay #1063, Snap→#1111, goal→#1117. Rows changed: Food 22-coarse → 25-granular. Issues
  filed: **4** (#1138-#1141). No code touched (matrix only); worker WIP left alone. Device-verify debt grows
  (Food shared surfaces + scout #8's Coach source-rows + scout #3's 5 workout leftovers + Supplements) — all
  awaiting an uncontended emulator window.

- **2026-07-28 (scout #8):** SOURCE-ONLY reconciliation of **Coach / AI chat** (epic #1066) — ps-check found
  BOTH sibling lanes live (executor PID 97569 + planner PID 94850, Opus) and `adb devices` empty, so the
  emulator was untouched per the scout-#3 collision lesson. Area chosen because the matrix said "iOS-only"
  but commit **b8c244a6 shipped the Coach TEXT chat to SharedUI** (#1066) — a stale section on the operator's
  0-AI-FOCUS priority queue. Full diff of `SharedUI/AIChatView*.swift` (+ViewModel +MessageHandling 2024 ln)
  vs the 8 iOS-only `Drift/Views/AI/**` files: **5 coarse rows → 21 granular rows**, ordered to match `body`.
  Reality: the DriftCore message harness runs on Android so DETERMINISTIC tools WORK (weight/activity logs,
  workout start+templates, delete-food, **navigation** — `.navigateToTab` posts immediately, tab-switch works,
  queries) — flipped those rows `ok`/`deviation`. Four gap-classes, all already tracked except one: **(a)** all
  13 tool-result cards are `#if DRIFT_IOS_APP`, text-summary-only on Android → **#1125**; **(b)** every food-logging
  tool DEGRADES to "add it from the Food tab for now" (single-food `handleSingleFoodIntent`→showingFoodSearch,
  usual-meal→showingMealReview, meal-plan, manual, barcode) → filed **#1135** (the one uncovered operator-priority
  gap — food-via-text is the marquee AI interaction; #1063 is capture not chat; precedent `DescribeMealSheet`
  already ported de-risks it); **(c)** voice/mic/talk-mode shimmed off (`CoachVoiceShims`) → **#1126**; **(d)**
  open-ended cloud-LLM turns HANG on "Looking that up…" (streaming buffered `#else` branch) → **#1133** (already
  filed+diagnosed). Interview ("set me up") `#if DRIFT_IOS_APP` → #1125. BackendSelector/AISetup/AIChooser =
  key-UI (#540), marked **ios-only-by-design** (Nebius-only, no key UI per 0-AI-FOCUS); AIChatInsightsView (#261
  local telemetry) + DriftCoachSheet picker-wrapper likewise ios-only-by-design. **#1066 demoted to INDEX**
  (children #1125/#1126/#1133/#1135). Rows changed: 5→21 (Coach section). Issues filed: **1** (#1135). No code
  touched (matrix only); worker WIP left alone. Device-verify debt grows by the Coach rows (source-verified,
  not driven) — still awaiting an uncontended emulator window alongside the food compiled-shared rows + scout
  #3's 5 workout leftovers + Supplements.

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
| Workout tab root | resume banner ("Workout in progress — Resume") — on-disk persistence FIXED via durable SQLite KV store | ok | #1108 closed f39655f3; device-verified both variants (#1102 closed, executor session 2026-07-28) |
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
| ActiveWorkoutView | set done pops keyboard into notes/Tip TextField — FIXED: tap-to-edit, set-DONE no longer steals IME focus | ok | #1103 closed aab2e238; device-reverify pending (runtime focus; scout #11) |
| ActiveWorkoutView | add exercises → ExercisePickerView sheet | ok | |
| ActiveWorkoutView | set row: decimal-pad keyboard appears, value commits | ok | |
| ActiveWorkoutView | set row: focus select-all — FIXED, typing replaces not inserts | ok | #1097 closed 066c91bc; device-reverify pending (runtime; scout #11) |
| ActiveWorkoutView | SetEntrySanity set-done dialog (operator e8821123 07-26; the driven "really heavy" = its absolute-ceiling variant). Un-driven variants share the mechanism: 3× jump-from-last (+100 lb floor), reps>100, duration>90m, "Let me fix it" cancel path; markSetDone now stable-ID (survives index shifts across the confirm round-trip) | ok | ceiling variant driven post-checkpoint (build 44) |
| ActiveWorkoutView | set row: prev-weight ghost values + prefill | ok | |
| ActiveWorkoutView | set row: done toggle ✓, per-exercise kg/lbs header menu ✓ (flip re-labels, doesn't rewrite field text — identical shared code); per-set warmup flag not driven | ok | |
| ActiveWorkoutView | rest-time chip Menu: opens w/ 6 options 0:30–3:00 | ok | chip-update after select unverified — lane collision (#1100) killed app; cheap re-check |
| ActiveWorkoutView | set done → green tint + inline rest timer countdown + coach toast | ok | |
| ActiveWorkoutView | exercise ⋮ (xmark.circle) menu: Favorite / Track by Time (drawn clock) / Remove — the Android contextMenu replacement | ok | |
| ActiveWorkoutView | command strip: tap → focus + IME with send action (parse path = Nebius residual, 0-AI-LADDER; e8821123 refinement: bare "form tips" resolves to the current exercise — Tier-0-tested, no new UI surface) | ok | |
| ActiveWorkoutView | exercise row → NavigationLink ExerciseDetailView | unknown | |
| ActiveWorkoutView | finish → options sheet (save-as-template/favorite) → completion card + share text | ok | |
| ActiveWorkoutView | mid-workout kill + resume — FIXED: SavedSession persists via durable SQLite KV store, survives process death (both kill variants) | ok | #1102 CLOSED — device-verified Variant A (30s tick, no backgrounding) + Variant B (HOME then force-stop): both show Resume banner, restore exercise/set/done-state/timer, and clearSession works on Finish + Cancel (executor session 2026-07-28) |
| ActiveWorkoutView | resume drops Previous-column ghosts (shows "—") — CONFIRMED still reproduces on the new keyValueStore resume path (not stale): pre-interrupt Previous showed "185 lbs × 12", post-resume reads "—" | deviation | #1098 device re-verify done (executor session 2026-07-28), ready for planning |
| ExercisePickerView | search field: autofocus, live results, tap result w/ keyboard up | ok | |
| ExercisePickerView | recent/your/all sections + last-weight decoration | ok | |
| ExercisePickerView | row .swipeActions(leading): swipe reveals Favorite, tap → Favorites section appears; Unfavorite restores | ok | star.slash→star.fill collapse noted on #1099 |
| ExercisePickerView | multi-select circles + "Add N Exercises" batch CTA | ok | |
| ExercisePickerView | custom exercise sheet: name field + Targets menu (7 parts) + Add/Cancel | ok | save-path not driven (no custom-delete API; junk-averse) |
| ExercisePickerView | "Your Exercises" carries pre-#1079 raw-utterance customs ×2; no delete path exists | ok | FIXED a8a62339 (#1107 CLOSED): run-once launch prune (`ExerciseDatabase.pruneLegacyUtteranceCustoms`, history-guarded so referenced names survive) wired on both platforms via the durable KV seam (#1108); device-verified the run-once flag persists across real Android process death, not just the Tier-0 simulation. User-facing delete UI still carved to #1127 |
| ExerciseBrowserView | body-part filter chips row visible + filtering (bugsweep-A FIXED) | ok | |
| ExerciseBrowserView | search field live filter (char-by-char, combined w/ chip) | ok | |
| ExerciseBrowserView | rows: pose photo thumbnails + distinct equipment glyphs | ok | |
| ExerciseBrowserView | row → NavigationLink ExerciseDetailView (works w/ keyboard up) | ok | |
| ExerciseBrowserView | custom-exercise CTA (+ top-right) sheet | unknown | |
| ExerciseDetailView | pose crossfade photos (-0/-1 HEIC animate) | ok | |
| ExerciseDetailView | muscle diagrams primary/secondary + name/level chips | ok | |
| ExerciseDetailView | equipment chip glyph — FIXED to match browser rows | ok | #1099 closed f899db8e; source-verified (sym map + shape) |
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
| ExerciseVoiceLogSheet | Cancel keeps parsed session — reopen resumes stale review, exercises accumulate (iOS resets) | ok | FIXED e979e2c5 (build 65, #1106 closed): `.onDisappear` now also calls `viewModel.reset()` + clears `draft`/`resolveTarget`, ungated (no-op on iOS). Device-verified: fresh reopen after Cancel, no accumulation across a second utterance, resolve-picker does NOT wipe the in-progress session, swipe-to-dismiss reopen is fresh, unsubmitted draft clears. New Tier-1 `ExerciseVoiceLogViewModelTests`; iOS suite 1470/1470 green |
| BodyMapView (recovery) | muscle figure colored by soreness (front+back render) | ok | |
| BodyMapView (recovery) | tap muscle → suggested recovery template | ok | device-verified (executor session 2026-07-28): tapping an under-trained chip (e.g. "Chest, 8d ago") expands an inline "haven't trained X in over a week" note + tappable template quick-starts (Start Push Day/Full Body/P5 Day 2/4); tapping a suggestion opens the real template pre-loaded with its warmup+working-set structure |
| MuscleHighlightCard | only render site is ExerciseDetailView muscle diagrams (device-verified ok above); "per-workout" premise stale | ok | source-resolved |

## Food (epic #1062 = INDEX · single-source: SharedUI/FoodTabView.swift hosted by FoodTab + Android stand-ins AndroidFoodSearchSheet/AndroidRecentMealsSheet · scoped ports #1138 search-hub / #1139 quick-add+manual / #1140 combos+recipes / #1141 residual affordances; capture #1063, goal #1117, edit-bug #1120)

Source-decomposed 2026-07-28 (scout #9): #1062 was a coarse mega-epic; split into 4 scoped children
mirroring #1067→#1114-1119. All 10 iOS-only food files (`Drift/Views/Food/**`: FoodSearchView 49KB,
QuickAddView 36KB, CombosView, ComboLogSheet, ManualFoodEntrySheet, FoodLogSheet, LogMealSheet,
PlantPointsCardView, ServingMultiplierStepper, VoiceLogSheet) have ZERO Android presence (grep-verified);
Android ships thin stand-ins (`FoodTab.swift` AndroidFoodSearchSheet:39 / AndroidRecentMealsSheet:198) +
the shared FoodTabView with every create/build/combo/goal/confirm path `#if DRIFT_IOS_APP`-gated. SHARED
FoodTabView surfaces (date strip, rings, timeline, edit sheet, serving input) compile on Android via the
ported ServingInputView/EditFoodEntrySheet/MealCalendarPicker/MealTimePicker/FoodLogViewModel/DescribeMealSheet
— those rows stay `unknown` = DEVICE-VERIFY DEBT (both sibling lanes live this session, emulator untouched
per the scout-#3 collision lesson).

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Food tab root | date strip + Select Date calendar sheet (`showingDatePicker`, logged-dots) — SHARED (MealCalendarPicker ported, os(Android) branches :410) | unknown | device-verify debt |
| Food tab root | macro rings / donut summary — SHARED FoodTabView | unknown | device-verify debt |
| Food tab root | meal timeline sections + entry rows — SHARED FoodTabView | unknown | device-verify debt |
| Food tab root | entry row edit sheet (`editingEntry` → EditFoodEntrySheet, SharedUI ported; beware stale SharedUICopy dupe #1071) — cal/macro OVERRIDE fields reported dead to tap | broken | #1120 |
| Food tab root | serving input in edit sheet (ServingInputView ported) | unknown | device-verify debt |
| Food tab root | add-food search sheet — Android stand-in `AndroidFoodSearchSheet` (FoodTab.swift:39); iOS FoodSearchView (49KB, 6 sections + 7 sub-sheets) NOT ported; #1075 = stand-in returns-nothing break | deviation | #1138 |
| Food tab root | recipe builder sheet (`showingRecipeBuilder` DRIFT_IOS_APP :203) → QuickAddView — no Android trigger | missing | #1139 |
| Food tab root | manual food entry (`showingManual` → ManualFoodEntrySheet) — no Android manual-add path at all | missing | #1139 |
| Food tab root | combos sheet (`showingCombos` iOS-gated :207/:787) + combo log sheet (`comboToLog` :210) → CombosView/ComboLogSheet; Android combo chips log DIRECTLY w/ toast undo (interim :753) | missing | #1140 |
| Food tab root | goal setup sheet (`showingGoalSetup`) — sheet + BOTH macro-card tap affordances iOS-gated (:600/:612); gates flip in the GoalSetupView port | missing | #1117 |
| Food tab root | plant points detail — static LeafShape row renders on Android; tap + expandable list iOS-gated :634-641 | missing | #1141 |
| Food tab root | confirm-log sheet (`showingConfirmLog` :237) — only trigger is the iOS-only contextMenu "Log Again" :1115 | missing | #1141 |
| Food tab root | barcode scanner fullScreenCover (`showingScanner` :165) — inherently LIVE-camera (AVFoundation); the landed #1128 seam is photo-library-ONLY, does NOT cover barcode → still needs a camera seam | missing | #1063 (live-camera seam pending) |
| Food tab root | Snap shortcut (safeAreaInset camera.viewfinder → PhotoLog) — DRIFT_IOS_APP :128-156; Food-tab entry point still not ported (Today's chip is the only Snap entry on Android) | missing | #1111 (Today chip shipped; Food-tab entry unclaimed) |
| Food tab root | suggestion chips: iOS → FoodLogSheet/ComboLogSheet review; Android quick-logs DIRECTLY + toast undo (deliberate interim :753-781) — quick-log write needs drive | deviation | #1140/#1138 |
| Food tab root | entry-row contextMenu (Edit/Favorite/Log Again/Copy/Move) — Darwin-only by house rule; Edit=row tap, Delete=✕, Favorite/Copy=edit sheet mapped; Log Again + Move Up/Down have NO Android path | deviation | #1141 |
| FoodSearchView (iOS 49KB) | search-first UX: query + RECENT/COMBOS/FAVORITES/FREQUENT/YOUR FOODS/POPULAR sections, per-result FoodLogSheet, favorite swipe, recent 1-tap re-log | missing | #1138 |
| FoodLogSheet / LogMealSheet | single-food + meal log sheets (serving + meal-type + Log; FAB "Log a meal" #1038) — funnel of the search hub | missing | #1138 |
| QuickAddView (iOS 36KB) | ingredient picker + IngredientPickerView manual fields + servings + expandOnLog aggregate-vs-individual + save-as-recipe | missing | #1139 |
| ManualFoodEntrySheet | manual macro entry (name/cal/P/C/F/fiber/serving) — iOS-target file | missing | #1139 |
| CombosView + ComboLogSheet | combo/recipe CRUD (list, delete-swipe, Build→QuickAdd, per-item log sheet w/ servings) — iOS-target files, no Android entry | missing | #1140 |
| PlantPointsCardView | plant-diversity card + expandable plant list — iOS-target file | missing | #1141 |
| MealReviewSheet / PhotoLogReviewView | editable review (all photo/capture logging funnels through it on iOS) | missing | #1063 |
| VoiceLogSheet (food) | voice food logging (speech→parse→review) — blocked on Android speech seam | missing | #1063 (#1126 seam) |

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
| Log methods | **Snap chip**: opens `SnapMealSheet` (#1111, 2026-08-03) — Take Photo (new `CameraCaptureFacade`/`CameraCaptureService`) + Choose from Library (`DriftPlatform.imagePicker`, #1128) both capture correctly and reach the review UI shell; the cloud vision round-trip itself is currently BROKEN (#1177 — buffered Android transport truncates every photo response to the first empty SSE chunk, HTTP 200, no error) so the happy path (real food detection) cannot complete on-device yet. Error+Retry state verified working (graceful, no crash). No longer opens Coach chat (that misrouted placeholder is gone). | broken | #1111 (mechanics shipped) / #1177 (blocks happy path) |
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

## Body / Weight (epic #1065 = INDEX · Android-only re-creation: WeightTab.swift 325 ln vs iOS WeightTabView.swift 422 ln + 6 sub-views · scoped ports #1142 insights / #1143 body-comp-entry / #1144 edit+outlier / #1145 residual · DEXA+photos → #1069 = INDEX, decomposed 2026-08-03 into #1185 DEXA screen / #1190 DEXA charts / #1191 DEXA PDF-import / #1186 gallery data defects / #1187 viewer / #1188 gallery structure / #1189 Trends sheet, plus existing #1166 capture · source-verified 2026-07-28, device-verify debt)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Weight tab | overall structure — Android WeightTab re-creation, not the iOS WeightTabView single-source port | deviation | #1065 |
| Weight tab | weight chart (WeightChartAndroid, Path-based — Charts absent on Skip) | ok | #1092 |
| Weight tab | Log Weight save (validates in-action, not `.disabled`) | ok | #1091 |
| Weight tab | time-range chips (1W…All, in-memory re-window) | ok | — |
| Weight tab | stats header: current + trend + 7d/30d change chips (goal-aware) | ok | — |
| Weight tab | delete a weigh-in (trash button) | ok | — |
| Weight tab | Daily/Weekly granularity menu | missing | #1145 |
| Weight tab | WeightInsightsView: trend-EMA + explainer + body-comp cards → metric sheets + weekday pattern + weight-changes sparklines | missing | #1142 |
| Weight tab | body-comp entry (fat%/BMI/water + muscle/bone/visceral in log sheet) | missing | #1143 |
| Weight tab | edit a weigh-in (tap-to-edit — iOS `.contextMenu` absent on Skip) | missing | #1144 |
| Weight tab | big-change outlier banner (>10% → correct/edit/remove) | missing | #1144 |
| Weight tab | collapsible history disclosure (chevron + N entries) — Android list is always-expanded | deviation | #1145 |
| Weight tab | milestone celebration overlay + haptic | missing | #1145 |
| Weight tab | empty state (manual-log CTA; AH-sync stays hidden till health seam) — Android shows inline "No weights yet" | deviation | #1145 |
| Today dashboard | body summary cards row (`BodySummaryCardsRow` — mounted in `DashboardView`, NOT the Weight tab; misfiled here) | unknown | #1061 |
### Body composition — DEXA (#1069 index · iOS `Drift/Views/BodyComposition/DEXAOverviewView.swift` 632 ln · NO Android route exists)

Source-enumerated 2026-08-03 (scout #14). **The whole data layer is already in DriftCore and
Android-available** (`Models/DEXAScan`, `Models/DEXARegion`, `Domain/Health/DEXAService`,
`Domain/Health/BodyCompositionAnalysis`) — these are pure view ports, not seam work.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| DEXA | route from More — Android `MoreTab.swift` has no Body Composition row at all | missing | #1185 |
| DEXA | overview cards (BF% / lean / fat / visceral, goal-aware deltas, 0.05 neutral threshold) + miniStat row (RMR / A-G / bone / total) | missing | #1185 |
| DEXA | "WHAT CHANGED" breakdown card — `BodyCompositionAnalysis.scanDelta` narrative + verdict tint + weight-trend `reconcile` line | missing | #1185 |
| DEXA | regional breakdown (arms/trunk/legs/android/gynoid) + muscle balance L/R table | missing | #1185 |
| DEXA | "All Scans (N)" list + per-scan delete + "Clear All" destructive alert | missing | #1185 |
| DEXA | manual entry sheet (`DEXAEntryView`) — the ONLY data-in path Android can have, since PDF is iOS-only | missing | #1185 |
| DEXA | trend charts (BF% / fat mass / lean mass) — `Charts` absent on Skip, needs Path port; lean-mass drop must read RED | missing | #1190 |
| DEXA | BodySpec PDF import (`.fileImporter` + spinner + result/error cards) — blocked on #1175 seam AND PDFKit-free parser | missing | #1191 |

### Body composition — progress photos (#1069 index · Android re-creation `ProgressGalleryAndroid.swift` 169 ln vs iOS `ProgressGalleryView.swift` 311 ln + viewer 277 + charts 170 + add-entry 478)

Device-verified 2026-08-03 (scout #14, emulator-5554 build 79) except where noted.
Wired at `MoreTab.swift:120` → `:190` (sheet). Add-entry runs on the landed #1128 image-in seam (`:84`).

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Progress photos | gallery route + check-in cards render | ok | — |
| Progress photos | thumbnail tap → full-screen viewer — **DEAD TAP**, screen pixel-identical after tap; viewer absent entirely | broken | #1187 |
| Progress photos | viewer depth: pose switcher, date swipe, stat-overlay chips, compare mode + goal-aware deltas | missing | #1187 |
| Progress photos | card date — Android renders raw ISO `2026-07-30` vs iOS `Jul 30, 2026` | deviation | #1186 |
| Progress photos | card weight — Android exact-date match vs iOS nearest-within-±14d, so weight usually absent | deviation | #1186 |
| Progress photos | measurement line — Android hardcodes **inches** + chest-only vs iOS unit-aware 4-site `displayOrder` | deviation | #1186 |
| Progress photos | measurement-only check-ins (no photo) never appear — Android groups by photos; `fetchProgressEntries()` is public in DriftCore | missing | #1186 |
| Progress photos | 4-up pose slots with placeholders for missing angles — Android draws only existing photos | deviation | #1188 |
| Progress photos | timeline scrubber (segmented pose picker + horizontal dated thumbs, ≥2 entries) — source-only, needs ≥2-entry device check | missing | #1188 |
| Progress photos | Compare / Trends action row — source-only, needs ≥2-entry device check | missing | #1188 |
| Progress photos | empty state — Android is 2 lines of grey text with no "Add First Check-in" CTA | deviation | #1188 |
| Progress photos | tap-to-edit / delete a check-in — Android header inert; **no correction path exists at all** | missing | #1188 |
| Progress photos | privacy banner — `lock.fill` + larger type + always shown vs iOS `lock.shield.fill` + `.tiny` + only when non-empty | deviation | #1188 |
| Progress photos | toolbar add glyph — bare `+` vs iOS `plus.circle.fill` | deviation | #1188 |
| Progress photos | add-entry depth: 4 poses (camera + library each), measurements by `MeasurementSite.Group`, notes, delete, MeasurementGuideSheet | deviation | #1166 |
| Progress photos | live timer camera (`TimerCameraView`) — needs a camera seam beyond #1128's library-only pick | missing | #1166 |
| Progress photos | Trends sheet (`ProgressChartsView`): insights (ratios / symmetry / biggest movers) + per-site Path charts | missing | #1189 |

## More / Settings (epic #1067 = INDEX · Android stub: MoreTab.swift 90 lines vs iOS ~3.5k-line tree · scoped ports #1114–#1119)

Source-enumerated 2026-07-27 (scout #5); `missing` rows are source-verified (no Android
route exists), not emulator-driven. Persistence acceptance on every ported control
inherits #1108. KEY POLICY (0-AI-FOCUS): no key-entry UI of any kind ships on Android.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| More hub (MoreTabView :4-193) | hub layout: HEALTH/APP sections, navRow chrome (36pt icon tile, subtitle, chevron, contentShape), inline title | missing | #1114 |
| More hub (Android-only) | "COMING TO ANDROID" card (`MoreTab.swift:161-173`) is a hardcoded string array — lists **shipped** Coach chat (#1066) and photo logging (#1111) as unshipped; drifts further with every port. Device-confirmed 2026-08-03 build 79 | deviation | #1192 |
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

## Coach / AI chat (epic #1066 = INDEX · single-source: SharedUI/AIChatView*.swift + AIChatViewModel + MessageHandling(2024 ln) · hosted by ContentView floating ChatIconButton + TodayTab coach sheet · scoped children #1125 cards+interview / #1126 voice / #1133 streaming-hang / #1135 food-logging)

Source-reconciled 2026-07-28 (scout #8). The Coach TEXT chat **SHIPPED** to SharedUI (#1066, commit
b8c244a6): `AIChatView` (+ChatBubble/+InputBar/+Suggestions/+MessageHandling), `AIChatViewModel`, Nebius
brain (`CoachCloud.install` synchronous in onAppear). iOS wraps it in `DriftCoachSheet` (owns the backend
picker); **Android presents `AIChatView()` directly** (ContentView:31 + TodayTab:161) — no picker, Nebius-only,
correct per 0-AI-FOCUS no-key-UI. The message harness (`AIChatView+MessageHandling`) is DriftCore-shared and
runs on Android, so DETERMINISTIC tools route; four gap-classes remain: **(a)** all 13 tool-result CARDS are
`#if DRIFT_IOS_APP` — text summary only on Android (→#1125); **(b)** every FOOD-logging tool routes through an
iOS-only sheet and DEGRADES to "add it from the Food tab" (→#1135, dep #1062); **(c)** VOICE (mic / talk-mode
/ TTS) shimmed off (`CoachVoiceShims` no-ops → #1126); **(d)** open-ended cloud-LLM turns HANG on "Looking that
up…" (streaming buffered `#else` branch never yields → #1133). Interview ("set me up") is `#if DRIFT_IOS_APP`
(→#1125). BackendSelector / AISetup / AIChooser are key-UI, iOS-only-by-design. Rows below are SOURCE-verified;
device-verify pending an uncontended emulator window (both sibling lanes live this session).

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Coach entry | floating ChatIconButton (ContentView) + TodayTab coach sheet → AIChatView | ok | |
| Chat shell | header ("Drift Coach" + close), scroll, thinking dots, TypewriterText, Android scroll-sentinel | ok | |
| Empty-state hero | iOS = ListeningCircle (tap-to-talk); Android = static SparkleShape "Ask me anything" (tap focuses input) | deviation | #1126 |
| Input bar | iOS `idleControls` (`AIChatView+InputBar.swift:121-142`) adds photo (PhotosPicker) + mic; Android gates BOTH off (`#if DRIFT_IOS_APP`). Photo-attach NEWLY UNBLOCKED — #1128 image-in seam landed 2026-07-31, `DriftPlatform.imagePicker` live (was mis-pointed at #1125, which is cards+interview only) | deviation | #1174 (photo) / #1126 (mic) |
| Input bar | **send button** (`arrow.up.circle.fill`, InputBar :160) — DEAD TAP on Android: `vm.sendMessage()` never fires on tap, only IME enter/submit sends (glyph is a drawn `sym()` Shape → hit-target falls through, [[harness_dead_synthetic_tap_means_contentshape]]) | broken | #1137 |
| Suggestions row | horizontal smart-suggestion pills → send | ok | |
| Deterministic turns | meal-planning reply, multi-turn pills, ClarificationCard, RemoteProviderBadge, Retry — render/route on Android | ok | #1133 (confirms) |
| Open-ended cloud-LLM turn | HANGS on "Looking that up…" indefinitely — NOT a transport issue (2026-07-28: OkHttp facade #1136 proves the real Nebius round-trip completes in 2-8s; reply still never reaches the UI, so the break is a deeper Swift-concurrency/task-race issue further up the call chain) | broken | #1133 |
| Tool-result cards | ALL 13 (food/nutrition/weight/workout/nav/supplement/medication/sleep/glucose/biomarker/help/proposedMeal) are `#if DRIFT_IOS_APP` — none render on Android, text summary only | missing | #1125 |
| Weight logging tool | saves via DriftCore ("Logged X"), works — weightCard visual absent | deviation | #1125 (card) |
| Activity/workout logging tool | yes/no confirm → saves, works — workoutCard visual absent | deviation | #1125 (card) |
| Workout start / templates / smart-workout | showingWorkout → ActiveWorkoutView (SharedUI) — opens + runs on Android | ok | |
| Delete-food tool | `FoodService.deleteEntry` — works | ok | |
| Query / nutrition-lookup tools | `ToolRegistry` text result renders; nutritionCard visual absent | deviation | #1125 (card) |
| Navigation tool | navigate(tab) posts `.navigateToTab` immediately — tab switch WORKS on Android; navigationCard visual absent | deviation | #1125 (card) |
| Food-logging tools | single-food / usual-meal / meal-continuation / meal-plan / manual / barcode ALL route to `#if DRIFT_IOS_APP` sheets → DEGRADE to "add it from the Food tab for now" (no logging) | missing | #1135 (dep #1062/#1128) |
| Voice talk-mode | ImmersiveVoiceView + ListeningCircle + header voiceCluster (speaker/waveform) + mic + TTS — all iOS-only, `CoachVoiceShims` no-ops on Android | missing | #1126 |
| Interview ("set me up") | multi-turn TrainingProfile Q&A → Nebius routine — `handleMultiTurnState` is `#if DRIFT_IOS_APP` | missing | #1125 |
| AI Chat Insights | AIChatInsightsView (#261 opt-in local telemetry) — dev/debug surface | ios-only-by-design | |
| Backend selector / AISetup / AIChooser | Local Brain/Cloud picker + BYOK key-UI (#540) — Android is Nebius-only, no key UI (0-AI-FOCUS) | ios-only-by-design | |
| DriftCoachSheet wrapper | backend-picker sheet wrapper — iOS presents AIChatView inside it; Android presents AIChatView directly | ios-only-by-design | |

## Capture (epic #1063 · iOS-only: Drift/Views/PhotoLog/**, BarcodeScannerView)

**Seam split (scout 2026-08-03):** #1128 landed a photo-**LIBRARY** seam (`DriftPlatform.imagePicker.pickLibraryImage`),
NOT live camera. So each capture path is gated differently: **library-pick → parse/review** is buildable NOW
(Snap #1111, WorkoutScan-image #1110); **live camera** (PhotoLog capture, barcode) still needs a separate
AVFoundation/CameraX seam; **PDF** needs SAF (#1109). Ship each path or show an explicit "not yet" state — never a dead control.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Photo log | capture view — Android's own `CameraCaptureFacade` (TakePicture ActivityResult + FileProvider, #1111, 2026-08-03) now covers live camera too, not just library-pick; verified on-device (permission prompt, capture, confirm, no crash) | ok | #1111 |
| Photo log | flow + review (`SnapMealSheet`, #1111, 2026-08-03) — capture/analyzing/review/error phases all render correctly, error state has Retry + Retake; **review can never be reached today** because the cloud vision call truncates before returning content (#1177) | broken | #1111 (shell shipped) / #1177 (blocks review) |
| Barcode scanner | scan → food match → log — inherently live-camera; NOT covered by the library-only #1128 seam | missing | #1063 (live-camera seam pending) |
| Workout scan | photo/PDF → template or session (WorkoutScanSheet + ReviewView) — **image path UNBLOCKED** (#1128 seam; `WorkoutScanSheet:102` already routes through it); PDF still #1109-SAF-gated; `blocked` label cleared 2026-08-03 | missing | #1110 (image path unblocked; PDF #1109) |

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
| Navigation | push/sheet transition speed + font stability; nav titles render in Material typography, not the app font | deviation | #1074/#1165 |
| Theme | dark/light, goal-aware green/red, Material accent leak | unknown | |
