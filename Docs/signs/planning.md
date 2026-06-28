# Signs — /planning role

Append-only single-sentence corrections. Loaded by `/planning` skill at startup. `/knowledge-curate` promotes 90d-stable signs to the skill body's stable section; prunes 180d-irrelevant signs.

When adding a sign: state the rule, then a one-line `Why:` (the incident that motivated it).

## Active signs

- **Anchor cadence triggers to the unit the human reads them against, not the internal counter that happened to be convenient.**
  Why: cycle-count-based review interval produced a daily review when wall-clock should drive cadence (cycle 10950, #803).

- **Promote tenets to rules when they matter operationally.** Tenets without rules are aspirations; tenets WITH rules are infrastructure.
  Why: failed-archive 24h tenet, once it became an auto-P0 rule, collapsed recovery from 17 builds to 1 day (cycle 10888).

- **Pair every passive activation lever with one active ask in the same sprint.** Dashboard banner without DM is half-shipped.
  Why: 3+ cycles of recommendation → ship → still null traffic because no human asked anyone to test it (cycle 10888, #789).

- **A review recommendation that survives one cycle without action becomes a sprint-task, not a re-recommendation.**
  Why: cycle 9851 — three consecutive reviews recommending the same activation lever produced zero action.

- **TestFlight build with no user-visible features auto-flags at next planning.** Two zero-feature ships in a row = cadence theater.
  Why: cycle 10950 — TestFlight publishes that don't carry user-visible change undermine "TestFlight reach is part of the product."

- **Class-of-bug audits earn their slot when a single fix shows the shape.** File the audit when you write the patch, not later.
  Why: 2-point extrapolation bug (cycle 10950, #801) was a class of UI confidence labels math doesn't earn.

- **The fix-or-XCTSkipIf shape is a known-good acceptance criterion.** "Diagnose root cause of X" should produce a documented root-cause string, not just "investigated."
  Why: cycle 9851 — tasks slipped because acceptance was un-measurable.

- **8+ sprint-tasks per cycle requires DROP/DEFER discipline** if queue >60. More tickets ≠ more throughput; senior drain rate is the only lever.
  Why: queue inflation pattern; senior drain rate is the only forward signal.

- **An override "split" that spawns a parallel arc but leaves the stuck epic OPEN re-fires the override forever.** Resolve the stuck epic to a single landable task (P0 if it gates the showstopper) + an escalation ladder; don't split-and-leave-open. When an epic is stuck, verify task bodies against real file:line before acting — they may claim work landed ("gate enforced") that never committed.
  Why: #860 was "split" 2026-05-31 (spawned #875) but left open, so the watchdog re-fired override 2026-06-03 with the same epic stuck — the real blocker was an unprioritized 28-file revert (#872) built on a false "gate enforced" premise, not arc scoping. (Resolved 2026-06-04: #872 had in fact landed+PASSed 4h after the 06-03 comment claimed it hadn't — verify-at-file:line caught it, so #860 was CLOSED, not split a 4th time.)

- **A multi-minute real-model eval wired as a per-TASK commit gate causes a headless death-loop in Mode 3** — sessions `external_kill` mid-eval before they can commit, re-orphaning identical files at zero net commits. Fix is a planning rescope (don't leave it `needs-human`): split the deterministic quality/grounding PREDICATE (Tier-0, commit-gated, runs on canned output) from the live-model RATE measurement (Tier-4 env-gated / preflight, OFF the commit path); the eval gold-set FILE still ships in the same PR so tenet #13 holds.
  Why: #877 (BriefNarrator) burned 8+ headless sessions 2026-06-03→04 re-running a 12-min Gemma grounding eval that its Done-When demanded in-PR, never committing the finished 4-file deliverable; rescoped 2026-06-04 (predicate→Tier-0 in #877, live RUN→#885).

- **A `<done_when>` `verify=` command that returns NON-EMPTY at epic-open is tautological — it rubber-stamps the subtask closed before the fix lands.** Run every verify against HEAD while drafting; if it already passes, re-gate it on a net-new NAMED test token you've confirmed ABSENT (`rg` the token first), not on a substring existing fixtures/tests already satisfy. Name the required test in the subtask note so the implementer writes the exact symbol the gate greps.
  Why: #909 (Coach polish epic, cycle 20049) — the first draft's verifies for #892/#898/#901 matched 21 pre-existing multi-turn tests / existing `with.*naan` fixtures / an existing `log 500ml water` test, so all three would have passed with zero new work; the principal-engineer validation pass caught it before filing. (Corollary: also confirm a verify that's EMPTY now will go non-empty when the fix lands — both polarities must discriminate.)

- **The watchdog's "stuck>2cycles" keys off the epic ISSUE's own `updatedAt`, which never moves when SUBTASKS close — so a healthily-draining finite epic trips override as a false positive.** In override, verify the drain rate (subtasks closed since epic-open) before acting; if >0 and the showstopper gate is met, the correct resolution is close-the-met-gate-epic + refile survivors as a fresh finite epic (resets the clock honestly), NOT wontfix/needs-human.
  Why: #900 (cycle 20049) tripped override one day after creation despite 2 P0 showstoppers + 3 other coach fixes landing; resolved by closing it (gate #896+#897 met+verified) and refiling the 6 polish survivors as #909.

- **A false-positive override on a finite epic whose GATE IS UNMET resolves by keeping the epic OPEN and bumping its `updatedAt` (edit body/comment) — NOT by close-and-refile.** Closing an undelivered-gate epic just to dodge the watchdog is dishonest; re-anchor escalation to a COUNTABLE predicate (≥3 abandon/WIP comments on the gate subtasks, `gh issue view <n> --json comments`), never an un-countable "N senior cycles."
  Why: #909 (cycle 20462, 2026-06-27) re-fired override ~28h after creation — #901 had drained but the premium-feel gate #890/#891 sat UNCLAIMED with ZERO senior attempts (queue latency, not a blocker); the #900 close-and-refile move would have closed an epic whose stated gate wasn't delivered. Distinct from the gate-MET case (the #900 sign above) where close-and-refile IS the honest reset.

## Recently pruned (last curation cycle)

None yet — first cycle. `/knowledge-curate` will populate.
