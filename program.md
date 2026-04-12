# Drift Self-Improvement

Autonomous loop. Follow this exactly.

## Steering notes

**Re-read before every cycle.** Human may change at any time.

_Directive:_ **Work through sprint.md top-down. Bugs first, then P0/P1 items. When finite items are done, rotate through Permanent Tasks: (1) AI chat & tool service — the showstopper, especially natural meal logging from freeform text, (2) UI polish — find rough edges, beautify across the whole app, (3) bug hunting — find bugs before users do, improve testing, (4) food DB enrichment — correct and expand. Never idle — there's always work in Permanent Tasks.**

_Override:_ STOP

---

## Starting up

**Fresh start:**
1. Read `CLAUDE.md`
2. Read `Docs/ai-parity.md` — this is what to build next
3. Read `Docs/sprint.md` — prioritized work items
4. Read `Docs/human-reported-bugs.md` — fix these FIRST
5. Build: `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "OK" || echo "FAIL"`
6. Start the loop

**Recovery (interrupted mid-cycle):**
- `git status && git log --oneline -5`
- Uncommitted changes? Finish or `git checkout -- .`
- Resume the loop

---

## The loop

LOOP FOREVER — do NOT stop between tickets:

1. Re-read steering notes above. Stop only if override says STOP.
2. If sprint.md has no unchecked items: pick next failing query from `Docs/failing-queries.md`, or next gap from `Docs/ai-parity.md`, and add to sprint.
3. Pick top unchecked item from sprint.md.
4. Make ONE change. Read only files you need. Edit. Done.
5. `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "BUILD OK" || (tail -20 /tmp/drift-build.log && echo "BUILD FAILED")`
6. **Kill stale processes first**, then test: `pkill -9 -f xcodebuild 2>/dev/null; sleep 2; xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-test.log 2>&1 && echo "TESTS OK" || echo "TESTS FAILED"` then `grep "✘" /tmp/drift-test.log`
7. For AI changes: `xcodebuild test ... -only-testing:'DriftTests/AIEvalHarness' > /tmp/drift-eval.log 2>&1 && echo "EVAL OK" || echo "EVAL FAILED"`. If scores drop, revert.
8. Fail? Fix or `git checkout -- .`. Pass? `git add -A && git commit -m "improve: description" && git push`
9. Mark `[x]` in sprint.md. If it was from ai-parity.md, mark there too. One-line log to improvement-log.md.
10. **IMMEDIATELY go to step 1.** Zero words to the user between tickets. NEVER STOP.

---

## Rules

- All 743+ tests must pass before committing
- Run eval harness after every AI change — if scores drop, revert
- Write tests for any new service/logic code. Coverage targets: **80%** pure logic, **50%** services
- Run `./scripts/coverage-check.sh` periodically. Fix files below threshold before moving on
- Every 5th cycle: run coverage check and write tests if new code is uncovered
- Each cycle closes one gap or fixes one failing query. Stay focused.
- When fixing a failing query: fix the CATEGORY (all similar phrasings), not just the exact string. Add 3+ variant tests to eval harness. Test both model paths. Move to Fixed section in failing-queries.md.
- Redirect ALL command output to `/tmp/` — never flood context
- Keep text responses under 3 sentences
- Only read files you are about to edit
- Do NOT publish TestFlight — human will say "publish" when ready
- POC work on branches, not main
- No MacroFactor references. Privacy-first. No cloud.
- New ideas go to `Docs/backlog.md`, not inline
- If stuck after 3 attempts, revert, log failure, move to next item

---

## For the human

Start: `cd /Users/ashishsadh/workspace/Drift` → tell Claude "run self-improvement"

Steer: edit steering notes above. Agent re-reads every cycle.

Stop: change override to `STOP`.

Priorities: edit `Docs/sprint.md` or `Docs/ai-parity.md`.
