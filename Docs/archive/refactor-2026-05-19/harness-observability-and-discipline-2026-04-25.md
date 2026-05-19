# Harness Observability + Plan-Comment Discipline

**Status:** plan only — NOT executed.
**Date authored:** 2026-04-25
**Inspired by:** garrytan/gbrain `docs/ethos/THIN_HARNESS_FAT_SKILLS.md`

## Context

Two real complaints from the human:

1. **Issues aren't getting updated with plans before implementation.** `program.md` line 97 mandates "post a plan comment on the GitHub issue BEFORE writing any code." Audit of 20 recent closed sprint-task issues: only **3/20 (15%)** posted plan comments. SENIOR/Opus does it ~25% of the time; JUNIOR/Sonnet ~8%. Currently a soft warning at session-exit (`ensure-clean-state.sh:131`), never a hard gate.
2. **No live visibility into what an autopilot session is currently working on.** `heartbeat.json` shows activity volume but not content. A `live-status` issue is manually maintained by sessions in free-text — fragile, not parseable. No way to answer "what's the senior working on RIGHT NOW, at what step, for how long?"

## Lens: THIN_HARNESS_FAT_SKILLS

Garry Tan's thesis (verbatim from the doc): **"Push intelligence UP into skills, push execution DOWN into deterministic tools, keep the harness THIN."** Anti-patterns to avoid:

- "A fat harness with thin skills: 40+ tool definitions eating half the context window."
- Bloated CLAUDE.md / context dumping. His 20K-line CLAUDE.md got cut to ~200 lines of pointers.
- Procedures repeated as one-off prompts instead of codified skills.

Applied to Drift: **don't fix these complaints by adding more imperative text to `program.md` or more eager-loading to `session-start.sh`.** Fix them with deterministic gates (hooks) for the discipline problem and a structured state file for the visibility problem.

## The fixes

### Fix 1 — Plan-comment enforcement (deterministic gate)

**Goal:** make plan-comment-before-implementation a build failure, not a suggestion.

**Approach:** new PreToolUse hook on `git commit ...`. The hook:

1. Reads `~/drift-state/sprint-state.json` to find the current `in_progress` issue number `N`.
2. If no in-progress issue (e.g., heartbeat commit, planning commit), allow.
3. Otherwise: `gh issue view $N --json comments --jq '.comments[].body'` and check for a comment matching the regex `(?i)^(plan|approach|investigation)\s*[:\-]`.
4. If absent: block with exit 2 and a message:
   ```
   Issue #N has no plan comment yet. Post one before committing:

       gh issue comment N --body "Plan: <root cause + fix approach + files>"

   Skip with DRIFT_SKIP_PLAN_COMMENT=1 only if you posted the plan in the original issue body (not a comment) and want to acknowledge that.
   ```
5. Honor `DRIFT_SKIP_PLAN_COMMENT=1` env var as the documented escape hatch.

**Edge cases handled:**
- P0 emergency bugs (per program.md: "not needed for P0 bugs in emergency"). Detect via labels on the issue; bypass for `P0` AND `bug` AND `emergency`-tagged issues.
- Permanent tasks (per program.md: should comment "Progress: ..." rather than "Plan: ..."). Accept `(?i)^progress\s*[:\-]` for issues labeled `permanent-task`.

**Why this fits THIN_HARNESS:** ~40 lines of bash, deterministic, no LLM in the loop. The "what's a plan comment" judgment is encoded as a regex; the rest is plumbing.

**Critical files:** `.claude/hooks/require-plan-comment.sh` (new), `.claude/settings.json` (register PreToolUse hook).

### Fix 2 — Structured session status file (visibility primitive)

**Goal:** at any moment, answer "what is the autopilot doing right now?" without reading log lines.

**Approach:** a single JSON file `~/drift-state/session-status.json` with the shape:

```json
{
  "session_id": "senior-2026-04-25T16:38:38Z",
  "session_type": "senior",
  "model": "sonnet",
  "task_number": 451,
  "task_title": "Fix supplements 'mark all' inverted state",
  "task_started_at": 1777160438,
  "step": "implementing",
  "step_started_at": 1777160622,
  "files_touched": ["Drift/Views/Supplements/SupplementListView.swift", "Drift/ViewModels/SupplementViewModel.swift"],
  "last_event_at": 1777160701,
  "last_event_kind": "edit"
}
```

**How it gets written:**

- **On `sprint-service.sh claim N`** (already a centralized chokepoint): write `task_number`, `task_title`, `task_started_at`, `step="claimed"`. Use the new `atomic_write_file` helper from this session's earlier work.
- **PreToolUse hook on `Edit`/`Write`** (`.claude/hooks/track-edit.sh`): append the file path to `files_touched`; set `step="implementing"`; bump `last_event_at` and `last_event_kind="edit"`.
- **PreToolUse hook on `Bash`**: a tiny pattern-match. If command starts with `xcodebuild build` → `step="building"`; with `xcodebuild test` or `swift test` → `step="testing"`; with `git commit` → `step="committing"`.
- **On `sprint-service.sh done N`** (existing chokepoint): write `step="done"` then atomically truncate the file (or rename to `~/drift-state/session-status.last.json` for postmortem) and start fresh on next claim.

**Why this fits THIN_HARNESS:** the file is data, not behavior. Hooks that write it are 5–10 lines each, deterministic, no LLM. The "step" labels (`claimed`/`implementing`/`building`/`testing`/`committing`/`done`) are a small enum, not free text.

**Critical files:** `~/drift-state/session-status.json` (new state file), `scripts/sprint-service.sh` (write on claim/done), `.claude/hooks/track-edit.sh` (new), `.claude/hooks/track-bash-step.sh` (new), `.claude/settings.json` (register hooks).

### Fix 3 — `scripts/session-status.sh status` reader (CLI surface)

**Goal:** humans answer "what's it doing?" with one command.

**Approach:** a small bash script that:

1. Reads `~/drift-state/session-status.json`.
2. Pretty-prints:
   ```
   ⚙️  senior session (sonnet) — cycle 7261

   Working on:  #451 "Fix supplements 'mark all' inverted state"
   Started:     12 min ago
   Step:        implementing
   Step age:    2 min
   Files:       2 touched
                Drift/Views/Supplements/SupplementListView.swift
                Drift/ViewModels/SupplementViewModel.swift
   Last event:  edit, 47s ago
   ```
3. If file missing or empty: "No active session" with a hint to check `~/drift-control.txt`.

**Critical files:** `scripts/session-status.sh` (new). ~50 lines.

### Fix 4 — Command Center surfaces session-status.json

**Goal:** the web UI gets a real "right now" panel, not a 5-min activity heatmap.

**Approach:** the existing `command-center/index.html` + `app.js` already has `loadLiveStatus()` polling a `live-status`-labeled GitHub issue every 30s. Replace that with a fetch of `command-center/session-status.json` (committed by the watchdog or the hooks themselves on each event). Display the structured fields above.

**Why fold this here:** today the live-status issue is manually maintained free-text by the session — exactly the anti-pattern (LLM doing what a deterministic hook should do). Moving to a hook-written JSON file is the THIN_HARNESS move.

**Critical files:** `command-center/index.html`, `command-center/app.js`, watchdog or hook to commit+push `session-status.json` periodically (every 60s if changed).

## What NOT to do (per THIN_HARNESS lens)

- **Don't add more imperative text to `program.md`.** It's already long. Adding "remember to post a plan comment!" reminders won't move the needle (audit shows 15% compliance — exhortation isn't working).
- **Don't expand `session-start.sh`** with more reminders. It's the eager-load file; gbrain says trim, don't grow. The PreCommit gate (Fix 1) replaces all reminders with one hard stop at the right moment.
- **Don't write the session status into a GitHub issue.** That's the current pattern and it's broken (manual, free-text, fragile, costs API budget per update). Local JSON file + commit-push is cleaner and free.
- **Don't add an LLM-judgment step** to detect plan comments. A regex is sufficient; if a session writes "I plan to do X" without using the heading "Plan:", that's a discipline failure the regex correctly punishes.
- **Don't introduce a new orchestration layer** (queue, supervisor wrapper, etc.). The watchdog is already that. Borrow patterns, don't replace.

## Out of scope (deliberately deferred)

- **Refactoring `program.md` into per-mode skill files** (`skills/planning.md`, `skills/senior.md`, `skills/junior.md`) invoked via slash commands. This IS the THIN_HARNESS-aligned move, but it's a big refactor. Worth doing in a separate session once the current bugs are settled.
- **Resolver pattern for context loading.** Today `session-start.sh` eagerly loads sprint state, design docs, focus, etc. A resolver would lazy-load. Same scope as the program.md split — defer.
- **Per-session "who's running what" dashboard** across multiple repos. Drift only runs autopilot in one repo today; this is over-engineering until a second repo joins.
- **Auditing all hooks for thin-harness compliance.** 18 hooks today; some are probably worth folding into skills or removing. Separate audit.

## Recommended order of execution

1. **Fix 1** (plan-comment hook) — ~30 min. Single file, single regex, no schema design. Ship first.
2. **Fix 2** (session-status.json schema + write hooks) — ~90 min. Define schema once, wire 4 hook points (claim, edit, bash-step, done).
3. **Fix 3** (CLI reader) — ~30 min. Trivial once Fix 2 lands.
4. **Fix 4** (Command Center wiring) — ~60 min. JS changes + commit/push of the JSON.

Total: ~3.5 hours.

## Verification

For each fix:

1. **Fix 1:** with `~/drift-state/sprint-state.json` containing `in_progress: 999`, run `git commit -m test` → expect block with the help message. Then `gh issue comment 999 --body "Plan: test"` and retry → expect commit allowed. Then `DRIFT_SKIP_PLAN_COMMENT=1 git commit -m test` → expect commit allowed without plan.
2. **Fix 2:** simulate `sprint-service.sh claim 999` → cat `~/drift-state/session-status.json`, expect `task_number=999`, `step="claimed"`, `task_started_at=<now>`. Edit a file → expect `files_touched` grows, `step="implementing"`. Run `xcodebuild build ...` → expect `step="building"`.
3. **Fix 3:** with the file populated, run `scripts/session-status.sh status` → expect the formatted block above. With the file missing, expect "No active session."
4. **Fix 4:** open `command-center/index.html` in a browser; with `session-status.json` present, expect a "Right Now" panel showing the structured fields.

After all four: run `swift test` (850), `xcodebuild test -only-testing:DriftTests` (1211). No Swift code changes; sanity only.

## Risk + revert plan

- All changes are isolated to `scripts/`, `.claude/hooks/`, `command-center/` and one new state file. No DriftCore / iOS source changes.
- Each fix is a separate commit. Revert any single one if it misbehaves.
- The plan-comment hook has an explicit escape hatch (`DRIFT_SKIP_PLAN_COMMENT=1`) so a misfire never blocks emergency work.
- Drift control stays on `PAUSE` throughout; resume after the human verifies all four items.

## Companion files for the agent that picks this up

- `program.md` — already references plan comments at lines 97, 118; no edits needed (the hook enforces what program.md already promises)
- `scripts/lib/atomic-write.sh` — use this for `~/drift-state/session-status.json` writes
- `~/drift-state/sprint-state.json` — read this to find `in_progress` for Fix 1
- `command-center/heartbeat.json` — leave this alone; it's the activity-volume artifact, complementary to session-status.json which is the "current task" artifact.
