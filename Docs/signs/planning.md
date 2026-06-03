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
  Why: #860 was "split" 2026-05-31 (spawned #875) but left open, so the watchdog re-fired override 2026-06-03 with the same epic stuck — the real blocker was an unprioritized 28-file revert (#872) built on a false "gate enforced" premise, not arc scoping.

## Recently pruned (last curation cycle)

None yet — first cycle. `/knowledge-curate` will populate.
