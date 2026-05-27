# Queue-router `blocked` / `needs-human` filter audit — 2026-05-27

## Source

Filed as #854 (epic #856). Class-of-bug audit triggered by #848's 4-abandonment chain: `scripts/sprint-service.sh cmd_next` filtered `needs-human` but NOT `blocked`, so a designer-blocked design-doc kept being re-served to senior autopilot. This audit checks every queue-routing surface in `scripts/` for the same gap.

## Method

1. `rg -ln 'cmd_next|cmd_claim|cmd_pending|cmd_status' scripts/*.sh` for files that surface work.
2. Inspect every function that calls `gh issue list` and decides whether to serve an issue to autopilot.
3. Cross-check against `scripts/design-service.sh:39` reference pattern: `select(.labels | map(.name) | index("blocked") | not)`.

## Findings table

| Script | Function | Surfaces work to autopilot? | Filters `blocked`? | Filters `needs-human`? | Action |
|---|---|---|---|---|---|
| `design-service.sh:38` | `cmd_pending` | yes — design-doc backlog → senior | **yes** (line 39) | n/a (auto-applied AFTER abandons; design-docs don't currently abandon) | reference impl |
| `sprint-service.sh:287` | `cmd_next` | yes — primary senior/junior task queue | **yes** (line 345, this epic) | **yes** (line 343) | fixed in #853 |
| `sprint-service.sh:82` | `cmd_refresh` | no — builds full state snapshot; `cmd_next` filters at serve time | n/a (snapshotter, not router) | n/a | no change |
| `issue-service.sh:77` | `cmd_bugs_needing_plan` | no — read-only listing for planning step 3; planning then decides per-bug | no filter | no filter | document; planning step 3 is a HUMAN/Opus judgment surface, not autopilot claim |
| `issue-service.sh:89` | `cmd_ready_from_review` | no — read-only listing of `needs-review` issues | no filter | no filter | safe — `needs-review` issues are claim-gated separately by `cmd_next` |
| `planning-service.sh:167` | `_food_db_open_count` | no — internal guard counter | n/a (count, not router) | n/a | no change |
| `planning-service.sh:181` | `cmd_guard_sprint_task` | no — gate on NEW issue creation, not routing | n/a | n/a | no change |
| `report-service.sh` | — | no | n/a | n/a | no routing surfaces |

## Verdict

**No additional queue-router fixes required.** The only two scripts that serve work to autopilot (`design-service.sh cmd_pending` and `sprint-service.sh cmd_next`) both now filter `blocked`. Read-only listings in `issue-service.sh` feed planning, not autopilot — they're already covered by the downstream `cmd_next` filter when planning files a sprint-task.

## Recommendation

Class-of-bug pattern logged in `Docs/decisions.md` → `queue-router-blocked-filter`. Future queue-routing additions must apply the filter at the serve site. The pattern is now in two scripts, so the rule-of-three for extraction does not yet justify a shared helper — revisit if a third router emerges.
