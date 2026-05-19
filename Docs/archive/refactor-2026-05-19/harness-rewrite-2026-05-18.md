# Drift Harness Rewrite — Holistic Decomposition

**Status:** Approved 2026-05-18. Implementation in progress under cycle 10950.
**Tracking:** GitHub Epic issue (TBD) + 8 phase issues.
**Source for plan history:** `~/.claude/plans/i-wanna-rewirete-glimmering-lampson.md` (frozen at approval).

---

## Context

The Drift autopilot today is a 282-line monolithic `program.md` injected as the prompt for every headless `claude -p` session the watchdog spawns — planning, senior, junior all load the same giant prompt regardless of phase. This fuses workflows that share nothing (a senior fixing a typo carries the design-doc state machine, TestFlight recipe, product-review template, and persona-curation rules) and reinvents primitives Claude Code now ships (`/loop`, `/goal`, `/batch`, `/schedule`, `/ultrareview`, `/autofix-pr`).

Beyond the obvious shard-into-skills work, the rewrite is a one-shot opportunity to fix things the current harness gets weakly: no Done-When contract per task, no progress-based stuck detection (only "no tool call in 1h"), no escape hatch when a session repair-loops on the same issue, no standardized plan-comment format, no verifier with hard thresholds (qa-tester returns checklists, not pass/fail gates), and an undocumented persona doc-form vs agent-form split that will drift the moment one is edited.

The plan below is grounded in synthesized best practice from current harness-engineering writing (Anthropic's two harness essays, OpenAI's Codex prompting guide + long-horizon-tasks post, Geoff Huntley's Ralph Wiggum, Cognition's *Don't Build Multi-Agents* + Devin 2025 review, Sourcegraph's Dan note, Chroma's *Context Rot*). It is opinionated against the naive multi-agent design and matches what Drift actually has the resources to maintain.

## Best-practices grounding (the 8 lessons we're applying)

| Principle (source) | How Drift applies it |
|---|---|
| **Context rot starts well below the window limit** (Chroma; Cognition) | Health metric is *tokens-since-last-verifier-pass*, not "tokens remaining." `/senior` and `/junior` check this at every milestone via `/context`; over threshold → abandon, not `/compact` |
| **Never `/compact`; serialize to durable markdown and spawn fresh** (Anthropic, OpenAI Codex, Ralph) | Over-budget = abandon back to queue; planning re-splits next cycle. No WIP commits to main, ever. |
| **Verifier must be skeptical, weighted, threshold-gated** (Anthropic harness post; OpenAI; Ralph) | `qa-tester` upgraded from checklist generator to **adversarial-verifier**: scores against per-task Done-When criteria with weighted thresholds; ANY criterion below threshold = REJECT. Different system prompt from implementer. |
| **Done-When contract is frozen before execution** (OpenAI; Anthropic) | Planning's last act before filing a sprint-task is writing a `<done_when>` block in the issue body. Senior reads it as ground truth. Verifier scores against it. Without the block, the issue can't be claimed (new hook). |
| **Multi-turn review = file-based, never feed entire thread** (Anthropic; OpenAI) | Existing `scripts/design-service.sh address-pr` dumps comments to stdout. For substantive design-doc threads → delegate to `/autofix-pr` web session. |
| **Liveness = progress, not timeout** (OpenAI Codex guide) | New `stuck-detector.sh` watchdog hook: kills on no-diff-growth, repeated file reads, or no plan/progress comment update. |
| **Escape hatch: abandon an Issue back to queue** (Ralph) | New `scripts/sprint-service.sh abandon` subcommand. After 3 abandonments → `needs-human` label. |
| **Sub-agents are read-only investigators, NOT deciders** (Cognition) | Personas return structured verdicts. `debate-moderator` synthesizes. The senior/junior session is the only decider that commits code. |

## Final counts — exactly what's being built

| Layer | Count | Detail |
|---|---|---|
| **Custom Skills** | 6 | 3 top-level (`/planning`, `/senior`, `/junior`) + 3 sub-skills (`/design-doc`, `/testflight-publish`, `/knowledge-curate`) |
| **Subagents** | 4 | `principal-engineer`, `product-designer`, `qa-tester` (extended → adversarial-verifier), `debate-moderator` |
| **Hooks** | 23 existing − 1 deleted + 2 new = 24 | Delete: `testflight-check.sh`. New: `require-done-when.sh`, `stuck-detector.sh` |
| **Cloud routines (`/schedule`)** | 2 | `drift-daily-exec`, `drift-product-review` |
| **Local cron (launchd)** | 1 | `com.drift.testflight-publish` — fires `claude -p "/testflight-publish"` every 3h |
| **MCP servers** | 1 (`drift-mcp`) | ~25 typed tools across 6 groups, thin wrapper over bash CLIs in v1 |
| **Sign docs** | 3 | `Docs/signs/{planning,senior,junior}.md` — append-only guardrails per role |
| **Tenets doc** | 1 | `Docs/tenets.md` — consolidated from #111 + program.md + personas |

## MCP server: `drift-mcp` (the typed tool layer)

Single Python MCP server, ~25 tools across 6 groups. v1 wraps existing bash CLIs (same behavior, structured I/O). Skills migrate to MCP tools one at a time. After 1 month stable, bash CLIs can shrink to compat shims.

**Tools by group:** `sprint.*` (claim/done/abandon/next/status/refresh), `design.*` (pending/in-review/approved-not-started/address-pr/check-complete), `issues.*` (drain-feedback/labels/comment/read-done-when), `reports.*` (start-review/start-exec/finish), `state.*` (is-clean/control-signal/in-progress-issue), `verify.*` (parse-verdict/tier0-passing), `testflight.*` (last-published-at/unpublished-commits).

**Permission model:** mutating tools require `$DRIFT_AUTONOMOUS=1` AND claim state for this session; read-only tools always allowed. Replaces blanket `Bash` allowlist with per-action permissions.

## Markup convention: XML tags for structure, markdown for prose

XML/HTML tags wrap any block that a machine must parse reliably (`<done_when>`, `<plan>`, `<verifier_verdict>`, `<progress>`, `<abandoned>`). Markdown for prose inside and around. Tags don't drift; markdown headers do.

Applied inside skill bodies (`<role>`, `<inputs>`, `<steps>`, `<exit_condition>`, `<context_rules>`) and subagent system prompts. Pure-prose artifacts (decisions.md, roadmap.md, persona "What I learned", exec/review reports) stay markdown.

## The Done-When contract

Every sprint-task issue body must include a `<done_when>` block. Without it, the issue cannot be claimed (`require-done-when.sh` hook).

```xml
<done_when threshold="weight_sum>=5 AND no_criterion_at_zero">
  <criterion id="1" weight="3" verify="cd DriftCore && swift test --filter ThemeFlipTests">
    New tier-0 test added covering the goal-aware color flip
  </criterion>
  <criterion id="2" weight="2" verify="xcodebuild test -scheme Drift -destination 'iOS Simulator,name=iPhone 17 Pro' 2>&amp;1 | grep '✘' | wc -l">
    Tier-1 iOS tests pass (verify expects output: 0)
  </criterion>
</done_when>
```

Hook parses with real XML parser (Python `lxml` inside `drift-mcp`), not regex.

**Permanent-tasks use `<progress_when>` instead** — signals "no end state, just per-cycle check." `session-done` rather than `done` keeps the issue open.

## Plan-comment format (XML)

```xml
<plan>
  <goal>Restate Done-When criterion 1 in one sentence.</goal>
  <approach>1. First step. 2. Second step. 3. Third step.</approach>
  <touches><file>path/to/file1.swift</file></touches>
  <risk>What could go wrong; "low" allowed.</risk>
  <verifier_path>Done-When criteria covered; "all" allowed.</verifier_path>
</plan>
```

Posted within 5 min of claim. Abandonment uses `<abandoned reason="..." abandonment_count="N"><progress>...</progress><next_attempt_should>...</next_attempt_should></abandoned>`.

## Verifier verdict format (XML)

```xml
<verifier_verdict decision="PASS">
  <scores>
    <score criterion="1" weight="3" earned="3"/>
    <score criterion="2" weight="2" earned="0"/>
  </scores>
  <fix_items>
    <item criterion="2">Specific actionable fix description.</item>
  </fix_items>
  <reasoning>Why this verdict, for the human reader.</reasoning>
</verifier_verdict>
```

Hook enforces "any earned=0 with weight>0 → REJECT regardless of weight-sum." `Decision="PASS"` must additionally satisfy weight_sum ≥ threshold.

## Context discipline (no /compact, abandon-don't-handoff)

1. Skills never invoke `/compact`. Period.
2. Token budget per role: senior ~250k working, junior ~120k working.
3. Over budget = ABANDON (not handoff). Senior posts `<abandoned>` comment, calls `sprint-service.sh abandon`, exits. Planning re-splits next cycle. **No WIP commits to main, ever.**
4. Sub-agent outputs are summaries, not transcripts. debate-moderator returns JSON verdict only (≤2k tokens).
5. Multi-turn review handled by file: `address-pr` dumps to a workdir file; senior reads file in fresh session; never re-feeds the thread.

## Complete-unit-of-work gate

Every triggered action checks `scripts/is-clean-state.sh` first. Gate is **skip-quietly, never-block-work**.

`is-clean-state.sh` returns 0 iff ALL true:
- `git status --porcelain` is empty
- HEAD commit's associated issue has `<verifier_verdict decision="PASS">` in its comments
- `~/drift-state/in-progress-issue` empty or its issue is closed
- Tier-0 tests pass on HEAD (cached 5 min)

| Trigger | Behavior when not clean |
|---|---|
| `/testflight-publish` cron | Skip quietly. Cron fires again in 3h. |
| `/senior` claim | Exit without claiming |
| `/junior` claim | Same |
| `daily-exec` routine | Run anyway — observability, not release gate |
| `product-review` routine | Same |
| `/planning` | Run anyway — operates on queue, not code state |

**The hard rule: every commit to main has a PASS verdict.** Enforced by `require-qa-verdict.sh` (existing, schema-updated). WIP only on feature branches `wip/issue-{N}`, never merged by autopilot.

## The 6 Skills (summarized — full bodies in `.claude/skills/`)

- **`/planning`** (Opus, daily). Drain feedback → triage bugs → process design-doc backlog → triage FRs → draft 8+ tasks with Done-When → debate-moderator verdict → create issues → update roadmap. Sets `/goal` for completion.
- **`/senior`** (Opus, 1 task). Clean-state check → claim → read Done-When → post Plan → implement → verifier debate → fix or abandon → commit on PASS.
- **`/junior`** (Sonnet, 1 task). Same shape as senior but qa-tester-only verifier, no design-doc, no security-review.
- **`/design-doc`** (sub-skill). State machine: pending/in-review-light/in-review-substantive/ready-to-close.
- **`/testflight-publish`** (Haiku, launchd-cron). Clean-state gate → staleness check → bump → archive → upload → stamp → update releases.json → commit → push.
- **`/knowledge-curate`** (weekly from planning). Sediment + prune persona learnings; curate signs.md.

## The 4 Subagents

- **`principal-engineer`** (system arch judgment; ports `Docs/personas/principal-engineer.md`)
- **`product-designer`** (UX judgment; ports `Docs/personas/product-designer.md`)
- **`qa-tester`** (upgraded → adversarial-verifier; existing file extended)
- **`debate-moderator`** (synthesizer, not debater; spawns participants in parallel, returns JSON verdict)

**Persona source of truth: `.claude/agents/`.** `Docs/personas/*.md` becomes a one-line pointer + warning hook on edits.

## Liveness — how work keeps happening

1. **Watchdog supervision (unchanged process).** New `stuck-detector.sh` kills on: no diff growth in 30 calls, same file opened >5 times, no plan/progress comment update in 20 calls, no heartbeat in 1h.
2. **In-session `/goal`** at line 1 of every top-level skill.
3. **Escape hatch:** `sprint-service.sh abandon`. After 3 abandonments → `needs-human`.
4. **Routine-backed cron** for daily-exec + product-review (cloud, independent of watchdog).

## Command Center alignment

CC stays **read-only UI**. Reads `heartbeat.json`, `releases.json`, `blockers.json`, GitHub via API. Writes nothing to local state. Control via `~/drift-control.txt` (PAUSE/DRAIN/RUN).

Schemas preserved: `heartbeat.json` bucketed activity, `releases.json` release notes shape, all label semantics (`permanent-task`, `sprint-task`, `SENIOR`, `JUNIOR`, `P0/P1/P2`, `design-doc`, `doc-ready`, `approved`, `implementing`, `feature-request`, `deferred`, `report`, `needs-review`, `requested`, plus new `needs-human`).

## Sign-driven correction

`Docs/signs/{planning,senior,junior}.md` — append-only single-sentence guardrails per role, loaded by the corresponding skill at startup.

Example `Docs/signs/senior.md`:
```
- Do not invoke `/compact`; if budget tight, abandon and let planning re-split.
- When tests fail, do not delete the test. Fix the code or fix the test, never both at once.
- After 2 verifier REJECT cycles on the same diff, abandon the issue.
```

`/knowledge-curate` promotes 90d-stable signs into skill-body stable section; prunes 180d-irrelevant.

## Feature-request triage rubric (used in `/planning` step 6)

```
FR is a sprint-task this cycle IF any:
  - aligns with a current #111 campaign tenet
  - same FR reported by ≥3 distinct users
  - blocks privacy/data-correctness/AI-chat top-feature paths
Else: label `deferred`, comment "Deferred; re-assessed next planning cycle if [tenet]/[reports] change."
After 3 cycles deferred AND no new evidence: label `declined`, close with rationale.
```

## Migration order (strict, lowest risk first)

`DRIFT_USE_SKILLS=1` controls cutover; default off during migration. Each step ≥2 cycles before next.

0. **Persist plan + tracking** (this commit). Plan doc in repo. Epic + 8 phase issues filed with `<done_when>`.
1. **MCP server v1 + cleanliness script.** Thin wrappers; smoke + contract tests; no skill consumes yet.
2. **Foundations.** 4 agents, tenets doc, signs docs, 2 new hooks in shadow mode.
3. **Spike `/planning` + `/knowledge-curate`.** Flag-on for next planning cycle. Quality ≥ parity.
4. **Port `/senior` + `/junior` + `/design-doc`.** Hooks shadow → enforce. 1 week soak.
5. **Move TestFlight to launchd.** Build skill, install plist, delete `testflight-check.sh`. Verify 2 firings.
6. **Add cloud routines.** `drift-daily-exec`, `drift-product-review` via `/schedule`. Verify 2 firings.
7. **Flip flag default-on. Delete monolithic program.md sections. Shrink bash CLIs to compat shims.**

Rollback at any step: flip `DRIFT_USE_SKILLS=0`. MCP server stays running; agents work standalone; hooks revert to shadow.

## Verification

- **Per-skill smoke:** `DRIFT_AUTONOMOUS=1 claude -p "/planning"` produces expected artifacts.
- **Verifier contract:** file a task with deliberately failing Done-When criterion; debate-moderator MUST REJECT.
- **Context-budget delta:** ≥40% reduction in tokens consumed before first user-visible tool call.
- **Stuck-detector contract:** force a stuck loop (read same file 6×) → watchdog kills + abandons.
- **CC schema preservation:** `heartbeat.json` + `releases.json` shape unchanged.
- **MCP contract tests:** `pytest drift-mcp/tests/`.

## Out of scope

- Adding release-manager / product-manager personas (release is deterministic; focus is data)
- Rewriting watchdog supervisor loop (only spawn line + stall heuristics change)
- Replacing hooks with skills (hooks remain the right primitive for policy)
- Long-running `/loop` session as watchdog replacement (context pollution)
- Command Center writeback API (stays read-only)
- Reimplementing bash CLIs as native Python in MCP server v2 (deferred)

## Open risks

1. Stream-json shape under `claude -p "/skill"` — verify on spike that watchdog's stall detection still works.
2. `/goal` semantics under `--dangerously-skip-permissions` — verify it actually keeps session running.
3. Routines availability — `/schedule` may not be on user's plan; fallback to in-`/planning` invocation.
4. Debate-moderator latency 30–90s — skip for trivial diffs (<10 lines, single file).
5. Skill auto-discovery in `-p` mode — verify `claude -p "/planning"` resolves the skill; fallback to passing SKILL.md body.
6. Persona doc-form drift — `.claude/agents/` is canonical; `Docs/personas/` becomes pointer.
7. `/knowledge-curate` over-pruning — log every prune to decisions.md for 1-cycle recoverability.
8. Stopped-early failure mode — verifier with hard thresholds is the cure.
9. Done-When blocks may be poorly written — `/knowledge-curate` reviews; signs.md accumulates anti-patterns.
10. Abandon-don't-handoff may starve large tasks — if >20% abandon on budget, plant a sign for planning to split smaller.
11. TestFlight starvation if main is never clean — escalate after 5 consecutive 3h skips.
12. MCP server SPOF — stateless design, supervisord-restart, bash CLI fallback for first month.
13. MCP permission interaction with `--dangerously-skip-permissions` — verify server-side gates still fire.
