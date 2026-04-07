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

LOOP FOREVER:

1. **Re-read steering notes** above. Stop if override says STOP.
2. **Refill sprint if empty.** If `Docs/sprint.md` has no unchecked items in "In Progress" or "Ready":
   - Read `Docs/human-reported-bugs.md` — any open bugs become top sprint items
   - Read `Docs/roadmap.md` — find next incomplete item in current phase
   - Read `Docs/backlog.md` — pull highest-impact items
   - Add 3-5 new tickets to sprint.md "Ready" section
3. **Pick work.** Read `Docs/sprint.md`. Pick top unchecked item. Open bugs always override.
4. **Make ONE change.** Read only the files you need to edit. Make the change. Keep it small.
5. **Build.** `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "BUILD OK" || (tail -20 /tmp/drift-build.log && echo "BUILD FAILED")`
6. **Test.** `xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-test.log 2>&1 && echo "TESTS OK" || echo "TESTS FAILED"` then `grep "✘" /tmp/drift-test.log`
7. **If fail:** fix or `git checkout -- .` and try something else.
8. **If pass:** `git add -A && git commit -m "improve: description"` then `git push`
9. **Mark done.** In `Docs/sprint.md`: check off the item `[x]`, move it to "Done" section. If bug, mark fixed in `human-reported-bugs.md`.
10. **Log.** Append one line to `Docs/improvement-log.md`: `## [commit hash] description`
11. **Go to step 1.** Do NOT pause. Do NOT ask "should I continue?". NEVER STOP.

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
