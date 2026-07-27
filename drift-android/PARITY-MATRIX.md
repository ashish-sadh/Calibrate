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

## Workout (epic #1064 · single-source: SharedUI/WorkoutView.swift hosted by WorkoutTab)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Workout tab root | template grid (cards; "Show all 10" affordance) | deviation | #1095 |
| Workout tab root | streak card (conditional: current > 0) | ok | |
| Workout tab root | burn chips (active cal / steps; gated on DriftPlatform.health) | ok | |
| Workout tab root | Apple-Health workouts band (fetchRecentWorkouts hardcoded []) | missing | #1070/#1095 |
| Workout tab root | history collapsible + rows → WorkoutDetailView (auto-expand on save) | ok | |
| Workout tab root | history row .contextMenu (delete) + Android fallback | unknown | #1076 |
| Workout tab root | Start Empty Workout → ActiveWorkoutView sheet | ok | |
| Workout tab root | Muscle Recovery body map + per-group chips (soreness data) | ok | |
| Workout tab root | resume banner ("Workout in progress — Resume") | ok | |
| Workout tab root | past-workout log sheet (`showingPastWorkout`) | unknown | |
| Workout tab root | voice/text log sheet (`showingVoiceLog` → ExerciseVoiceLogSheet) | unknown | |
| Workout tab root | scan workout sheet (`showingScan` → WorkoutScanSheet, iOS-only file) | missing | #1095 |
| Workout tab root | create template sheet (`showingCreateTemplate` → CreateTemplateView) | unknown | |
| Workout tab root | edit template sheet (`editingTemplateForEdit`) | unknown | |
| Workout tab root | exercise browser sheet (`showingExerciseBrowser`) | ok | |
| Workout tab root | template preview sheet (warmups, pose thumbs, rest times, start/edit/favorite/delete) | ok | |
| Workout tab root | Rename Template alert | unknown | |
| Workout tab root | Delete Template / Remove All Templates alerts | unknown | |
| Workout tab root | Delete Workout alert | unknown | |
| Workout tab root | Import alert | unknown | |
| ActiveWorkoutView | FIRST set-done → notif-permission moment relaunches MainActivity, dumps to Today | broken | #1096 |
| ActiveWorkoutView | close → confirmationDialog (resume/discard/finish) | unknown | #1076 |
| ActiveWorkoutView | add exercises → ExercisePickerView sheet | ok | |
| ActiveWorkoutView | set row: decimal-pad keyboard appears, value commits | ok | |
| ActiveWorkoutView | set row: focus does NOT select-all — typing inserts (185+200 → 120085) | deviation | #1097 |
| ActiveWorkoutView | implausible-weight confirmation dialog ("really heavy") | ok | |
| ActiveWorkoutView | set row: prev-weight ghost values + prefill | ok | |
| ActiveWorkoutView | set row: warmup flag, done toggle, kg/lbs per exercise | unknown | |
| ActiveWorkoutView | set done → green tint + inline rest timer countdown + coach toast | ok | |
| ActiveWorkoutView | exercise .contextMenu (Android fallback affordance) | unknown | #1076 |
| ActiveWorkoutView | command strip / commandFocused text entry | unknown | #1076 |
| ActiveWorkoutView | exercise row → NavigationLink ExerciseDetailView | unknown | |
| ActiveWorkoutView | finish → options sheet (save-as-template/favorite) → completion card + share text | ok | |
| ActiveWorkoutView | mid-workout kill + resume (SavedSession restores sets/state/timer) | ok | |
| ActiveWorkoutView | resume drops Previous-column ghosts (shows "—") | deviation | #1098 |
| ExercisePickerView | search field: autofocus, live results, tap result w/ keyboard up | ok | |
| ExercisePickerView | recent/your/all sections + last-weight decoration | ok | |
| ExercisePickerView | row .swipeActions(leading) + Android fallback | unknown | #1076 |
| ExercisePickerView | multi-select circles + "Add N Exercises" batch CTA | ok | |
| ExercisePickerView | custom exercise sheet (`showingCustom`) | unknown | |
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
| TemplatePreviewSheet | exercise rows → NavigationLink detail | unknown | |
| TemplatePreviewSheet | Start Workout / Edit / Favorite / Delete Template actions | unknown | |
| CreateTemplateView | add exercises via picker sheet | unknown | |
| CreateTemplateView | per-exercise set/rep Stepper bounds | unknown | #1076 |
| CreateTemplateView | edit-exercise sheet (`editingBinding`) | unknown | |
| WorkoutDetailView | header stats + set rows w/ per-set 1RM | ok | |
| WorkoutDetailView | ⋮ menu: Share / Edit Name & Notes / Save as Template / Delete | ok | |
| WorkoutDetailView | set row .swipeActions(trailing) delete | unknown | |
| WorkoutDetailView | Edit Set (iOS alert / Android sheet stand-in) | unknown | |
| WorkoutDetailView | menu actions drive-through (rename/delete/save/share sheets) | unknown | |
| ExerciseVoiceLogSheet | voice/text parse via Nebius ladder (#1079 fixed raw-name save; re-verify) | unknown | 0-AI-LADDER |
| ExerciseVoiceLogSheet | resolve-target sheet (`resolveTarget`) | unknown | |
| BodyMapView (recovery) | muscle figure colored by soreness (front+back render) | ok | |
| BodyMapView (recovery) | tap muscle → suggested recovery template | unknown | |
| MuscleHighlightCard | per-workout muscle highlight rendering | unknown | |

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
| Dashboard | rings/donut (TodayDonutView, V6Rings) | unknown | #1061 |
| Dashboard | coaching cards (CoachingBriefCard, V6CoachingNudge) | unknown | #1061 |
| Dashboard | sleep/recovery card (SleepRecoveryView) | unknown | #1061 |
| Dashboard | workout consistency card | unknown | #1061 |
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
