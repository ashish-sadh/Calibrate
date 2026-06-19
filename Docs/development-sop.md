# Drift Development SOP — make a change, test it, ship it

The canonical, human-facing guide to changing Drift safely. `CLAUDE.md` is the
agent-facing mirror of these same rules; when the two disagree, fix both — there
is one workflow, not two.

> **Counts in this doc are approximate on purpose.** Hardcoded test/resource
> counts are what made the old docs lie. Where a number matters, the live command
> to get it is given. The real gate is "green", not a number.

---

## 0. The one rule that prevents most mistakes

**Decide which module the code belongs in *before* you write it.**

The repo is a cross-platform Swift package (`DriftCore`) plus the iOS app shell
(`Drift`). The boundary is mechanical:

> If a file does **not** `import UIKit / SwiftUI / HealthKit / WidgetKit /
> AVFoundation / Speech / Photos / AppIntents`, it belongs in **DriftCore** —
> even if only iOS uses it today.

```
DriftCore/Sources/DriftCore/   cross-platform domain logic (builds on iOS AND macOS)
  Models/ Persistence/ Adapters/ Utilities/ Domain/{Food,Weight,Workout,Health}/
  AI/{Parsing,Classification,Tools,Pipeline,LLM}/
Drift/                          iOS app shell — Views, ViewModels, and ONLY the
                                genuinely iOS-bound services (HealthKitService,
                                WidgetDataProvider, NotificationService,
                                SpeechRecognitionService, OCR/Vision, CloudVision)
```

Today that's ~169 DriftCore vs ~117 iOS source files — keep the iOS target lean.
A bridge/extension file with no iOS-framework import goes in DriftCore. Don't
blanket-`public`-ify on the way in; mark `public` only what's a real external API.

**Why it matters for testing:** DriftCore logic is tested with `swift test`
(~2s warm). The iOS target needs a booted simulator (~25s). Putting pure logic in
the iOS target makes the fast loop ~10× slower for no reason.

---

## 1. Prerequisites

- macOS with Xcode 16+, Swift 6.x
- `brew install xcodegen`
- For local LLM work: Gemma/SmolLM gguf in `~/drift-state/models/`
- For the cloud coach: Nebius key (see §6)
- Physical iPhone only for real HealthKit testing (simulator covers the rest)

```bash
cd /Users/ashishsadh/workspace/Drift
xcodegen generate     # after ANY project.yml change or new file
xcodebuild build -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## 2. The change loop

1. **Decide the module** (§0).
2. **Write the code.** Match the surrounding style, naming, and comment density.
   No backwards-compat shims (change the code, delete the old, no `_oldXxx`
   aliases or "removed" markers). Three similar lines beat a premature
   abstraction — consider extracting on the *third* occurrence, not the second.
3. **`xcodegen generate`** if you added/removed files or touched `project.yml`.
4. **Build** the thing you touched.
5. **Test the matching tier** (§3) — *every change*, not just at the end.
6. **Eval** if you touched the AI pipeline (§5).
7. **Coverage** if you added logic or tests: `./scripts/coverage-check.sh`
   (targets: 80% pure logic/calculators, 50% services/viewmodels/database).
8. **Update docs in the same commit** if the change affects `Docs/state.md`
   (build number, test/food/exercise/biomarker counts, AI architecture,
   capabilities). Append a line to `Docs/decisions.md` for any non-obvious call.
9. **Commit.** Build + test must be green first — the harness blocks otherwise.

---

## 3. Test Tier Map — run the right test at the right time

Five tiers by cost. **Each test file belongs to exactly one tier.** Mixing a
Tier-0 pure-logic assert with a Tier-3 LLM-backed assert in one file is the
failure mode that turned the old suite into a liability.

| Tier | Trigger | Wall time | Lives in | Tests |
|---|---|---|---|---|
| **0** | every save | <2s warm | `DriftCore/Tests/DriftCoreTests/` | pure logic — normalizer, ranker, parsers, formatters, services w/ in-memory DB |
| **1** | every commit | ~25s | `DriftTests/` (iOS sim) | UI/ViewModel binding, HealthKit, Widget, Notification, Speech, OCR, Keychain |
| **2** | every commit | ~30s | `DriftLLMEvalMacOS/` *(deterministic)* | LLM-pipeline cases that don't call a model — routing smoke, prompt-structure asserts |
| **3** | pre-TestFlight | ~12 min | `DriftLLMEvalMacOS/` *(LLM-backed)* | real model routing, multi-turn, prompt regressions |
| **4** | manual / weekly | minutes–hours | env-gated | `DRIFT_DEEP_EVAL=1`, `DRIFT_AUTORESEARCH=1`, `DRIFT_LATENCY_BENCH=1`, `DRIFT_USDA_EVAL=1` |

**New test? Decision flow:**
1. Needs a real LLM call? → Tier 3 (no env gate) or Tier 4 (env-gated).
2. Needs the iOS simulator (UIKit/HealthKit/Widget/Speech/Photos/AppIntents/
   Keychain)? → Tier 1 (`DriftTests`).
3. Otherwise → **Tier 0** (`DriftCore/Tests/DriftCoreTests/`). This is the
   default; the burden of proof is on putting it elsewhere.

Rules: one tier per file; gold sets are Tier 0 unless they call the LLM; env-gated
tests stay co-located with their helpers; fixtures travel with their tests (assert
non-empty in setup so an orphaned fixture fails loudly); don't make
`SomethingTests_v2` — expand the existing file.

---

## 4. Test commands — match the command to what you touched

| Touched | Command | Wall time |
|---|---|---|
| Pure logic in `DriftCore/` | `cd DriftCore && swift test` | ~2s warm |
| iOS UI / HealthKit / Widget | `xcodebuild test -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | ~25s |
| AI pipeline (real model) | `xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'` | ~12 min |
| Pre-TestFlight | all of the above (`.claude/hooks/preflight-check.sh` enforces) | |

```bash
cd /Users/ashishsadh/workspace/Drift

# Tier 0 — DriftCore (the fast loop; ~1,600 tests). Live count: cd DriftCore && swift test
cd DriftCore && swift test
cd DriftCore && swift test --filter SomeTests        # one suite
cd DriftCore && swift test --filter AIEvalHarness     # intent/routing eval (no LLM)

# Tier 1 — iOS (~1,250 tests). ALWAYS kill stale procs first.
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test ... 2>&1 | grep "✘"                   # empty = all pass

# Tier 3 — real-model LLM eval (macOS). DriftLLMEvalMacOS replaced the removed
# iOS DriftLLMEvalTests target (it skipped silently — see Docs/decisions.md).
pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'

# Coverage
rm -rf /tmp/DriftCoverage.xcresult; pkill -9 -f xcodebuild 2>/dev/null; sleep 2
xcodebuild test -project Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -enableCodeCoverage YES -resultBundlePath /tmp/DriftCoverage.xcresult
./scripts/coverage-check.sh
```

> **CRITICAL: never run two `xcodebuild test` at once** — they fight for the
> simulator and deadlock. Kill stale processes first, every time.

Tier-4 env vars don't reach the macOS test host as shell env (Xcode 13+); pass
them as a build setting: `xcodebuild ... DRIFT_DEEP_EVAL=1` (wired via `$(VAR)`
scheme refs). See `Docs/decisions.md`.

---

## 5. AI / chat changes — eval *and* simulate

After any change to the AI pipeline (`DriftCore/Sources/DriftCore/AI/...`):

- **Eval (lite) every time:** `cd DriftCore && swift test --filter AIEvalHarness`
  (deterministic intent/routing). Deep/real-model eval = Tier 3 (`DriftLLMEvalMacOS`)
  before TestFlight.
- **Log real failures** to `Docs/failing-queries.md`, then fix systematically and
  add a gold case.

### DriftChatSim — reproduce & iterate on chat bugs without an iOS build

`DriftChatSim` (`DriftCore/Sources/DriftChatSim/`, scheme `DriftChatSim`) drives
the **real** pipeline headlessly over a **seeded sample DB**, printing a per-turn
trace (input → normalize → StaticOverrides → route → tools+args → DB before→after
diff → response → conversation phase). It's the fastest way to see *where* a turn
goes wrong.

```bash
cd DriftCore
# Production Coach (Nebius) — most faithful:
NEBIUS_API_KEY=$(cat ~/drift-state/nebius-key.txt) swift run DriftChatSim --once "log 2 rotis and dal"
# On-device path (local Gemma), or deterministic-only if no model:
swift run DriftChatSim --repl --backend local        # multi-turn; :phase / :state / :reseed / :quit
swift run DriftChatSim --script turns.json --json     # scriptable / gold-set JSONL
```

- **Backends:** `--backend nebius|local|auto` (auto = Nebius if key, else local,
  else deterministic-only). `--screen`, `--no-seed`, `--json`, `--model PATH`.
- **GOTCHA:** the sim shares `AppDatabase.shared` (tools hardcode it — no injection
  seam), and `swift test` mutates that same DB. **Always seed** (the default; don't
  pass `--no-seed`) for accurate `db_effects`.
- **Covers:** Phase 1 (`StaticOverrides`) + Phase 8 (`AIToolAgent`) + real tools +
  real DB. **Does NOT cover** the iOS dispatch Phases 0.5–7 (multi-turn picks,
  food-intent parse, confirms) — those live in `AIChatViewModel`. That extraction
  (a DriftCore `ChatEngine` returning effects) is the planned v2.

See `DriftCore/Sources/DriftChatSim/README.md` for the full interface.

### Models & backend
- **Cloud coach:** Nebius (Qwen3-235B), key in `~/drift-state/nebius-key.txt`
  (sealed in `Drift/Config/AppConfig.swift`; low-stakes spending cap, rotate
  periodically). This is what ships as "Drift Coach".
- **On-device:** llama.cpp via `LlamaCppBackend`, Gemma 4 / SmolLM gguf in
  `~/drift-state/models/`. CPU-only (Metal is broken on A19 Pro hardware).

---

## 6. Adding a feature — checklist

1. Find current priorities: `scripts/sprint-service.sh status` (queue is GitHub
   `sprint-task` issues — there is no static task list).
2. Decide the module (§0).
3. New data? Add a GRDB migration in `DriftCore/.../Persistence/`.
4. Model in `Models/`, service in `Domain/.../`, view in `Drift/Views/`.
5. Write tests **before** committing new service/logic code (§3).
6. `xcodegen generate` if files were added.
7. AI-related? Add eval cases (§5) and reproduce via `DriftChatSim`.
8. Update `Docs/state.md` if you changed any counted/architectural fact.

---

## 7. Resources & data

Bundled JSON lives in `DriftCore/Sources/DriftCore/Resources/`, loaded via
`Bundle.module` (resolves headlessly on macOS too): foods (~5,460, Indian-first),
exercises (~960), biomarkers (~71). `AppDatabase` seeds/refreshes foods from
`foods.json` on launch; user-scanned foods (barcode/recipe/photo/custom) are never
overwritten. Use `AppDatabase.shared` in production, `AppDatabase.empty()` for
isolated tests.

---

## 8. TestFlight

Auto-published every 3 hours via `.claude/hooks/testflight-check.sh` (the hook
injects publish instructions after a commit once 3h have passed — follow them when
they appear; never publish more often). Manual cut: bump
`CURRENT_PROJECT_VERSION` in `project.yml` → `xcodegen generate` → archive →
export/upload (full commands in `CLAUDE.md` → TestFlight).
`.claude/hooks/preflight-check.sh` runs all tiers as the gate.

---

## See also
- `CLAUDE.md` — the agent-facing mirror of this SOP (authoritative on identical rules)
- `Docs/architecture.md` — AI-first dual-model + cloud-coach architecture
- `Docs/decisions.md` — non-obvious decisions & harness rules from real incidents
- `Docs/testing.md` / `Docs/develop.md` — pointers into this SOP + a few unique setup notes
- `Docs/failing-queries.md` — real chat queries that don't work yet
