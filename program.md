# Drift Self-Improvement

Autonomous loop. Follow this exactly.

## Steering notes

**Re-read before every cycle.** Human may change at any time.

_Directive:_ **Work top-down through sprint.md. Bugs first.**

_Override:_ CONTINUE

---

## Starting up

**Fresh start:**
1. Read `CLAUDE.md`
2. Read `Docs/sprint.md` — this is where priorities live
3. Read `Docs/human-reported-bugs.md` — fix these FIRST
4. Build: `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "OK" || echo "FAIL"`
5. Start the loop

**Recovery (interrupted mid-cycle):**
- `git status && git log --oneline -5`
- Uncommitted changes? Finish or `git checkout -- .`
- Resume the loop

---

## The loop

LOOP FOREVER — do NOT stop between tickets:

1. Re-read steering notes above. Stop only if override says STOP.
2. If sprint.md has no unchecked items: refill from roadmap.md / backlog.md / human-reported-bugs.md.
3. Pick top unchecked item from sprint.md.
4. Make ONE change. Read only files you need. Edit. Done.
5. `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "BUILD OK" || (tail -20 /tmp/drift-build.log && echo "BUILD FAILED")`
6. `xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-test.log 2>&1 && echo "TESTS OK" || echo "TESTS FAILED"` then `grep "✘" /tmp/drift-test.log`
7. Fail? Fix or `git checkout -- .`. Pass? `git add -A && git commit -m "improve: description" && git push`
8. Mark `[x]` in sprint.md. One-line log to improvement-log.md.
9. **IMMEDIATELY go to step 1.** Do not summarize. Do not pause. Do not ask the human anything. Do not output more than 1 sentence between tickets. The next tool call after committing must be reading sprint.md for the next ticket. NEVER STOP.

---

## Rules

- All 729+ tests must pass before committing
- Redirect ALL command output to `/tmp/` — never flood context
- Keep text responses under 3 sentences — save context for code
- Only read files you are about to edit — don't browse
- Run eval harness after AI changes: `xcodebuild test ... -only-testing:'DriftTests/AIEvalHarness' > /tmp/drift-eval.log 2>&1`
- Don't publish TestFlight unless steering says to
- POC work on branches, not main
- No MacroFactor references. Privacy-first. No cloud.
- New ideas go to `Docs/backlog.md`, not inline
- If stuck after 3 attempts, revert, log failure, move to next item

---

## For the human

Start: `cd /Users/ashishsadh/workspace/Drift` → tell Claude "run self-improvement"

Steer: edit steering notes above. Agent re-reads every cycle.

Stop: change override to `STOP`.

Priorities: edit `Docs/sprint.md` — that's the single source of truth.
