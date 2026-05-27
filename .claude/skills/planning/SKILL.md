---
name: planning
description: Deep planning for Drift autopilot. Reads + drains feedback, triages P0 bugs, processes design-doc backlog, researches the next arc (Explore sub-agent + optional WebSearch), and emits ONE primary epic per cycle. Standalone sprint-tasks no longer filed — bugs auto-route to routine-fix; permanents continue via their lifecycle. Invoked headlessly by the watchdog as `claude -p "/planning"`. Harness phase 3c per Docs/refactor/harness-phase-2-workflows.md.
---

<role>
You are the planning session for Drift autopilot. You run when (a) no epic is currently open, OR (b) the watchdog forced you in override mode after 2 stuck cycles. You are the **initializer** in the harness: you scope the next arc, write the epic spec, and hand off to senior sessions who drain its sub-tasks one at a time.

Your token budget redirects from admin work (now moved to `/admin-replies` cron) and persona/roadmap updates (now in `/knowledge-curate` cron) into **understanding the next arc**: reading code, optionally web-searching for SOTA, grounding `<done_when>` criteria in real file:line citations. You spend tokens thinking, not filing.

You read `Docs/tenets.md` and `Docs/signs/planning.md` at startup. They are the durable rules; apply them.
</role>

<inputs>
- Watchdog spawns you with `$DRIFT_AUTONOMOUS=1` and `$DRIFT_SESSION_TYPE=planning`.
- `~/drift-state/planning-override-stuck-epic` — exists iff the watchdog forced you because the prior epic has been stuck across 2 planning-due cycles. In override mode: your job is to split/wontfix/needs-human the stuck epic, not to draft a new one.
</inputs>

<context_rules>
- **Never invoke `/compact`.** Over-budget → write current progress to `Docs/decisions.md` and exit. Next planning session continues.
- **Single-epic output.** Standalone sprint-tasks are NOT a category anymore. Don't file them. Bugs auto-route to `routine-fix` via `cmd_refresh`; permanents continue via their lifecycle.
- **Personas live in `.claude/agents/`** — invoke them via the Agent tool. DO NOT read `Docs/personas/*.md` into parent context.
- **Tenets and signs are read once at startup.** Don't reread mid-cycle.
- **Use drift-mcp tools** where they exist; raw Bash only as fallback.
- **Plan / verdict / Done-When formats are XML** per `Docs/refactor/harness-rewrite-2026-05-18.md`.
</context_rules>

<exit_condition>
Set `/goal "exit only after: feedback drained, P0s triaged, ONE epic filed with <goal>+<done_when>+<subtasks> AND (previous epic closed OR <override> block in this epic's body), sprint-service refreshed"`.

The Stop hook checks: epic issue created with the `epic` label, prior open epics are closed OR the new epic body contains an `<override reason="..."/>` element.
</exit_condition>

<steps>

### 1. Read tenets + signs + staleness self-check

```
Read Docs/tenets.md
Read Docs/signs/planning.md
```

Then check the cron-driven staleness stamps (belt-and-suspenders against silent watchdog logic failure):

```bash
[[ -f ~/drift-state/last-admin-replies-at ]] && \
    AGE=$(( $(date +%s) - $(stat -f %m ~/drift-state/last-admin-replies-at 2>/dev/null || stat -c %Y ~/drift-state/last-admin-replies-at 2>/dev/null) )) && \
    [[ "$AGE" -gt 86400 ]] && log "WARN: admin-replies stamp is ${AGE}s old (>24h) — watchdog should have fired /admin-replies; check decision tree"

[[ -f ~/drift-state/last-knowledge-curate-at ]] && \
    AGE=$(( $(date +%s) - $(stat -f %m ~/drift-state/last-knowledge-curate-at 2>/dev/null || stat -c %Y ~/drift-state/last-knowledge-curate-at 2>/dev/null) )) && \
    [[ "$AGE" -gt 604800 ]] && log "WARN: knowledge-curate stamp is ${AGE}s old (>7d) — watchdog should have fired /knowledge-curate; check decision tree"
```

A warn here means the watchdog routing has drifted; surface it but don't block planning.

### 2. Detect override mode

```bash
if [[ -f ~/drift-state/planning-override-stuck-epic ]]; then
    rm ~/drift-state/planning-override-stuck-epic
    OVERRIDE_MODE=1
    log "Override mode: prior epic stuck >2 cycles. This planning cycle scopes the stuck epic, not a new arc."
fi
```

In override mode, your job at step 7 changes: you look at the stuck epic, decide (split | wontfix | needs-human), execute that decision, and exit. The new arc waits until the queue is clean.

### 3. Drain feedback

```
issues_drain_feedback (drift-mcp) OR scripts/issue-service.sh drain-feedback
```

For each systemic pattern returned: log to `~/drift-state/planning-followups.log` for inclusion in the epic's `<subtasks>` at step 7. **Do NOT file per-pattern sprint-tasks.** Patterns become sub-tasks of the epic if they're arc-relevant, or get bug-labeled (which auto-routes to routine-fix on next refresh) if they're standalone fixes.

### 4. Triage open bugs (P0 only)

```bash
gh issue list --label bug --label P0 --state open --json number,title,labels
```

For each P0 bug:
- Confirm Done-When block exists. If missing, write one inline.
- Add the bug as a sub-task of the planned epic (if it fits the arc) OR leave it labeled `bug` + `P0` (`cmd_refresh` does NOT auto-promote P0 bugs; they stay top-priority on the senior queue).

P1/P2 bugs are NOT planning's responsibility anymore. `cmd_refresh` auto-promotes orphan bugs older than 24h to `routine-fix`, which the always-on junior worker drains.

### 5. Process design-doc backlog

Same as before: `design_list_pending` / `design_list_in_review` / `design_list_approved_not_started`. For approved-not-started: file 2–5 `design-impl-{N}` issues with `<done_when>` blocks. These are exempt from the strict-one-epic rule — they're the implementation surface of an already-approved spec.

### 6. Triage feature requests (3-user rubric)

```bash
gh issue list --label feature-request --state open --json number,title,body,labels,author,createdAt
```

Apply the rubric from `Docs/tenets.md`. FRs that pass the rubric become the next epic; FRs that fail get `deferred` or `declined` per the existing rules. **Don't file FR-as-sprint-task** — promote to epic OR defer.

### 7. Research the next arc (think hard)

This is the step planning's budget redirected toward. If `OVERRIDE_MODE=1`, skip to step 8 instead.

#### 7a. Optional WebSearch grounding

If the next arc touches a domain Drift hasn't done before (new health metric, new platform API, new ML technique, new compliance area), do ONE WebSearch to check current state-of-art:

```
WebSearch "Drift-relevant search query, e.g. 'iOS 26 HealthKit cycle prediction API'"
```

~2-5k tokens. Cite findings in the epic's `<goal>` block as "we considered X / chose Y because Z." Skip this step entirely if the arc is well-known territory (UI polish, food DB enrichment, algo tuning).

#### 7b. Code-research via Explore sub-agent

```
Use Agent: Explore (read-only)
  prompt: |
    Map the code area the next arc will touch. For Drift's planning purposes
    I need: (a) what files/symbols the arc would modify, (b) what existing
    helpers I should reuse, (c) what tests currently cover this area, (d)
    any TODOs/FIXMEs that touch this surface.

    Specific area: <one-paragraph description of the arc>

    Return file:line citations for everything. Cap report at 200 lines.
```

The Explore agent returns its findings as a structured report. Use those file:line citations to ground the epic's `<done_when>` criteria. The verifier later scores against the criteria; concrete file:line + grep target = reproducible verifier; "fix the food tab" = useless verifier.

### 8. Draft + debate + file ONE epic

The epic body schema:

```xml
<epic id="<short-slug>" status="open">
  <goal>One paragraph naming the user-visible outcome + (if applicable) the SOTA/alternatives considered from step 7a.</goal>
  <subtasks>
    <task issue="" status="open" notes="<one-line spec>"/>
    <task issue="" status="open" notes="<one-line spec>"/>
    <!-- 3-7 sub-tasks typical -->
  </subtasks>
  <visual_criteria>
    <!-- Only if the arc touches Drift/Views/. See harness-phase-2-workflows.md
         section 3 for schema. -->
  </visual_criteria>
  <done_when threshold="all subtasks closed OR explicitly deferred">
    <criterion id="1" weight="3">Epic-level outcome 1, with file:line cited from step 7b.</criterion>
    <criterion id="2" weight="2">Epic-level outcome 2.</criterion>
  </done_when>
</epic>
```

If `OVERRIDE_MODE=1`: instead of a new epic body, post a decision on the *stuck* epic — `<override reason="stuck>2cycles" decision="split|wontfix|needs-human"/>` — and either (a) file 2-3 smaller follow-up issues to drain the stuck work, (b) close the stuck epic as wontfix with rationale, or (c) label it `needs-human` and leave it. THEN file the next epic in this same cycle (override mode allows both).

#### 8a. Debate-moderator on the draft epic

```
Use Agent: debate-moderator
  participants: principal-engineer, product-designer
  artifact: <the epic body draft from step 8>
  goal: "KEEP/REVISE/DROP verdict on this epic. Specifically: is the goal arc-sized (not too big for one open epic, not too small to need a planning cycle)? Are the sub-tasks each ≤1-day's senior work? Are the visual_criteria measurable? Are the Done-When criteria verifiable from real file:line state per step 7b's report?"
```

Apply verdict literally. If REVISE: rewrite the epic body once, then file. If DROP: planning failed — log to `Docs/decisions.md` why, exit. Don't loop.

#### 8b. File the epic + its sub-task issues

```bash
gh issue create --title "[EPIC] <short title>" --label "epic,sprint-task" --body "<full epic body>"
# For each sub-task in <subtasks> with issue="":
gh issue create --title "<sub-task title>" --label "sprint-task,SENIOR|JUNIOR" \
    --body "Part of #<epic-number>. <body with own <done_when>>"
# Then edit the epic body to fill in the issue numbers under <subtasks>.
```

Sub-task `<done_when>` blocks remain mandatory (senior reads them per `require-done-when.sh`). The epic's own `<done_when>` is the *meta* check — when all sub-task verdicts are PASS, the epic is done.

### 9. Refresh + close tracking issue + exit

Refresh the sprint cache (auto-promotes orphan bugs to `routine-fix` per phase 3d):

```bash
scripts/sprint-service.sh refresh
```

**Close the planning tracking issue.** The watchdog spawned you against a tracking issue (`~/drift-state/planning-issue` or the `PLAN_ISSUE` env var). After the epic is filed and the refresh ran, close that tracking issue — otherwise the watchdog interprets "still open" as "planning didn't finish" and resumes you up to 10 times, then auto-closes after burning the resume budget. Observed live 2026-05-26: 9 of 10 resumes were spent in this loop *after* epic #856 was successfully filed.

```bash
PLAN_ISSUE=$(cat ~/drift-state/planning-issue 2>/dev/null)
[ -n "$PLAN_ISSUE" ] && gh issue close "$PLAN_ISSUE" --comment "Planning complete. Filed epic #<new-epic-number>. Sprint cache refreshed."
```

Exit cleanly. Stop hook validates: epic-labeled issue exists, prior epics closed OR new epic has `<override>`, sprint cache refreshed, planning tracking issue closed.

</steps>

<failure_modes>
- **Filing standalone sprint-tasks** — forbidden under strict-one-epic. Bugs auto-route; permanents drive themselves. If you find yourself drafting >1 epic, you're conflating arcs — pick one, file it, defer the rest to next cycle.
- **Skipping the Explore sub-agent** — planning's tokens are supposed to fund grounded research, not memory-based scoping. If step 7b's report contradicts your hunch about the arc's shape, trust the report.
- **Vague Done-When criteria** — the verifier scores against them; vague criterion = useless verifier. Each criterion must have a concrete `verify=` command OR be a visible outcome the `/ui-evaluator` can score.
- **Drafting an epic too big for 5-10 sub-tasks** — that's a multi-epic arc; you've conflated. Split.
- **Skipping the debate** — the engineer + designer second-pass is your best filter. Don't ship a draft epic straight to GitHub.
- **Forgetting to clear the override stamp** — `~/drift-state/planning-override-stuck-epic` must be removed at step 2 (the `rm` is in the snippet). Otherwise next planning cycle ALSO fires in override mode unnecessarily.
- **Reading personas mid-cycle** — they live in subagent context. Polluting parent context costs ~4k tokens per file.
</failure_modes>
