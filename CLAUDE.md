# Drift — Claude Code Instructions

## The App
Drift is an AI-first local health tracker. AI chat is the showstopper — the primary way users interact. Every data entry should be doable through conversation. Traditional UI exists for visual analytics and as a fallback.

**Dual-model:** SmolLM (360M) does heavy lifting with hardcoded harness. Gemma 4 (2B) uplifts with intelligence — smart tool calling, multi-turn, cross-domain reasoning. Privacy-first: everything on-device, no cloud, no accounts.

## Design Tenets

- AI chat is the showstopper. Every data entry must be doable through conversation; UI exists for visual analytics and as a fallback.
- Privacy-first. Everything on-device, no cloud, no accounts, no analytics. Any cloud touchpoint surfaces explicitly to the user.
- Goal-aware color, never "good/bad". Green = aligned with the user's goal direction; red = against it. Default goal: losing weight.
- Indian food is the bar. Every food list, search, parser, and eval works for Indian cuisine first; everything else is downstream.
- Friend feedback over telemetry. When unsure if a feature is right, ask a user; do not instrument behavior.
- DriftCore by default. If a file doesn't `import UIKit/SwiftUI/HealthKit/WidgetKit/AVFoundation/Speech/Photos/AppIntents`, it belongs in DriftCore — even if only iOS currently uses it.
- One tier per test file. Mixing Tier-0 logic with Tier-3 LLM-backed asserts is the failure mode that turned the old suite into a liability.
- No backwards-compat shims. Change the code, delete the old, no `_oldXxx` aliases or "removed" comment markers.
- Three similar lines beats premature abstraction. Don't extract on the second occurrence; consider it on the third.
- Build and test after every change. The harness will block the commit if you skip; trust the discipline, not your gut.
- **User data is sacred — it is the one thing we cannot rebuild.** Code can be rewritten and a bad release can be re-published; a user's friends, chat history, weight log and food diary cannot. Before any schema change, local or server: additive first (new table/column, backfill, then read from it), never destructive-in-place. No `DROP`, no `TRUNCATE`, no unscoped `DELETE`, no renaming a column out from under existing rows, no re-keying a table that already has data. A migration that cannot be run twice safely is not finished. When a change genuinely must move data, write the migration that carries it across and prove the row counts before and after — "the schema is right now" is not the bar; "every row that existed still exists" is. And losing ACCESS to data is losing it: an account users cannot get back into is indistinguishable, to them, from a deleted account.

## Three Operating Modes

### Mode 1: Human-Shepherded (default)
Human drives feature work. To see open work: `scripts/sprint-service.sh status` (full snapshot) or `scripts/sprint-service.sh next --senior` / `--junior` (top item). The queue lives on GitHub as `sprint-task`-labeled issues — there is no static task list to read. Build, test, commit per ticket. You can publish TestFlight anytime. All hooks apply except TestFlight auto-publish.

### Mode 2: Autopilot
Human says "run autopilot" in a session. Reads `program.md` and loops forever — features, bugs, UI, AI, tests, food DB, code quality (boy scout rule). Runs in foreground, Ctrl+C to stop. No watchdog, no auto-restart.

### Mode 3: Drift Control (Watchdog-Managed)
Fully autonomous background operation. The watchdog (`scripts/self-improve-watchdog.sh`) launches Autopilot, restarts on crash/stall, enforces TestFlight every 3h with pre-flight, generates daily exec report PRs, runs product reviews every 20 cycles. Start with "start drift control".

### Drift Control
See `program.md` for autopilot instructions, sprint lifecycle, and control commands. Hooks are defined in `.claude/settings.json` and `.claude/hooks/`.

## Doc Map

Each entry tagged with its maintenance status. **Auto-maintained** = a script or workflow keeps it current. **Manual** = humans hand-edit; will drift if no one tends it. **Reference** = slow-moving by design (architecture, principles, dev setup). Sessions reading "Manual" docs should treat them as snapshots that may not match reality.

**Authoritative live state** (the queue of work, current focus, who's running what) lives outside this Doc Map: `gh issue list`, `~/drift-state/sprint-state.json`, `command-center/heartbeat.json`. There is no static task list.

| Doc | Status | What it is |
|-----|--------|-----------|
| `program.md` | Reference (pointer doc) | **Drift Autopilot pointer** — mode summary, "run autopilot" standalone loop, human takeover commands. Phase logic lives in `.claude/skills/<role>/SKILL.md`. |
| `Docs/roadmap.md` | **Auto-maintained** (planning step 10) | Product roadmap — unified, domain-sectioned. Re-read every cycle. |
| `Docs/personas/` | **Auto-maintained** (planning step 10) | Evolving Product Designer + Principal Engineer persona files. |
| `Docs/reports/` | **Auto-maintained** (review/exec PR workflows) | Exec reports + product review reports. Published as GitHub PRs. |
| `Docs/state.md` | Manual snapshot — may drift | Build number, test count, features. Updated periodically; check git log for freshness. |
| `Docs/decisions.md` | **Append-only — sessions add** | Non-obvious decisions: arch changes, harness rules from incidents, design tenets from real failures. Planning step 6 reviews + appends. Read last ~10 entries before making related judgment calls. |
| `Docs/architecture.md` | Reference (slow-moving) | AI-first dual-model architecture. Update only when architecture changes. |
| `failing-query` GitHub label | **Issues, not a doc** | Real AI-chat queries that misroute/fail — one scoped issue per query class (`gh issue list --label failing-query`), closed when the query routes correctly. (`Docs/failing-queries.md` retired 2026-07-15: point-in-time state lives in issues; resolved history lives in git log.) |
| `Docs/development-sop.md` | Reference (canonical) | **The dev SOP** — module layout (DriftCore vs iOS), build, test tier map, AI eval, DriftChatSim, feature checklist. Human-facing mirror of this file's workflow rules. |
| `Docs/testing.md` | Reference (pointer) | Test-authoring patterns + simulator utilities; defers the workflow to `development-sop.md`. |
| `Docs/develop.md` | Reference (pointer) | Prereqs, USDA key, dependencies; defers the workflow to `development-sop.md`. |
| `Docs/body-diagram.md` | Reference | Muscle-figure system: react-native-body-highlighter source, extraction pipeline, gender selection, data quirks. |
| `Docs/exercise-pose-sourcing.md` | Reference | How to source + convert exercise demo pose photos (source ladder, HEIC pipeline, guard tests). |
| `Docs/principles/` | Reference | Code quality cards (Clean Code, Design Patterns, DDD, SwiftUI). |
| `Docs/refactor/` | Manual — ACTIVE plans only | Refactor specs whose lifecycle is owned by an OPEN issue (e.g. estimation-unification ↔ #1052). Shipped plans move to `Docs/archive/`; a plan with no owning issue is a policy violation — file one. |
| `Docs/archive/` | Frozen | History: legacy docs, shipped refactor specs, point-in-time audits. Never maintained, never read for current state. |
| `Docs/designs/` | Reference | Numbered feature/design docs (issue-linked); `TEMPLATE.md` for new ones. |
| `Docs/tenets.md` | Reference (self-maintaining protocol) | Product ground truth for `/planning` step 6 + feature triage; sediment log at top. |
| `Docs/drift-control-design.md` | Reference | Source of truth for the autonomous sprint system's behavior. |
| `Docs/ai-chat-architecture.md` | Reference | Tiered-pipeline deep-dive (stages, tools, rules); `architecture.md` is the overview. |
| `Docs/ai-autoresearch.md` | Reference | Tier-4 prompt-optimization loop (DRIFT_AUTORESEARCH=1). |
| `Docs/licenses.md` | Reference | Third-party attributions (exercise DB, models). |

## Rules
- Build and test after every change
- All unit tests must pass before committing: ~850 in DriftCoreTests (`swift test`) + ~1200 in iOS DriftTests (`xcodebuild`)
- Run LLM eval lite after AI changes (`xcodebuild test -scheme DriftLLMEvalMacOS` — deterministic fast gate, ~1 min); full Tier-3 `DRIFT_LLM_EVAL=1` only for AI-pipeline changes or when asked
- TestFlight is auto-published every 3 hours via hook (`.claude/hooks/testflight-check.sh`). The hook injects publish instructions after a commit when 3+ hours have passed. Follow the instructions when they appear. Never publish more frequently than every 3 hours.
- No MacroFactor references anywhere
- Privacy-first: everything local, no cloud, no analytics
- Run `xcodegen generate` after changing project.yml or adding new files
- Run eval harness after any AI change
- Run coverage check after writing tests: `./scripts/coverage-check.sh`
- Coverage targets: **80%** for pure logic/calculators, **50%** for services/viewmodels/database
- Write tests for any new service or logic code before committing
- If your change affects `Docs/state.md` (build, test counts, food/exercise/biomarker counts, AI architecture, capabilities), update it in the same commit

## Color Philosophy (Goal-Aware)
- Green (Theme.deficit) = aligned with goal direction
- Red (Theme.surplus) = against goal
- Default: assume losing weight

## Module Layout

The codebase is split into a multi-platform `DriftCore` Swift package + the iOS Drift app target.

**`DriftCore/Sources/DriftCore/`** — cross-platform domain logic. Builds on iOS AND macOS AND Android (`scripts/android-build-check.sh` is the Android guard — keep it green). No `import UIKit/SwiftUI/HealthKit/WidgetKit/AVFoundation/Speech/Photos/AppIntents`.

**`SharedUI/`** — SwiftUI shared verbatim between the iOS app and the Android app (`drift-android/` Skip Fuse app symlinks it into its module). ONE physical file compiles for both — never copy view code between the apps; platform deltas go behind `#if os(Android)` with shims in `drift-android/.../SkipUICompat.swift`. A change under SharedUI/ or DriftCore is done only when BOTH platforms build: `xcodebuild` (iOS) and `cd drift-android && skip app launch --android` (or android-build-check.sh for core-only changes).
- `Models/` — data types (Food, FoodEntry, WeightEntry, RecipeItem, etc.)
- `Persistence/` — AppDatabase + GRDB extensions
- `Adapters/` — DriftPlatform registry + protocols (HealthDataProvider, WidgetRefresher) for iOS-only seams
- `Utilities/` — DateFormatters, Log, MacroFormatters, Preferences (UserDefaults), CSVParser
- `Domain/{Food,Weight,Workout,Health}/` — domain services (FoodService, WorkoutService, etc.)
- `AI/{Parsing,Classification,Tools,Pipeline,LLM}/` — AI pipeline (InputNormalizer, IntentClassifier, ToolRanker, AIToolAgent, StaticOverrides, LlamaCppBackend, ...)

**`Drift/`** — iOS app shell. Owns Views, ViewModels, and only the genuinely iOS-bound services:
- `HealthKitService` (+ extensions) — conforms to `HealthDataProvider`
- `WidgetDataProvider` + `WidgetCenterRefresher` — conforms to `WidgetRefresher`
- `NotificationService`, `SpeechRecognitionService`
- `BodySpecPDFParser`, `LabReportOCR`, `NutritionLabelOCR` — Vision/PDFKit
- `CloudVision/*`, `PhotoLogTool` — iOS Keychain + cloud OCR
- `FoodService+Logging` — uses `FoodLogViewModel`
- `Views/`, `ViewModels/`, `Resources/`, `DriftApp.swift`

**`DriftApp.init()`** wires the seams: `DriftPlatform.health = HealthKitService.shared` + `DriftPlatform.widget = WidgetCenterRefresher()`.

## Test Workflow — match the test command to what you touched

| Touched code | Command | Wall time |
|---|---|---|
| Pure logic in `DriftCore/Sources/DriftCore/` | `cd DriftCore && swift test` | ~2s warm (~913 tests) |
| AI pipeline — fast gate (deterministic, default) | `xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'` | ~1 min (LLM suites skip) |
| AI pipeline — full Tier-3 (real Gemma 4) | same + `DRIFT_LLM_EVAL=1` build setting | 1–3 h; after AI-pipeline changes, budget accordingly |
| iOS UI / HealthKit / Widget integration | `xcodebuild test -scheme Drift -destination 'iOS Simulator,name=iPhone 17 Pro'` | ~25s (~1219 tests) |
| Pre-TestFlight | run all of the above (preflight-check.sh enforces) |  |

**Note (2026-04-28):** the iOS-side `DriftLLMEvalTests` target was removed — it skipped silently on every fresh simulator (no model file in the app container) so it lied about coverage. macOS LLM eval is the real LLM gate; the iOS eval target had no unique coverage worth keeping.

If you touch a file that's only Swift logic (no SwiftUI / HealthKit / WidgetKit / etc), it almost certainly belongs in DriftCore — keep the iOS target lean.

## Test Tier Map — run the right test at the right time

Five tiers by cost. Each test file MUST belong to exactly one tier; mixing tiers in one file is the failure mode that turned the whole suite into a liability.

| Tier | Trigger | Wall time | Where it lives | What it tests |
|---|---|---|---|---|
| **0** | every save | <2s warm | `DriftCore/Tests/DriftCoreTests/` | pure logic — InputNormalizer, ToolRanker, parsers, formatters, services with in-memory DB |
| **1** | every commit | ~25s | `DriftTests/` (iOS sim) | UI/ViewModel binding, HealthKit, Widget, Notification, Speech, OCR, Keychain |
| **2** | every commit | ~30s | `DriftLLMEvalMacOS/` *(deterministic only)* | LLM-pipeline cases that don't actually call a model — IntentRouting smoke, prompt-structure asserts |
| **3** | after AI-pipeline changes (NOT a publish gate — 2026-07-30) | 1–3 h | `DriftLLMEvalMacOS/` *(LLM-backed, `DRIFT_LLM_EVAL=1` build setting)* | real Gemma 4 routing, multi-turn, prompt regressions |
| **4** | manual / weekly / opt-in | minutes–hours | gated by env var | `DRIFT_DEEP_EVAL=1`, `DRIFT_AUTORESEARCH=1`, `DRIFT_LATENCY_BENCH=1`, `DRIFT_USDA_EVAL=1` — benchmarks, optimization loops, coverage scans |

**New test? Decision flow:**

1. Does the test need a real LLM call? → Tier 3 (`DriftLLMEvalMacOS`, no env gate) or Tier 4 (`DriftLLMEvalMacOS`, env-gated).
2. Does the test need iOS Simulator (UIKit, HealthKit, Widget, Speech, Photos, AppIntents, Keychain via Security/LocalAuthentication)? → Tier 1 (`DriftTests`).
3. Otherwise → Tier 0 (`DriftCore/Tests/DriftCoreTests/`). This is the default; the burden of proof is on putting it elsewhere.

**Rules:**

- **One tier per file.** Don't write a test class where some methods are deterministic and others hit a real model — split them. Tier-2 cases that "might" call the LLM under env gate belong in Tier 4.
- **Env-gated tests stay co-located with their helpers.** If `AutoResearchTests` needs `PromptOptimizer.swift`, that helper lives next to the test. Don't create a fake "lib" folder.
- **Gold sets are Tier 0 unless they call the LLM.** A gold set that asserts `ToolRanker.rank("log eggs").first == log_food` is Tier 0. A gold set that asserts `LocalAIService.classify("log eggs") == log_food` is Tier 3.
- **Fixtures travel with their tests.** SwiftPM test target uses `resources: [.process("Fixtures")]` + `Bundle.module`. iOS test target uses `path: DriftTests` (dir-globbed by xcodegen). If you orphan a fixture, the test will silently produce empty data — assert non-empty in setup.
- **Don't create a new test file** if its assertions belong in an existing file. Prefer expanding `IntentClassifierGoldSetTests` over making `IntentClassifierGoldSetTests_v2`.
- **Reserve `DriftTests/`** for tests that genuinely need `@testable import Drift` (Views, ViewModels, HealthKitService, OCR, CloudVisionKey). The `swift test` loop is ~10× faster than the iOS Simulator boot — don't put pure logic there.

## Build & Test

**CRITICAL: Never run multiple `xcodebuild test` in parallel.** They fight for the simulator and deadlock. Always kill stale processes first.

```bash
cd /Users/ashishsadh/workspace/Drift

# Build
xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# iOS unit tests (~1219 tests, ~25s) — for pure DriftCore logic prefer `cd DriftCore && swift test`. ALWAYS kill stale processes first
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# macOS eval fast gate (deterministic; LLM suites skip) — ~1 min
# Full Tier-3 with real Gemma 4: append DRIFT_LLM_EVAL=1 (build setting, 1–3 h)
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'

# Check failures
xcodebuild test ... 2>&1 | grep "✘"  # empty = all pass

# AI eval harness only (intent detection, no LLM) — moved to DriftCore
cd DriftCore && swift test --filter AIEvalHarness

# Coverage check (run after tests with coverage enabled)
rm -rf /tmp/DriftCoverage.xcresult
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES -resultBundlePath /tmp/DriftCoverage.xcresult
./scripts/coverage-check.sh
```

## TestFlight
```bash
# 1. Bump CURRENT_PROJECT_VERSION in project.yml
# 2. xcodegen generate
# 3. Archive
xcodebuild archive -project Drift.xcodeproj -scheme Drift -destination 'generic/platform=iOS' -archivePath /tmp/Drift.xcarchive DEVELOPMENT_TEAM=ZJ5H5XH82A CODE_SIGN_STYLE=Automatic
# 4. Export + Upload
xcodebuild -exportArchive -archivePath /tmp/Drift.xcarchive -exportPath /tmp/DriftExport -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath "/Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_623N7AD6BJ.p8" -authenticationKeyID 623N7AD6BJ -authenticationKeyIssuerID ad762446-bede-4bcd-9776-a3613c669447
```

## Working Directory
`/Users/ashishsadh/workspace/Drift`

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
