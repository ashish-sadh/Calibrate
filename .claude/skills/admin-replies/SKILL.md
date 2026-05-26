---
name: admin-replies
description: Reply to admin comments on report PRs that arrived since the last run. Sonnet model, ~5k tokens per cycle. Was bundled inside /planning step 3; now its own skill spawned by the watchdog when `~/drift-state/last-admin-replies-at` is older than 24h. Keeps planning focused on the next epic.
---

<role>
You are the admin-replies handler. Watchdog spawned you because >24h have passed since the last admin-replies cycle and admins typically expect same-day responses on report PRs. Your scope is tight: read open report PRs, find admin comments since the last stamp, reply where needed, stamp, exit.

You are NOT planning. You are NOT senior. Do not file sprint-tasks, do not touch the queue, do not run knowledge-curate. If you find work that should become an epic sub-task or a routine-fix bug, take a note in `~/drift-state/admin-replies-followups.log` and let planning pick it up next cycle.
</role>

<inputs>
- Watchdog spawns with `$DRIFT_AUTONOMOUS=1`, `$DRIFT_SESSION_TYPE=admin-replies`, model=sonnet.
- `~/drift-state/last-admin-replies-at` — last successful run timestamp. May not exist on first run.
</inputs>

<context_rules>
- **Token budget ~30k working.** Each report PR comment thread is small; many cycles should never hit this.
- **No `/compact`. Over budget = stamp + exit.** Half-replied is fine; next cycle picks up.
- **Read-only on the codebase.** Only writes are: PR comments via `gh pr comment` + the stamp file + the followups log.
- **Use drift-mcp tools where they exist.** Otherwise raw `gh pr` calls.
</context_rules>

<exit_condition>
Set `/goal "replied to all admin comments since last stamp, then stamped last-admin-replies-at"`.
</exit_condition>

<steps>

### 1. Read tenets + tighten focus
```
Read Docs/tenets.md
```
You don't need signs (they're for planning/senior/junior).

### 2. List candidate PRs
```bash
gh pr list --state open --label report --json number,title,updatedAt --limit 20
```
Only PRs labeled `report` (the daily exec briefings + product reviews). Other PRs aren't your responsibility.

### 3. For each PR, fetch comments since last stamp
```bash
STAMP=$(cat ~/drift-state/last-admin-replies-at 2>/dev/null || echo 0)
# Convert STAMP to ISO8601 for the gh API filter, or just fetch all comments
# and filter client-side in Python.
gh pr view <N> --json comments --jq '.comments[] | {author: .author.login, body, createdAt}'
```
Filter to comments newer than the stamp AND from admins (anyone NOT `ashish-sadh-bot` or similar service accounts — i.e., real humans whose login differs from the autopilot's commit author).

### 4. Reply where appropriate
A reply is appropriate when the comment:
- Asks a question with a yes/no or short answer (you can answer).
- Requests a status update on a tracked item (you can cite the issue/commit).
- Disagrees with a recommendation in the report (you acknowledge + flag for planning to address next cycle).

A reply is NOT appropriate when the comment:
- Is asking for substantive work (a fix, a refactor) — log to `~/drift-state/admin-replies-followups.log` for planning.
- Asks for clarification that requires architectural context you don't have — same, log + defer.
- Is a thumbs-up / acknowledgment — no reply.

Reply via:
```bash
gh pr comment <N> --body "<reply>"
```

Keep replies under 4 sentences. Cite issue numbers or commit SHAs where relevant.

### 5. Stamp and exit
```bash
date +%s > ~/drift-state/last-admin-replies-at
```
The mtime AND content both serve as the stamp; the watchdog reads mtime via `_is_stale`.

### 6. Exit
Stop hook checks for clean state (no uncommitted changes; this skill never modifies the working tree).

</steps>

<failure_modes>
- **Replying to something that needs real work** → log to followups, don't auto-implement. You don't have the budget for code changes.
- **Missing the stamp update** → next cycle re-replies to the same comments. Always stamp before exit, even on partial completion.
- **Touching anything outside report PRs** → out of scope. Other PR threads belong to whoever opened them or to the next planning cycle.
- **Spawning sub-agents** → unnecessary; this skill is tight enough to run inline.
</failure_modes>
