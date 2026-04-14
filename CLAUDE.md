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

### Drift Control Commands

| User says | You do | What happens |
|-----------|--------|-------------|
| "start drift control" | `echo "RUN" > ~/drift-control.txt && cd /Users/ashishsadh/workspace/Drift && nohup ./scripts/self-improve-watchdog.sh > /dev/null 2>&1 &` | Watchdog starts, picks model based on work available |
| "stop drift control" | `echo "STOP" > ~/drift-control.txt` | Kills session immediately, watchdog exits |
| "drain" / "graceful stop" | `echo "DRAIN" > ~/drift-control.txt` | Finishes current commit, exits cleanly |
| "take over from autopilot" | `echo "PAUSE" > ~/drift-control.txt` → wait for autopilot to exit (`while ps aux \| grep -q 'claude.*autopilot'; do sleep 5; done`) → confirm "Autopilot stopped. You're in control." | Graceful handoff — autopilot finishes commit, stops. Human works freely. |
| "release control to autopilot" | `echo "RUN" > ~/drift-control.txt` → confirm "Autopilot will resume on next watchdog check (~30s)." | Watchdog restarts sessions |
| "status" | `cat ~/drift-control.txt && cat ~/drift-state/last-model && ps aux \| grep 'claude.*autopilot' \| grep -v grep` | Control state, last model used, running processes |

### Sprint Lifecycle

The watchdog orchestrates a 3-phase sprint:
1. **Sprint Planning (Opus, every 6h):** Deep review + create 8-12 sprint-task Issues (SENIOR/JUNIOR)
2. **Senior Execution (Opus):** SENIOR Issues + P0 bugs. Alternates with Sonnet.
3. **Junior Execution (Sonnet + advisor):** JUNIOR Issues, then permanent tasks. Always running.

Sprint tasks are GitHub Issues with `sprint-task` + `SENIOR`/`JUNIOR` labels. Sonnet is the default — Opus only runs when there's SENIOR/P0 work or planning is due.

### Enforced Hooks

| Hook | Event | Blocks? | Applies to | What |
|------|-------|---------|-----------|------|
| **Read-before-edit** | PreToolUse Edit/Write | Yes | All modes | Must Read .swift files before editing |
| **Boy scout** | PostToolUse Edit/Write | No | All modes | Reminds to clean code smells you touched |
| **Issue check** | PreToolUse git commit | No (nags) | All modes | Check GitHub Issues every 2h |
| **Cycle counter** | PostToolUse git commit | No | All modes | Counts cycles. Every 20th: product review + PR |
| **Coverage gate** | PostToolUse git commit (5th) | No | All modes | Coverage check, forces test-writing if dropped |
| **TestFlight check** | PostToolUse git commit (3h) | No | Drift Control only | Auto TestFlight publish with pre-flight |
| **TestFlight guard** | PreToolUse xcodebuild archive | Yes | Drift Control only | Blocks unauthorized publishes |
| **Pre-flight** | Before archive | Yes | Drift Control only | Build + tests + eval + no P0 bugs |
| **Mark in-progress** | PostToolUse git commit | No | All modes | Auto-adds in-progress label when commit references #N |
| **Daily exec report** | PostToolUse git commit (24h) | No | Drift Control only | Exec report PR + wiki refresh |
| **Clean state** | Stop | Yes | All modes | Blocks stop with uncommitted/unpushed + persona check |
| **Session start** | SessionStart | No | All modes | Cycle count + roadmap reminder |

### Reports & Feedback (via GitHub PRs)

| Report | Cadence | Purpose |
|--------|---------|---------|
| **Product Review PR** | Every 20 cycles | Full designer + engineer discussion. Sprint-level direction. Comment to nudge priorities. |
| **Exec Report PR** | Once per day | High-level metrics, strategic direction. Comment for strategic feedback. |

Feedback flow: Exec PR feedback → shapes roadmap → Product Review reads it → shapes sprint → Autopilot executes.

### Monitoring

```bash
tail -f ~/drift-self-improve-logs/watchdog.log          # Watchdog events
tail -f $(ls -t ~/drift-self-improve-logs/session_*.log | head -1)  # Live session
cat ~/drift-state/cycle-counter                          # Cycle count
cat ~/drift-state/last-review-cycle                      # Last review
date -r $(cat ~/drift-state/last-testflight-publish) 2>/dev/null    # Last TestFlight
cat ~/drift-state/last-coverage-snapshot                 # Coverage %
gh pr list --label report                                # Open report PRs
gh issue list --state open --label bug                   # Open bugs
```

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
| `Docs/human-reported-bugs.md` | User bug reports — fix these first |
| `Docs/improvement-log.md` | Loop cycle log |
| `Docs/principles/` | Code quality reference cards (Clean Code, Design Patterns, DDD, SwiftUI) |
| `program.md` | **Drift Autopilot** — the single autonomous loop program |

## Rules
- Build and test after every change
- All 729+ unit tests (DriftTests) must pass before committing
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

## Build & Test

**CRITICAL: Never run multiple `xcodebuild test` in parallel.** They fight for the simulator and deadlock. Always kill stale processes first.

```bash
cd /Users/ashishsadh/workspace/Drift

# Build
xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Unit tests (729+ fast tests, ~10s) — ALWAYS kill stale processes first
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
`/Users/ashishsadh/workspace/Drift` (was renamed from Calibrate).
