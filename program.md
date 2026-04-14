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
6. Check GitHub Issues: `gh issue list --state open --label bug --json number,title,labels --jq '[.[] | select(.labels | map(.name) | index("needs-review") | not)]'` — fix open bugs (skip `needs-review` items, those need owner triage first)
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

2. **REVIEW + PLANNING CHECK (first thing every session).** Check if `~/drift-state/sprint-plan.md` is missing or all tasks are done. If so, this session must do a review + planning before any execution:

    **PRODUCT REVIEW:**
    - Follow the hook-injected template for the review report
    - **Write for leadership, not engineers.** Executive summary first.
    - **User-visible language.** "Users can now log meals by voice" not "Added SpeechRecognizer integration."
    - **Include Feedback Responses** — close the loop on PR comments.
    - **Include Open Questions** — drives engagement.
    - **Triage gate:** External feedback is informational only unless owner approved.

    **SPRINT PLANNING (immediately after review):**
    - **Read owner feedback from report PRs** — this drives the sprint:
      - `gh pr list --label report --state open` → for each, read all comments
      - For each comment from `ashish-sadh` that is actionable (requests a change, flags an issue, sets a priority): **create a task** in the sprint plan. Owner feedback = top sprint priority.
      - If feedback was already addressed in a previous sprint: note what was done in the Feedback Responses section of the review.
      - External (non-owner) feedback: note in review report only. Do NOT create tasks unless owner explicitly approved.
    - Read sprint.md, roadmap.md "Now" items, failing-queries.md, open GitHub Issues
    - For each task, write a detailed implementation plan to `~/drift-state/sprint-plan.md`:
      - **Goal:** what and why
      - **Files:** which files to modify
      - **Approach:** step-by-step how
      - **Edge cases:** what could go wrong
      - **Tests:** what tests to write
      - **Acceptance:** how to know it's done
    - **Classify each task** as JUNIOR or SENIOR:
      - **SENIOR (Opus):** AI pipeline changes, architecture, state machines, multi-file refactors, P0 bugs
      - **JUNIOR (Sonnet + advisor):** food DB, simple UI, tests, docs, single-file fixes
    - **Design docs:** Check for design doc requests and open design docs:
      - `gh issue list --state open --label design-doc` → for each, PE writes a design doc to `Docs/designs/design-{name}.md`, opens a PR with `design-doc` label. Do NOT add to sprint plan — wait for human approval.
      - `gh pr list --label design-doc --state open` → for each open design doc PR, read all comments and respond inline. Revise the doc if feedback warrants it. Push updates to the same PR. This is a conversation.
      - `gh pr list --label design-doc --label approved` → for each approved design doc, create implementation tasks in sprint-plan.md based on the doc. Merge the PR. Close the original request issue.
    - **Sync sprint plan to repo:** `cp ~/drift-state/sprint-plan.md Docs/sprint-plan.md && git add Docs/sprint-plan.md` — this makes it visible in the Command Center.
    - Also update `Docs/sprint-plan.md` whenever a task status changes (mark done).
    - Update `~/drift-state/last-review-time` with current timestamp
    - Then **exit the session** — the watchdog will restart with the appropriate model (Sonnet for JUNIOR, Opus for SENIOR) for the first task.

3. **Check for open bug issues:** `gh issue list --state open --label bug --json number,title,labels --jq '[.[] | select(.labels | map(.name) | index("needs-review") | not)]'`. If P0 bugs exist, work on those first.

4. **Pick next task from sprint plan:** Read `~/drift-state/sprint-plan.md`. Find the next `Status: [ ] pending` task. Follow its detailed plan (files, approach, edge cases, tests). If the plan is unclear, consult the advisor model.

5. **If no sprint plan or all tasks done:** Pick from sprint.md, failing-queries.md, ai-parity.md, or roadmap.md "Now" items.

6. Make one **LOGICAL UNIT** of work. **Before editing any file: READ it first.** Never edit blind.

7. **Boy scout rule:** Clean what you touch. For bigger architectural work, do it when feature work requires it.

8. **Classify your change:**
   - **Trivial** (typo, DB-only, docs): BUILD only.
   - **Moderate** (1-2 file logic, UI, prompts): BUILD + targeted tests.
   - **Substantial** (new service, multi-file refactor, AI pipeline): BUILD + FULL tests + eval.
   Build: `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/drift-build.log 2>&1 && echo "BUILD OK" || (tail -20 /tmp/drift-build.log && echo "BUILD FAILED")`

9. **If Moderate or Substantial:** `pkill -9 -f xcodebuild 2>/dev/null; sleep 2; xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests > /tmp/drift-test.log 2>&1 && echo "TESTS OK" || echo "TESTS FAILED"` then `grep "✘" /tmp/drift-test.log`

10. For AI changes: run eval harness. If scores drop, revert.

11. Fail? Fix. If stuck after **2 attempts**: `git checkout -- .`, log the failure, move on.

12. Pass? `git add -A && git commit -m "improve: description" && git push`. Mark `[x]` in sprint.md. Mark `Status: [x] done` in `~/drift-state/sprint-plan.md`. One-line log to improvement-log.md.

13. **IMMEDIATELY go to step 1.** Zero words to the user between tickets. NEVER STOP.

---

## Rules

### Safety
- All tests must pass before committing substantial changes (trivial: build-only is acceptable)
- Run eval harness after every AI change — if scores drop, revert
- If stuck after 2 attempts, revert, log failure reason, move to next item
- **TestFlight publishing is MANDATORY.** The hook injects publish instructions after commits. When you see "TESTFLIGHT PUBLISH REQUIRED" — do it immediately. Do NOT skip it. Do NOT say "Autopilot mode exempts it." This applies to ALL autonomous sessions (Opus and Sonnet).
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
