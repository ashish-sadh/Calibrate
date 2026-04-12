# Drift Autopilot

Autonomous loop. Follow this exactly.

## Steering notes

**Re-read before every cycle.** Human may change at any time.

_Directive:_ **Read `Docs/roadmap.md` to understand product direction. Pick work that advances the current phase. Work through sprint.md top-down — bugs first, then P0/P1 items. When finite items are done, rotate through Permanent Tasks guided by the roadmap's "Now" items. Be bold — a full UI redesign or AI chat state machine rewrite is fine. The goal is visible, meaningful progress every cycle.**

_Override:_ STOP

---

## Starting up

**Fresh start:**
1. Read `CLAUDE.md`
2. Read `Docs/roadmap.md` — understand where the product is heading and why
3. Read `Docs/ai-parity.md` — what to build next for AI chat
4. Read `Docs/sprint.md` — prioritized work items
5. Read `Docs/human-reported-bugs.md` — fix these FIRST
6. Check GitHub Issues: `gh issue list --state open --label bug` — fix open bugs
7. Build: `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "OK" || echo "FAIL"`
8. Start the loop

**Recovery (interrupted mid-cycle):**
- `git status && git log --oneline -5`
- Uncommitted changes? Finish or `git checkout -- .`
- Resume the loop

---

## The loop

LOOP FOREVER — do NOT stop between tickets:

1. Re-read steering notes above. Stop only if override says STOP.
2. Check for open bug issues: `gh issue list --state open --label bug`. If P0 bugs exist, work on those first.
3. If sprint.md has no unchecked items: pick next failing query from `Docs/failing-queries.md`, or next gap from `Docs/ai-parity.md`, or next "Now" item from `Docs/roadmap.md`, and add to sprint.
4. Pick top unchecked item from sprint.md.
5. Make one **LOGICAL UNIT** of work. This can span multiple files if they are part of the same change (e.g., a service + its tests + the view that calls it, or a theme change across 10 views). **Before editing any file: READ it first** — understand its types, signatures, imports, and conventions. Never edit blind.
6. **Boy scout rule:** When you edit a file, if you see obvious code smells in the area you touched (long function, bad naming, dead code, DDD violations, missing error handling), fix them in the same commit. Don't go looking for problems elsewhere — just clean what you touched. For bigger architectural work (ViewModel extraction, service decomposition), do it when feature work requires it.
7. **Classify your change:**
   - **Trivial** (typo, comment, single-line fix, DB-only, docs): BUILD only — skip tests.
   - **Moderate** (new logic in 1-2 files, UI changes, prompt text): BUILD + targeted tests (`-only-testing:DriftTests/RelevantTestClass`).
   - **Substantial** (new service, multi-file refactor, AI pipeline change): BUILD + FULL test suite + eval harness if AI-related.
   Build: `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "BUILD OK" || (tail -20 /tmp/drift-build.log && echo "BUILD FAILED")`
8. **If Moderate or Substantial:** `pkill -9 -f xcodebuild 2>/dev/null; sleep 2; xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests > /tmp/drift-test.log 2>&1 && echo "TESTS OK" || echo "TESTS FAILED"` then `grep "✘" /tmp/drift-test.log`
9. For AI changes: `xcodebuild test ... -only-testing:'DriftTests/AIEvalHarness' > /tmp/drift-eval.log 2>&1 && echo "EVAL OK" || echo "EVAL FAILED"`. If scores drop, revert.
10. Fail? Fix. If stuck after **2 attempts**: `git checkout -- .`, log the failure reason, move on.
11. Pass? `git add -A && git commit -m "improve: description" && git push`. Mark `[x]` in sprint.md. One-line log to improvement-log.md.
12. **Every 20th cycle: PRODUCT REVIEW.** (Hooks inject this reminder with the full template.) The hook tells you exactly what to write and in what structure. Key principles:
    - **Write for leadership, not engineers.** Execs have 60 seconds. Executive summary first.
    - **User-visible language.** "Users can now log meals by voice" not "Added SpeechRecognizer integration."
    - **Scorecard is pass/fail.** Not paragraphs — one-line status per goal.
    - **Include Feedback Responses** — close the loop on any comments from previous reports.
    - **Include Open Questions** — this drives engagement and steering from leadership.
    - **Designer × Engineer discussion** should be readable narrative, not bullet lists.
    - **Never wait for human feedback.** Read it if it's there, keep going if not.
13. **IMMEDIATELY go to step 1.** Zero words to the user between tickets. NEVER STOP.

---

## Rules

### Safety
- All tests must pass before committing substantial changes (trivial: build-only is acceptable)
- Run eval harness after every AI change — if scores drop, revert
- If stuck after 2 attempts, revert, log failure reason, move to next item
- TestFlight publishes automatically every 3 hours via hook. Follow the instructions when they appear.
- POC work on branches, not main
- No MacroFactor references in code/UI. Privacy-first. No cloud.

### Quality
- **READ before EDIT.** Before modifying any file, read it first. Understand its types, function signatures, imports. Non-negotiable.
- **Boy scout rule.** Clean what you touch. Don't scan for violations in files you're not working on.
- For bigger architecture work (DDD, ViewModel extraction, DI), do it when feature work requires it — not in blanket sweeps. Read `Docs/principles/` for guidance.
- Write tests for any new service/logic code. Coverage targets: **80%** pure logic, **50%** services.
- Run `./scripts/coverage-check.sh` periodically. Fix files below threshold.
- When fixing a failing query: fix the CATEGORY, not just the exact string. Add 3+ variant tests.

### Scope
- One **LOGICAL UNIT** of work per cycle. Multi-file changes encouraged when logically related. No line limit.
- **Bold changes welcome:** full theme overhaul, AI chat state machine rewrite, new UI layouts.
- For UI changes: **ALWAYS app-wide**. Never change one view's style without updating all others.
- For AI chat: prefer architectural improvements over keyword additions.
- Reference `Docs/roadmap.md` every cycle to stay aligned with product direction.

### Hygiene
- Redirect ALL command output to `/tmp/` — never flood context
- Keep text responses under 3 sentences
- New ideas go to `Docs/backlog.md`, not inline
- Run `xcodegen generate` if you add new files to the project
- File bugs as GitHub Issues (`gh issue create --label bug`), not just in docs

---

## For the human

Start: `cd /Users/ashishsadh/workspace/Drift` → tell Claude "run autopilot"

Drift Control: `echo "RUN" > ~/drift-control.txt && ./scripts/self-improve-watchdog.sh`

Steer: edit steering notes above. Agent re-reads every cycle.

Stop: change override to `STOP`.

Drain: `echo "DRAIN" > ~/drift-control.txt` — finishes current cycle, then stops.

Priorities: edit `Docs/sprint.md`, `Docs/roadmap.md`, or `Docs/ai-parity.md`.

Feedback: comment on report PRs on GitHub. Next review cycle reads and incorporates.
