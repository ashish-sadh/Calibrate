# Sprint Board

## In Progress

_(pick from Ready)_

## Ready

### Infrastructure
- [x] **TC-1: ToolSchema + ToolRegistry** — b24799d
- [x] **TC-2: SpellCorrectService** — da6e4c8
- [x] **TC-3: JSON tool-call parser** — da6e4c8+

### Services (one per domain — UI and AI share these)
- [x] **SVC-1: FoodService** — c8cc327+
- [ ] **SVC-2: WeightService** — Consolidate weight logic. Methods: log_weight, get_trend, get_history, get_goal_progress. Wraps AppDatabase + WeightTrendCalculator.
- [ ] **SVC-3: ExerciseService** — Consolidate workout + exercise. Methods: start_template, build_smart_session (max 5 exercises, popular first, add notes), create_workout, get_workout_history, suggest_workout, get_progressive_overload, exercises_by_muscle, popular_exercises. Wraps WorkoutService + ExerciseDatabase.
- [ ] **SVC-4: SleepRecoveryService** — Consolidate HealthKit biometrics. Methods: get_sleep, get_recovery, get_hrv, get_readiness. Wraps HealthKitService + RecoveryEstimator.
- [ ] **SVC-5: SupplementService** — Light wrapper. Methods: get_status, mark_taken.
- [ ] **SVC-6: GlucoseService** — Methods: get_readings, detect_spikes.
- [ ] **SVC-7: BiomarkerService** — Methods: get_results, get_detail, parse_report (AI-enhanced).

### Wiring
- [ ] **WIRE-1: Register all tools** — Register every service method in ToolRegistry with schema + handler closure.
- [ ] **WIRE-2: Update system prompt** — Inject ToolRegistry.schemaPrompt() into LLM context. Screen-aware filtering.
- [ ] **WIRE-3: Replace AIChatView routing** — Use ToolRegistry.execute() instead of hardcoded sendMessage() routing. Keep rule engine for instant answers.
- [ ] **WIRE-4: Block health questions** — System prompt: "Don't give health advice. Show user's data instead. Redirect to service tools."
- [ ] **WIRE-5: Smart workout when no template** — If user says "I want to work out" and has no templates, call build_smart_session instead of listing empty templates.

### Quality
- [ ] **QA-1: Eval tests for tool-call format** — 10+ tests verifying LLM outputs valid JSON tool calls.
- [ ] **QA-2: Service unit tests** — At least 5 tests per new service (FoodService, WeightService, ExerciseService).
- [ ] **QA-3: Progressive overload tests** — Verify improving/stalling/declining detection.
- [ ] **QA-4: Smart session builder tests** — Verify max 5 exercises, popular first, notes included.

### Bugs
- [ ] **BUG: Total calories error** — Investigate and fix calories calculation inaccuracy.
- [ ] **BUG: Flaky workout session tests** — Fix sessionSaveAndLoad, sessionRoundtripWithWarmups intermittent failures.
- [ ] **FEAT-001: Calorie estimation for unknown foods** — LLM fallback when DB lookup fails.

## Done

- [x] BUG-001: Calories left wrong number
- [x] Action tags in system prompt + all screens
- [x] Removed hardcoded handlers → LLM
- [x] Direct template start from chat
- [x] Food parser: beverages, snacks, cooking verbs
- [x] 41 self-improvement cycles, 63 eval tests, build 84
- [x] Docs rewrite: clean structure, tool-calling vision
- [x] Simplified program.md (220→76 lines)
