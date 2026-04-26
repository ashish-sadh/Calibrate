# Drift — Claude Code Instructions

## The App
Drift is an AI-first local health tracker. AI chat is the showstopper — the primary way users interact. Every data entry should be doable through conversation. Traditional UI exists for visual analytics and as a fallback.

**Dual-model:** SmolLM (360M) does heavy lifting with hardcoded harness. Gemma 4 (2B) uplifts with intelligence — smart tool calling, multi-turn, cross-domain reasoning. Privacy-first: everything on-device, no cloud, no accounts.

## Three Operating Modes

### Mode 1: Human-Shepherded (default)
Human drives feature work. Read `Docs/sprint.md` for current tickets. Build, test, commit per ticket. You can publish TestFlight anytime. All hooks apply except TestFlight auto-publish.

### Mode 2: Autopilot
Human says "run autopilot" in a session. Reads `program.md` and loops forever — features, bugs, UI, AI, tests, food DB, code quality (boy scout rule). Runs in foreground, Ctrl+C to stop. No watchdog, no auto-restart.

### Mode 3: Drift Control (Watchdog-Managed)
Fully autonomous background operation. The watchdog (`scripts/self-improve-watchdog.sh`) launches Autopilot, restarts on crash/stall, enforces TestFlight every 3h with pre-flight, generates daily exec report PRs, runs product reviews every 20 cycles. Start with "start drift control".

### Drift Control
See `program.md` for autopilot instructions, sprint lifecycle, and control commands. Hooks are defined in `.claude/settings.json` and `.claude/hooks/`.

## Doc Map
| Doc | What it is |
|-----|-----------|
| `Docs/ai-parity.md` | **AI chat vs UI feature gap** — what to build next |
| `Docs/failing-queries.md` | **Failing queries** — real queries that don't work, fix systematically |
| `Docs/architecture.md` | AI-first dual-model architecture |
| `Docs/sprint.md` | Current sprint (close parity gaps) |
| `Docs/state.md` | Current build, test count, features |
| `Docs/tools.md` | Service → tool mapping (10 JSON tools) |
| `Docs/backlog.md` | Long-term tickets (organized by AI gaps) |
| `Docs/roadmap.md` | **Product roadmap** — unified, domain-sectioned, read every cycle |
| `Docs/product-review-log.md` | Periodic product + engineering reviews (every 20 cycles) |
| `Docs/personas/` | Evolving Product Designer + Principal Engineer persona files |
| `Docs/reports/` | Exec reports and product review reports (published as GitHub PRs) |
| `Docs/testing.md` | How to run tests, eval harness |
| `Docs/develop.md` | Dev setup, architecture, adding features |
| `Docs/improvement-log.md` | Loop cycle log |
| `Docs/principles/` | Code quality reference cards (Clean Code, Design Patterns, DDD, SwiftUI) |
| `program.md` | **Drift Autopilot** — the single autonomous loop program |

## Rules
- Build and test after every change
- All unit tests must pass before committing: ~850 in DriftCoreTests (`swift test`) + ~1200 in iOS DriftTests (`xcodebuild`)
- Run LLM eval lite after AI changes; deep eval only when asked
- TestFlight is auto-published every 3 hours via hook (`.claude/hooks/testflight-check.sh`). The hook injects publish instructions after a commit when 3+ hours have passed. Follow the instructions when they appear. Never publish more frequently than every 3 hours.
- No MacroFactor references anywhere
- Privacy-first: everything local, no cloud, no analytics
- Run `xcodegen generate` after changing project.yml or adding new files
- Run eval harness after any AI change
- Run coverage check after writing tests: `./scripts/coverage-check.sh`
- Coverage targets: **80%** for pure logic/calculators, **50%** for services/viewmodels/database
- Write tests for any new service or logic code before committing

## Color Philosophy (Goal-Aware)
- Green (Theme.deficit) = aligned with goal direction
- Red (Theme.surplus) = against goal
- Default: assume losing weight

## Module Layout

The codebase is split into a multi-platform `DriftCore` Swift package + the iOS Drift app target.

**`DriftCore/Sources/DriftCore/`** — cross-platform domain logic. Builds on iOS AND macOS. No `import UIKit/SwiftUI/HealthKit/WidgetKit/AVFoundation/Speech/Photos/AppIntents`.
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
| Pure logic in `DriftCore/Sources/DriftCore/` | `cd DriftCore && swift test` | ~2s warm (~850 tests) |
| AI pipeline (LLM eval) | `xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'` | 30s deterministic per-stage / ~5min full |
| iOS UI / HealthKit / Widget integration | `xcodebuild test -scheme Drift -destination 'iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests` | ~30s (~1200 tests) |
| Pre-TestFlight | run all of the above |  |

If you touch a file that's only Swift logic (no SwiftUI / HealthKit / WidgetKit / etc), it almost certainly belongs in DriftCore — keep the iOS target lean.

## Test Tier Map — run the right test at the right time

Five tiers by cost. Each test file MUST belong to exactly one tier; mixing tiers in one file is the failure mode that turned the whole suite into a liability.

| Tier | Trigger | Wall time | Where it lives | What it tests |
|---|---|---|---|---|
| **0** | every save | <2s warm | `DriftCore/Tests/DriftCoreTests/` | pure logic — InputNormalizer, ToolRanker, parsers, formatters, services with in-memory DB |
| **1** | every commit | ~30s | `DriftTests/` (iOS sim) | UI/ViewModel binding, HealthKit, Widget, Notification, Speech, OCR, Keychain |
| **2** | every commit | ~30s | `DriftLLMEvalMacOS/` *(deterministic only)* | LLM-pipeline cases that don't actually call a model — IntentRouting smoke, prompt-structure asserts |
| **3** | nightly + pre-TestFlight | ~5–10 min | `DriftLLMEvalMacOS/` *(LLM-backed)* | real Gemma 4 / Qwen3 routing, multi-turn, prompt regressions |
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

# iOS unit tests (~1200 tests, ~30s) — for pure DriftCore logic prefer `cd DriftCore && swift test`. ALWAYS kill stale processes first
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests

# LLM eval lite (3 queries per model, ~2 min) — run after AI changes
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftLLMEvalTests 2>&1 | grep -E "📊|❌|✔|✘|passed|failed"

# LLM eval deep PARALLEL (40 queries x 3 models, ~10 min) — only when asked, run in background
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
DRIFT_DEEP_EVAL=1 xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'DriftLLMEvalTests/ParallelLLMEval'

# LLM eval deep SEQUENTIAL (100+ queries per model, ~25 min each) — full eval
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
DRIFT_DEEP_EVAL=1 xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftLLMEvalTests

# Check failures
xcodebuild test ... 2>&1 | grep "✘"  # empty = all pass

# AI eval harness only (intent detection, no LLM)
xcodebuild test ... -only-testing:'DriftTests/AIEvalHarness'

# Coverage check (run after tests with coverage enabled)
rm -rf /tmp/DriftCoverage.xcresult
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests -enableCodeCoverage YES -resultBundlePath /tmp/DriftCoverage.xcresult
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
