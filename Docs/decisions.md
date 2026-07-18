# Decisions Log

Append-only record of non-obvious decisions: architecture changes, harness rules, design tenets that emerged from a real incident, performance/correctness tradeoffs that future readers should know about.

**The bar (read this before appending):** *"would a future session reading the diff still ask **why was it done this way?**"* — if yes, append. If the diff explains itself, don't.

**What goes here:**
- Architectural calls (e.g. "regress on raw weights, not EMA")
- Harness/process rules that came from a real incident (e.g. "raise stale-claim threshold to 90min after #426 false flag")
- Cross-cutting design choices (e.g. "Source: line required on sprint-tasks")
- Reversals (e.g. "replaced crashed/<N> branches with patch files — branch ceremony was too heavy")

**What does NOT go here:**
- Bug fixes — commit message + Resolution comment is enough
- Feature ships — changelog/releases.json captures these
- Code style / refactor for cleanliness — live in CLAUDE.md tenets, no per-decision noise
- Routine planning decomposition — sprint-task bodies capture this
- Test additions — diff is self-explanatory
- "I did X" without a *why* — every entry must have a reason future-you couldn't reconstruct from the diff alone

**Who appends:**
- **Anyone** with a real decision — senior, junior, planning, human. After closing the issue (or as part of closing).
- **Planning** is the editor: step 6 sweeps for missed entries from significant commits AND prunes the file (remove entries that didn't meet the bar, consolidate duplicates, archive entries >30 days that are now common knowledge).

**Format:**
- Most recent at the top
- One section per decision: `### <slug> — <one-line summary>`
- 1–3 sentences for the body. Lead with the *why*. Link the commit hash.
- Group by date heading: `## YYYY-MM-DD`

---

## 2026-06-19

### Knowledge curation pass 2026-06-19

Weekly `/knowledge-curate` ran (21d since the 2026-05-29 stamp). First pass with *eligible* entries — the 2026-05-12…05-17 persona cohorts crossed the 30d sediment threshold. Key method note: the **planning/senior signs files are the "referenced by a rule" oracle.** A persona learning that `/planning` promoted to a sign counts as referenced — this caught principal-engineer's "outcome metric" entry, which a keyword grep missed because the sign phrases it as "measurable acceptance" / "documented root-cause string" (planning.md / cycle 9851). Without the signs cross-check it would have been wrongly pruned.

**Sedimented into stable:**
- principal-engineer.md: 8 durable claims — flag-off+eval-gated cutover template *(Testing & Quality)*; wall-clock-not-cycle-count cadence (#803), human-action third work-item category (#789), known-failing-test re-verify-each-planning (#780), recurring-complaint-across-3+-reviews→re-diagnose-the-layer, class-of-bug-audit-filed-with-the-patch (#801), measurable-acceptance-criteria (cycle 9851) *(Process & Discipline)*; 2-point-extrapolation bug class (#801) *(What Broke & Why)*.
- product-designer.md: 3 — survives-one-cycle→sprint-task (cycle 9851), tenets-WITH-rules-are-infrastructure (cycle 10888), zero-feature-build auto-flags-at-next-planning (cycle 10950). All *Process & Discipline*, each backed by an existing planning sign.
- qa-tester.md: 0 new — the cycle-9792 rubber-stamp rule was already sedimented into `<context_rules>` + senior.md signs last cycle; the entry held no new *code* failure-mode for `<drift_failure_modes>`.
- signs (skill bodies): 0 — all three signs files are ~32d old (created 2026-05-18 … last appended 2026-06-04). Sediment needs a >90d-old incident AND a 90d violation-free track record; none qualify yet (earliest crossing ~2026-08-16, as the 2026-05-29 pass projected).

**Pruned (recoverable for 1 cycle):**
- principal-engineer.md: "V6 visual evolution shipped in 3 reversible commits (incremental + reversible by default for UI ships). Monolithic redesigns require explicit justification." — unreferenced (no sign, no decision in 34d). The designer's mirror copy was pruned for the same reason, so the incremental-UI-default principle is recoverable **only** from this log.
- principal-engineer.md: "LLM prompt audit tasks need a *cross-stage* eval gate, not just the changed gold-set." — unreferenced; nothing picked it up in 38d.
- principal-engineer.md (superseded, not unreferenced): "Apple Foundation Models with `@Generable` is now a production architecture pattern in Drift." — contradicted by the #872 NO-GO revert (2026-06-03). Only its durable half (the flag-off+eval-gate cutover template) sedimented.
- product-designer.md (superseded): "Apple Foundation Models is the right platform bet to lean into." — same #872 revert.
- product-designer.md: "V6 in 3 reversible elements is materially better than the cycle-869 monolithic theme overhaul. Multi-commit incremental UI is the default; monolithic redesigns require justification." — unreferenced mirror of the pruned principal-engineer note.
- product-designer.md (restatements already verbatim in stable, pruned without separate recovery): the Feedback-null-traffic-#789 tracking note + the "in violation of my own learning, ZERO friend-tester DM" self-critique (both restate the passive-lever-pairing rule at stable line 47); the "TestFlight reach is measurable (#770)" + "passive lever is half a lever" entries (already in the stable Users & Feedback block).
- qa-tester.md: "7 traced-correctly verdicts cite real tests but line numbers drift 1–58 lines …" (an observation, not an actionable rule) + "Hook recommendation deferred: extract test names from verdict body and grep test files for them at commit time." (a deferred proposal — confirmed **no such hook was ever built**, so it was a dead TODO, not a live pattern).

Total agent-file line counts after curation:
- principal-engineer: 127 / 300 cap
- product-designer: 118 / 300 cap
- qa-tester: 91 / 250 cap

**Next eligibility:** all 9851–10950 persona cohorts are now processed; fresh `/planning` appends will age into the 30d window over the coming weeks. Signs first cross the 90d sediment threshold ~2026-08-16.

## 2026-06-17

### briefnarrator-grounded-rate — live grounding eval clears the bar, green-lights the Today's Brief surface (#885 → #879)
**BriefNarrator live grounded rate = 7/7 (100%) over the `BriefNarratorGroundingEval` gold set, vs the named `groundingThreshold = 0.75` (`DriftLLMEvalMacOS/BriefNarratorGroundingEval.swift`).** Measured on real Gemma 4 (E2B Q4, llama.cpp/Metal, M5 Max) via `xcodebuild test -scheme DriftLLMEvalMacOS ... DRIFT_DEEP_EVAL=1` after the env-gate wiring fix (commit f81c1b60). Every narrated item across all 7 Indian-first cases introduced only numbers present in its supplied `BriefInput` signals — no over-claim / 2-point-extrapolation (#801) leakage. This is the safety property the whole arc depends on: **rate ≥ 0.75 ⇒ #879 (integration capstone) is green-lit** to wire the brief onto the user-facing Today screen. The complementary Tier-0 `isGrounded` predicate (commit 15ea3527) still guards the commit path on canned output; this measures live model behavior off the headless-kill path (the split that broke the prior eval-as-commit-gate death-loop). Note for #879: grounding guards number *introduction* in digit form, not factual semantics — do not treat it as a full truth gate.

## 2026-06-03

### fm-chat-no-go-revert-to-llamacpp — showstopper measured sub-bar; revert the global chat default (epic #860, enacted by P0 #872)
**Decision: NO-GO on Foundation Models as the global chat default — revert to llama.cpp/Gemma.** #861 measured FM chat parity at **80.5% overall (33/41) / 75.0% critical (18/24)** vs the llama.cpp/Gemma baseline **92.7%**; the cutover bar is ≥95%/≥98%, and FM was made the default (`AIBackend.swift:99-106` detectTier; `Preferences.swift:251`) **without ever clearing it**. #862 established the multi-turn gap is **structural** — no bounded FM-side fix; the only lever is the ~25-call-site native-`Transcript` redesign (#864). Per the operational rule *"run eval before AND after every AI change — if accuracy drops, revert, no exceptions"* + tenet #1 (chat = showstopper), the call is to **restore the documented pre-2026-05-19 default (llama.cpp/Gemma)** — not fix-forward, not escalate. Reverting is the *status quo ante*, not a new product bet (principal-engineer + product-designer debate 2026-06-03 both returned KEEP-REVERT, decisively). FM stays a user-selectable opt-in; **re-promotion to default is gated needs-human on #874**, only after FM clears the parity gate (e.g. via #864).

Three findings the enactment (#872, now P0) MUST honor — verified at file:line in the 2026-06-03 debate; without them the revert silently doesn't revert:
1. **`DriftApp.swift:70-73` runs a launch-time force-migration that re-flips any `.llamaCpp` preference back to `.foundationModels` on every launch.** Flipping `detectTier` + the `Preferences` fallback alone reverts only fresh installs; existing users get silently re-pinned to FM. This file is load-bearing and was absent from #872's original scope — the likely reason the revert never "stuck" across 3+ attempts.
2. **Existing FM-default users need a migration prompt on the next build** (land on the chooser / "download on-device AI for better Coach quality" — never a dead chat). First-run download UX already exists (`AIChooserView`/`AISetupView`/`AIModelManager`: size, Wi-Fi guidance, progress, retry, not-enough-space), so no new download surface is needed — only the migration path + a release note (engine-shipped ≠ user-shipped, tenet #11).
3. **Keep the parity gate always-MEASURING; only the *blocking* threshold goes conditional** on FM being the active default. "A skipping gate lies" — a gate that auto-passes once reverted must still emit the parity number every run (like the existing regression floor at `FoundationModelsChatParityTests.swift:313`), or it decays back into the dormant state being fixed here.

**Done when:** `detectTier()` returns `.llamaCpp`, `Preferences.preferredAIBackend` defaults to `.llamaCpp`, the `DriftApp.swift:70-73` force-migration is removed/inverted, existing-FM users get a migration prompt, the parity floor is green on HEAD, and a release note ships in the same build. **Tradeoff accepted:** llama.cpp/Gemma needs a ~2.9GB on-device download FM avoided — acceptable because it is the prior default, fully on-device (privacy tenet), and a one-time bounded cost vs an unbounded multi-turn-quality regression on the showstopper. **Why it thrashed (3+ sessions):** the revert was a single 28-file task, never P0, and built on a *false* "gate already enforced" premise (the gate was never actually wired into preflight — `DRIFT_FM_PARITY_GATE_STRICT` is unset). Now consolidated to one honest P0 task (#872); #863 closed as a duplicate.

## 2026-05-29

### Knowledge curation pass 2026-05-29

Weekly `/knowledge-curate` ran (7.0d since last stamp; first pass ever *logged* — the layer landed 2026-05-18 via `ec936bc5`). **No-op cycle by design** — the entire knowledge layer is younger than its promotion thresholds, so nothing was eligible to sediment or prune. Recorded for the audit trail: a dated "0/0" pass tells the next curator the run was healthy, not skipped.

**Sedimented into stable:**
- principal-engineer.md: 0 — all 4 `<what_i_learned>` entries (cycles 9851–10950, dated 2026-05-12…05-17) are 12–17d old; rule is leave until ≥30d.
- product-designer.md: 0 — same 4 dated cohorts, all <30d.
- qa-tester.md: 0 — sole `<learnings>` entry (cycle 9792, 2026-05-11) is 18d, <30d.
- signs (skill bodies): 0 — planning/senior/junior signs files are 11d old (created 2026-05-18), below the 90d stability threshold; none carry a >90d incident with a 90d violation-free track record.

**Pruned (recoverable for 1 cycle):** none — nothing is ≥30d unsedimented (agent files) or ≥180d unreferenced (signs).

**Next eligibility:** `<what_i_learned>` entries cross 30d starting ~2026-06-11 (the 2026-05-12 cohort first); signs cross 90d no earlier than ~2026-08-16. Expect the first real sediment/prune around mid-June.

Total agent-file line counts after curation (unchanged — no file was rewritten):
- principal-engineer: 135 / 300 cap
- product-designer: 128 / 300 cap
- qa-tester: 94 / 250 cap

### fm-multiturn-fix-is-structural-not-bounded — there is no FM-side multi-turn lever to tune (#862 → follow-up #864)
#862 was scoped to "fix the tractable multi-turn parity breaks **in `FoundationModelsBackend.swift`**." Verified at current file:line that that lever **does not exist as a bounded edit**, so the fix is structural — documented here as #862's chartered finding rather than ground open-endedly. (1) `FoundationModelsBackend.respond(to prompt: String, systemPrompt: String)` (`FoundationModelsBackend.swift:57`) takes a **single flat pre-folded string** and spins a fresh stateless session (`makeSession:137`) with **zero** history logic. (2) Multi-turn history is folded **upstream** and shared **byte-identically** with the Gemma baseline — the parity harness folds via `userMessage(query:history:)` (`FoundationModelsChatParityTests.swift:158-160`) and feeds the same string to both `classifyLlama` (`:162`) and `classifyFM` (`:168`); production folds identically in `IntentRoutingEval`/`IntentClassifier`. So any FM↔Gemma divergence is the model's internal handling of the *same* input — nothing FM-specific to tune in-file. (3) The only FM-native multi-turn lever is seeding a session with a native `Transcript` instead of flat text, which requires changing the flat-string `AIBackend.respond` contract (`AIBackend.swift:14`) + ~25 call sites = cross-cutting redesign, explicitly out of #862's "bounded, one senior session" scope. Filed as **#864**, gated on #863's go/no-go (only do it if #863 picks fix-forward; obsolete if #863 reverts the global default to llama.cpp). **This conclusion is input-independent** — it's a property of the architecture, not of which cases fail — so it stands without #861's per-case failure list. **Still open:** #861 (the measured FM-vs-Gemma parity *number*) has not run (OPEN, 0 comments); #863's go/no-go needs both that number and this tractability finding. No source change; Tier-0 untouched.

## 2026-05-28

### fm-chat-parity-gate-dormant — the chat backend cutover gate was never enforced (epic #860)
Planning cycle 15764 scoped epic #860 around a live risk: FM is the **default** chat backend (`Preferences.swift:251`; `AIBackend.swift:99-106` detectTier always returns `.foundationModels`) but it was made default without its parity cutover gate ever passing. `testFoundationModelsChat_parityCutoverGate` (≥95%/≥98% vs the Gemma baseline, `FoundationModelsChatParityTests.swift:263`) is skipped unless `DRIFT_FM_PARITY_GATE_STRICT=1`, which preflight never sets (`preflight-check.sh:86`) — so only a 40% catastrophic floor guards every autonomous 3-hourly TestFlight, and multi-turn coverage is 2 two-turn cases. This is the **same env-gated-cutover pattern as the FM composite-food extractor (#771)**, now applied to the most important FM surface (chat = showstopper, tenet #1). Two design calls were baked into the subtasks after the planning debate's moderator (participants failed — see below) flagged them: (1) backend is a *single global default*, not per-route, so an FM-below-bar outcome can only be fix-forward or a **global** revert to llama.cpp — "revert one route" is incoherent; (2) the parity test *skips* when FM is unavailable on the host, so on an autonomous no-human pipeline the gate must **hard-fail loudly**, never green-skip (a skipping gate lies). Chosen over deferred alternatives: V7 Body screen (blocked on needs-human #848), pink-retirement long tail (fragmented, partly #833), exercise visuals (off-focus).

### planning-debate-participants-empty — debate-moderator participant subagents returned no output
During #860's pre-file debate, both `principal-engineer` and `product-designer` participant subagents returned empty output across 4 spawn attempts (the parent Explore agent also socket-errored twice before succeeding on the 3rd try). The debate-moderator still produced a useful *orchestrator-level* REVISE synthesis, which was applied; the load-bearing claim (global vs per-route backend) was re-verified directly against `AIBackend.swift:99-106` rather than trusted blind. Flagging because a recurring participant-empty failure would silently degrade every planning/senior debate to single-perspective — if it recurs, investigate the Agent spawn path, don't just retry.

## 2026-05-27

### userdefaults-leakage-cross-suite — Swift Testing `.serialized` is intra-suite only; co-locate writers of one key
Two separate `@Suite(.serialized) struct` blocks (`FoodIntentFlagBehavior` in `FoodLogIntentExtractorTests.swift` + `FoundationModelsFoodExtractorFlagBehavior` in `FoundationModelsFoodExtractorTests.swift`) both mutated `UserDefaults.standard["drift_fm_food_intent_extract"]` via `defer { removeObject }` + `Preferences.fmFoodIntentExtractEnabled = false`. Swift Testing's `.serialized` trait serializes child tests *within* one suite — sibling suites still run in parallel, so the `defer` in suite A raced the `= false` in suite B and `asyncParseFood_flagOffMatchesSync_allGoldRows` flaked depending on suite ordering. This bricked `state_is_clean` for #848 across 4 abandonments in 2 days. Standing rule: tests that read or write a shared global (UserDefaults key, env var, static var) MUST live in one suite. Don't add a second `@Suite(.serialized)` that touches the same key — hoist or co-locate. Fixed by moving the two FM facade flag tests into `FoodIntentFlagBehavior`. See #852 + epic #856.

### queue-router-blocked-filter — every queue router must filter `blocked` AND `needs-human` from `available`
`scripts/sprint-service.sh` `cmd_next` filtered `needs-human` but not `blocked`, so #848 — manually blocked by a designer reweight comment — kept being served to the senior, who abandoned it 4 times in 2 days before the `needs-human` auto-label finally took effect at abandonment_count=3. `scripts/design-service.sh:39` had the correct pattern (`select(.labels | map(.name) | index("blocked") | not)`); cmd_next did not. Standing rule: every queue router that surfaces work to autopilot MUST drop both labels at the `available` filter. A blocked-label issue is a designer/engineer veto — autopilot serving it is wasted cycles + amplified abandonment counts. The class-of-bug audit (#854) is filed JUNIOR to check all sibling routers. Fixed by mirroring design-service.sh's filter pattern. See #853 + epic #856.

---

## 2026-05-18

### review-cadence-wall-clock-replaces-cycle-count — anchor the gate to real time, not autopilot velocity
Product review was triggering on a 20-cycle gap. Cycle 10950 review observed this had collapsed to a daily review because autopilot cycles now complete in ~20 minutes (70+ cycles/day), not the ~5–6 cycles/day the original interval was set against. Reviews ran every day after every exec briefing — overweighting process work and burning a fresh GitHub Issue per cycle. Replaced with a single wall-clock gate (`PRODUCT_REVIEW_INTERVAL_DAYS`, default 5) in `cmd_review_due` and `cmd_planning_context`; the old cycle-count fields stay in `planning-context` output for telemetry only. Standing rule: any cadence in the harness must anchor to wall time, not cycle count — otherwise it drifts silently as autopilot speed changes. Commit will land via #803.

---

## 2026-05-17

### honest-uncertainty-beats-clever-extrapolation — refuse to project when the sample doesn't support it
A real-device 2-weigh-in install ("+1.3 lbs over 5 days") was displayed as "+4.41 lbs/wk" and "+1714 cal/day surplus" both labelled "based on last 21 days" because `WeightTrendCalculator`'s fallback path projected the most recent 2 points to a weekly cadence when the regression and two-window methods lacked data. The label-mismatch was as bad as the number — the UI claimed 21-day evidence for a 2-point extrapolation. Standing rule for any UI surface displaying a derived metric over a window: the displayed window has to match the actual evidence used. When evidence is too thin to project honestly, ship a "need more data" affordance rather than fabricated certainty. Commit `5a3f6eec`.

---

## 2026-05-16

### human-action-register-replaces-cycle-relabeling — named owner + deadline is the missing mechanism
#708 backup E2E dogfood entered its 4th consecutive cycle open despite cycle 10262's "escalate to human-action in daily exec" recommendation being followed (relabel succeeded). The relabel didn't produce action because the escalation mechanism was missing (1) named owner, (2) deadline, (3) what-happens-when-deadline-passes. Filed #789 to build `Docs/human-action.md` register + `human-action-service.sh` + EXEC-TEMPLATE integration. Standing rule: items that need a human-not-Claude action are not sprint-tasks — they belong in the register with owner + deadline + visible fallback. After deadline passes, the feature ships flagged "engine validated, restore not field-tested" rather than carrying as "still open." Commit `46ec7d41` (review cycle 10888 PR #787).

### testflight-archive-pipeline-is-resilient — 6 builds shipped in 72h after cycle-10262 archive failure
The cycle-10262 standing rule ("failed archive within 24h = auto-P0") fired correctly via #770 and the pipeline shipped 6 builds (244-250) in 72 hours. The standing rule worked end-to-end for the first observable test. Lesson: when a tenet ("TestFlight reach is part of the product") is operationalized into a P0-trigger rule, AND the rule has a single owner discipline, AND the diagnostic is documented (xcodebuild log analysis path), the recovery time collapses from 17 builds (cycle 8799) to 1 day (cycle 10262). The architecture is the discipline.

---

## 2026-05-13

### fm-extractor-flag-off-then-tier3-eval — Foundation Models cutover requires eval gate, not direct flip
The four FM extraction migrations this cycle (#744 CompositeFoodEntry, #745 WorkoutEntry, #748 nutrition label OCR, #749 lab report hybrid) all ship with a feature flag — flag-off path verified by 47 Tier-0 fixture tests against the regex baseline, flag-on path (actual `FoundationModels` calls via `@Generable`) deliberately unverified. Standing rule for any platform-API integration: the flag-off path is the safe ship, the flag-on cutover blocks on a Tier-3 `DriftLLMEvalMacOS` gate that proves ≥95% parity with the regex baseline on the same fixture rows + ≥98% on cases tagged 'critical' (Indian dishes, multi-piece, compound names). This mirrors the cycle 8666 "eval before LLM swap" principle: a regression in extraction would manifest weeks later via friend reports, with no telemetry to catch it. Filed as #771; landing it before flipping the flag is non-negotiable. Commits `b4831b09`, `a65f474b`, `9c6922aa`, `ecd7e103`.

### known-failing-test-must-be-reverified-each-planning — never carry forward a 'still open' claim without re-running
#568 (testPortionScaling_DecimalServings) was carried through 7 consecutive reviews as 'still open' when the underlying fix had actually shipped 2026-05-03 via `9a5b06ea` (#571 cup-to-gram gold-set update). The flag came from stale GitHub state, not stale code. Standing rule: the review template's known-failing-test scorecard line must include a re-verification step — for each test referenced as 'open' or 'still failing' in any prior review's Technical Debt, re-run it locally in the planning cycle; if it passes, close the issue and remove from carry-forward. Without this, review recommendations become noise that suppresses other work. Filed as #780 (template update). Commit `272d8293` (close + reset).

### heartbeat-side-branch-not-throttle — operational state belongs off `main`, not slow-on-main
Heartbeat noise persisted across cycles 9688/9760/9792/9851 *after* #642 batching shipped — three reviews of "still flagged." Root cause (#758): the batching reduced commit frequency but didn't change the destination. Snapshots were still landing on `main` at ~30 per real ship commit. New invariant: operational state never goes on `main`. The fix routes heartbeat snapshots to a dedicated side branch (commit `272d8293`). General lesson: when the same complaint appears in 3+ reviews after a "fix" was applied, assume the fix addressed the wrong layer — re-diagnose, don't re-verify.

---

## 2026-05-10

### food-db-curated-not-exhaustive — ≤6,000 entry ceiling, batch imports rejected
Build 217 USDA Phase 2 bulk import (`af3f50e9`, +7,556 entries) took foods.json to 11,162 (3.7 MB). SR Legacy is research-grade noise: "Beans, snap, raw, NS as to color", 50+ variants of one canonical food, industrial-ingredient strings. The food DB is a UX surface that ships *embedded* — bulk grows install size, slows cold-launch DB-init, dilutes search ranking for the Indian-food-first entries that justify the app's existence. New tenet (#9 in product focus): **curated, not exhaustive**. Planning step 9a now reads `wc -l foods.json` each cycle, files/keeps a curation task if above ceiling, and rejects batch-import feature requests without a curation plan attached. Each new entry must justify itself: high-frequency search miss, unique nutrition profile, regional gap users actually eat. The one-time pass (#717, `1e222ec6`) dropped 5,742 multi-comma-bulk + verbose-USDA entries to land at 5,420; new Tier-0 `FoodDBSizeTests` locks the ceiling so future imports can't silently bloat. Commits `603ae058`, `1e222ec6`.

### qa-tester subagent gets its own maintenance loop in planning step 10
The `qa-tester` subagent (added 2026-05-08) is itself a piece of harness that drifts: over-flagging means sessions stop trusting the verdicts; under-generating means real bugs slip through. Planning step 10 now also reviews the last 5–10 closed sprint-tasks' QA-verdict comments looking for: (a) >40% `NOT APPLICABLE` across multiple issues → tighten generators; (b) post-shipped bugs filed within 7 days that no QA scenario flagged → identify missing failure category, add generator; (c) scenarios that caught real bugs across 2+ cycles → promote into stable generators block. Same sediment-and-prune rules as personas (durable in 2+ cycles → into generators; >30 days unsedimented → delete; ≤200 lines). Without this loop the subagent calcifies and either gets ignored or becomes noise. Commit `1474a33b`.

---

## 2026-05-08

### qa-tester subagent + verdict hook — adversarial pass before commit on UI/data-flow changes
Calorie overlay (#669) shipped 4 unit tests but 3 bugs slipped through (empty data, sort-order mismatch, @Observable computed-property gotcha) — all three were scenarios a halfway-decent QA pass would have flagged. New senior protocol step before any commit touching `Drift/Views|ViewModels|Services` or `DriftCore/Sources/{Domain,AI,Persistence}`: invoke `qa-tester` subagent → it returns a markdown checklist of failure scenarios → senior must trace each through actual code paths and either fix or prove handled, then post `## QA scenarios (qa-tester)` block on the issue with one verdict per scenario. `require-qa-verdict.sh` PreToolUse hook blocks the commit if the latest issue comment lacks the verdict block or any scenario remains unchecked. The point is to collapse the multi-commit iteration into one shipping commit by *assuming the code is broken until traced*, not to write more tests after the fact. Commit `d427f870`.

### require-test-on-source-change hook — every source commit ships with a test
Companion to QA pass: `require-test-on-source-change.sh` PreToolUse hook blocks any commit that stages files under `Drift/Views|ViewModels|Services` or `DriftCore/Sources/DriftCore/{Domain,AI,Persistence}` without ALSO staging a test under `DriftCoreTests`, `DriftTests`, or `DriftLLMEvalMacOS`. Edge case (pure typo/comment/asset, genuinely untestable) → include `[no-test]` in the commit message; auditable, use sparingly. Driven by the same #669 calorie-overlay incident — the data-flow bugs would have been caught by even a basic data-flow test, not just the preferences-toggle tests that did ship. Commit `ba46cfa9`.

### backup-allowlist-must-mirror-real-keys — string-typed UserDefaults dictionary is silent data loss waiting to happen
`PreferencesBackup.allowlist` was hand-curated against the conceptual list of preferences the team thought was being persisted; multiple production keys (weightGoal, tdeeConfig, custom_exercises, etc.) didn't match the allowlist string-for-string and were silently dropped from backups for weeks. Two follow-on fixes: (a) #700 — the allowlist must be derived from or explicitly verified against `Preferences.swift` keys; an audit script (`scripts/preferences-allowlist-audit.sh` if it doesn't exist yet, file an issue) should fail CI when they diverge; (b) #701 — `Codable Data` and array-typed preferences (e.g. weightGoal, custom exercises) need first-class round-tripping in the backup encoder/decoder, not "primitive types only" string matching. General lesson: any string-keyed allowlist over a moving target is a silent-data-loss vector — either generate it from the source of truth or verify equality with a test. Commits `791f287a`, `cb87668c`.

## 2026-05-07

### launch-watchdog-budget — defer notification + widget refresh, do not await before syncComplete
After #620 (GLP-1 weekly slot) + #627 (protein adherence 4-of-7), `NotificationService.refreshScheduledAlerts()` issues ~35 DB fetches per launch (5 BehaviorInsight alerts × 7-day windows + medication + GLP-1). Adding HealthKit sync + weight trend + TDEE puts cold launch within iOS's ~20s watchdog kill. New rule: any work that doesn't gate first frame goes in `Task { @MainActor in ... }`, not awaited inline in `DriftApp.task`. Notifications fire on schedule and widget pushes are fire-and-forget — neither gates UI. Commit `36f0cb12`.

### gh-search-index-bypass — sprint listings use REST list, not search
GitHub's `?labels=X` REST calls route through the search index, which had >27-min propagation lag on 2026-05-07 — newly-filed P0 bugs were invisible to both `sprint-service.sh refresh` and the command-center for almost half an hour. Both code paths now do unfiltered fetches (`state=open per_page=100` etc.) and filter client-side. Pattern: when correctness depends on seeing an issue right after it was created/labeled, never depend on `--search` or `?q=label:`. Commits `607c1398`, `e4e757a5`.

---

## 2026-04-28

### remove-db-matching-from-ai — AI workflows trust LLM output directly, no local DB second-guess
Removed `PhotoLogTool.applyDBMatching`, the `log_food` preHook DB lookup paths, and `PhotoLogMatcher.matchFood`. Multiple P0 bugs (#522, #524, #525) traced to DB second-guessing correct AI output — case-sensitive lookups, fuzzy false positives, silent-failure UX when user input doesn't look like a food name. Vision models trained on food photos beat string-distance; AI macros are within ~10-15%, within self-reported noise floor. DB remains for explicit user search (food_info tool), barcode scan, and manual entry. Commit `f97cf10`.

### photo-log-provider-fallback-chain — FallbackVisionClient tries Anthropic→OpenAI→Gemini on transient failures
Single-provider photo log meant any transient API failure (rate limit, 5xx, timeout) blocked the feature entirely. New `FallbackVisionClient` actor tries providers in order, advancing on transient errors and aborting immediately on permanent ones (401, malformed, offline). Keys fetched lazily so biometrics only prompt for the provider actually needed. Provider name appended to chat summary when fallback was used. Commit `866c074`.

### remote-byok-chat — cloud chat shares Photo Log key, no separate setup
`AIBackendType` gained `.remote`; `LocalAIService.useRemoteBackend()` accepts an apiKey from the iOS shell (DriftCore never touches Keychain). Cloud chat reuses Photo Log's `CloudVisionKey` entry + provider/model preference — once Photo Log is configured, chat is free. `Preferences.preferredAIBackend` defaults to `.llamaCpp` (privacy-first); the in-chat cpu/cloud toggle only renders when both backends are available so it can never be a no-op. `RemoteLLMBackend` now ships native parsers for Anthropic / OpenAI / Gemini SSE (text + tool calls), with categorized errors (`auth | rateLimited | quotaExceeded | transient | malformed`) so the chat layer can decide whether to auto-fallback to local (transient only) or surface a retry CTA. Photo conversational flow (`propose_meal` + `ProposedMealCardView`) deferred to a follow-up — the prompt protocol is baked into `IntentClassifier.remotePrompt`, but the inline-card UI + photo attachment are not yet wired. Issue #515.

## 2026-04-27

### simpler-snapshot-than-branches — patch files replace `crashed/<N>` branches
Crashed sessions now preserve WIP as `~/drift-state/wip/<N>.patch` (+ `.untracked.tar.gz` for new files), updated every 30s by the watchdog. Replaces the earlier `crashed/<N>-<ts>` branch model (`0abd0e9`). Reasoning: branch ceremony was too heavy — remote branches accumulated, recovery required PR/merge, multi-step protocol. Patch files give 1-line `git apply` recovery. Tradeoff accepted: local-only (drift-state has no remote) — if the machine dies the work is gone, which is true regardless. Latest commit: see `chore: hook-generated updates` cluster around 08:11–08:13 PDT.

### file-edit signal on stale-claim — work-in-progress no longer flagged
`check_stale_claim` now treats real file edits in working tree (filtered: not heartbeat/graphify/xcodeproj) as a third progress signal alongside commits + comments. Was: 60-min auto-flag on #426 fired despite 7 real edits sitting in working tree because session hit Anthropic API stream timeout right before its first commit. Combined with the threshold raise to 90min, false-positive rate should drop sharply.

### stale-claim threshold 60min → 90min
Multi-file senior tasks (new tool + tests + registration) legitimately need 60–90 min before first commit. The 60-min threshold was catching #426/#418-style work falsely. Override via `DRIFT_CLAIM_STALE_THRESHOLD_SECS` env var. Doesn't fully solve API-timeout work loss (the WIP-patch system above does that).

## 2026-04-26

### regress-on-raw-weights — slope/surplus/projection no longer use EMA series
`WeightTrendCalculator` used to do linear regression on EMA-smoothed values. For users with a recent regime change (gained-then-losing), the EMA lags actual weight by weeks; regressing on it measures the EMA *catching up*, not the user's actual rate. Reported as "+1870 kcal surplus" on a real user who was clearly losing. Now: regression on raw filtered weights, with two-window endpoint method (`avg of first 7-day window` vs `avg of last 7-day window`) for noise reduction. Adaptive widen to 42-day window when slope is below 0.5 lbs/wk threshold. Commit `e25afe3`.

### time-weighted EMA — display "Trend Weight" no longer cadence-dependent
EMA was entry-indexed (`α = 0.1` per entry). For weekly weighers, ~13 entries in 90 days meant the seed weight kept ~25% influence — Trend Weight stuck near old regime forever. Now: `α = 1 − 0.5^(Δt/halfLife)` where `halfLife` is in days (default 14). A daily and weekly weigher with the same actual trajectory now produce the same Trend Weight. Commit `e25afe3`.

### iOS test runner — `-skip-testing` not `-only-testing` for the bundle filter
`xcodebuild test -only-testing:DriftTests` silently dropped 1211 of 1249 tests in Xcode 26 — only XCTest classes get included with bundle-level `-only-testing`; Swift Testing (`@Test`) functions are bypassed unless filtered by full test ID. All operational hooks/scripts/CLAUDE.md migrated to `-skip-testing:DriftLLMEvalTests` which includes both frameworks. Autopilot had been shipping commits saying "All tests pass" while running 3% of the iOS suite. Commit `84a6e1a`.

### hard gate on Bash|Read|Grep|Glob until claim
Sessions were running `next --senior` (read-only) instead of `next --senior --claim`, then self-directing into work from the issue body without ever tagging in-progress. Initial Bash-only gate was bypassed via Read/Grep tools. Extended hook to gate all four PreToolUse tools, with a tight orient-only allowlist (`sprint-service.sh`, `gh issue view`, `cat docs`, `ls/pwd/echo`). After claim: full freedom. Commit `a26780e`.

### plan-comment required before commit (autopilot only)
Documented discipline ("post a Plan: comment before implementing") was at ~15% compliance. Auto-flag fires on `git commit` if the in-progress issue has no comment matching `^(Plan|Approach|Investigation|Progress|Resolution)\s*[:\-]`. Commit `ebff0c3`, fixed for stdin-JSON in `8d90f11`.

### `Source:` line required on every new sprint-task
Planning's old order ("P0 → product focus → admin feedback → roadmap → parity gaps") didn't track *which* source a task came from. Tasks could be created without mapping to anything. Now every body must include a `Source:` reference (one of: `campaign-<slug>`, `review-cycle-<N>`, `P0-<short>`, `feedback-<note>`, `roadmap-<item>`). Goal ≥90%. If planning can't map most new work to a source it's freelancing — flag and don't invent. Commit `cc8485d`.

### hooks defer pkill when xcodebuild archive is running
`coverage-gate.sh` (post-commit) and `preflight-check.sh` ran `pkill -9 -f xcodebuild` before their own xcodebuild test. While a TestFlight archive (5–10min) was running, a parallel session commit would kill the archive. Build 178 failed twice this way. All sites now `pgrep -f "xcodebuild.*archive"` and defer if found. Commit `58d90bb`.

### Design tenets in CLAUDE.md (philosophy, not procedure)
Sessions had no prescriptive philosophy doc — only the 4-line Color Philosophy. Added 10 tenets covering: AI chat as showstopper, privacy-first, goal-aware color, Indian food bar, friend feedback over telemetry, DriftCore-by-default, one-tier-per-test-file, no compat shims, three-lines-before-abstraction, build-test-after-every-change. Tenets, not patterns/file paths — survive folder moves. Commit `a690d43`.

### FM composite-food extractor cutover blocked — Tier-3 eval gate quantified the gap
Design-666 QW2 shipped `CompositeFoodExtractor` (Apple Foundation Models) with a flag default of ON, but the flag-on path had no Tier-3 quality measurement — flipping was a leap. New eval target `CompositeFoodExtractorFMEval` (#771) replays the 30-row gold set against the real `@Generable` schema on macOS 26. Measured today: **90% overall (27/30), 40% on FM-win rows (2/5)** — the bare-juxtaposition Indian compounds "dal chawal" and "rajma chawal" come back as `.notComposite` (model treats them as single dish names rather than splitting). That's below the design-666 QW2 cutover bar (≥95% overall, ≥98% FM-win). Eval split into a regression-floor test that runs always (locks current quality so a drop is loud) and an `DRIFT_FM_EVAL_GATE_STRICT=1` env-gated test that enforces the cutover bar. Run the strict gate twice green before flipping; the gap closure (prompt tweak / fallback rule for bare-juxtaposition / fine-tune) is a separate work item. Workout / Nutrition / LabReport extractor evals deferred — same pattern, different structured comparators.

---

*Older decisions live in commit messages, `Docs/refactor/`, `Docs/audits/`. This file starts here.*

### verifier/planning debate — spawn participants DIRECTLY, never via debate-moderator (2026-05-29)
A subagent cannot nest sub-agent spawns (the harness allows one level only). `debate-moderator`
is itself a subagent whose only tool is `Agent`, so when /senior, /junior, /planning, or
/design-doc invoked it, it tried to spawn its participants as *sub-subagents* and stalled with
zero completed tool calls — every verification/planning debate. Sessions then burned context
working around it and abandoned on budget exhaustion. Observed as #869 churning across ~6 senior
sessions in 1.5h with no commit (and pre-flagged in this log: "planning-debate-participants-empty").
Fix: each caller now spawns the participants (qa-tester + principal-engineer / engineer + designer)
DIRECTLY in parallel and applies the merge rule itself (any REJECT→REJECT; else any FIX→FIX; else
PASS). `debate-moderator.md` deprecated (kept, not invoked). Do NOT reintroduce the moderator layer —
the nesting limit makes it stall, it is not a flake to retry.

### #875 Today's Brief deferred post-launch; epic #887 = Drift Coach launch hardening (2026-06-19)
Planning override cycle 19118. Stuck epic #875 (proactive "Today's Brief") was NOT stuck on arc
scoping — verify-at-file:line showed 4 of 6 subtasks genuinely DONE on main (#876 service, #877
narrator @ commit `15ea3527`, #878 card, #885 grounding eval @ `decisions.md` 100% rate); the epic
body just carried stale `status="open"` text for already-closed #877/#885. The real reason it never
drained: the **product pivoted to Nebius cloud** (#872 FM-revert) + **launch hardening T-1 day "NO
new features,"** which orphaned the remaining surface work (#879 integration, #880 notification).
Decision: **defer #879/#880 post-launch, close the epic.** Decisive engineering fact (PE-confirmed):
`BriefNarrator.narrate` → `LocalAIService.respondDirect` (BriefNarrator.swift:185) runs on **Nebius**
on the launch build, NOT the Gemma 4 its 100% grounded rate was measured on — wiring it now ships
*unmeasured-on-Nebius* health-number narration (the #801 over-claim bug class). Engine stays on main
unwired (acceptable only because surface tasks are tracked). RESUME: re-run the grounding eval against
Nebius (Qwen3-235B) before any wiring. New epic **#887** hardens Drift Coach for launch — 7 subtasks
(#888-894), grounded in an Explore + PE/PD debate. Two debate catches worth remembering: (1) the
"lingering spinner" is NOT missing error/retry (that exists + is tested, `handleRemoteBackendError`/
`retryTurn`) — the real bug is **no `timeoutInterval` in RemoteLLMBackend.swift** (rides URLSession's
60s default); (2) chat color debt lives in `AIChatView+Cards.swift` (raw `.green/.red/.orange` on
confirm/insight cards), not just the one `Color.red` in AIChatView.swift. Queue-staleness note for
next cycle: several pre-pivot V7 tasks remain (#833/#835/#847 visual refresh, #829 build-261 notes) —
candidates for prune/re-triage if still unclaimed; closed #834 (FM-backend multi-turn, superseded by
#892).

### Knowledge curation pass 2026-06-26

Ran 7 days after the prior full curation (2026-06-19, which drained cycles 9851–10950). No-op for
content — nothing crossed a threshold:

**Sedimented into stable:**
- principal-engineer.md: 0 entries — `<what_i_learned>` holds only the 2026-06-19 curation note; no new dated `### Review Cycle` entries appended since (file untouched since Jun 19, `/planning` step 13 added nothing).
- product-designer.md: 0 entries — same; `<what_i_learned>` is just the 2026-06-19 note.
- qa-tester.md: 0 entries — `<learnings>` is just the 2026-06-19 note.
- signs (skill bodies): 0 entries — every dated sign references an incident <90d old (planning.md: cycles 9851–10950 / 2026-05-31→06-04; senior.md cycle 9792). The cycle-8000-era READ-before-EDIT sign is older but is a live harness-enforced guard still producing violations, so it fails the "no violation in the period" half of the sediment test and stays. junior.md signs are timeless role-boundary rules with no dateable incident.

**Pruned (recoverable for 1 cycle):**
- None — no sign is ≥180d old (signs files date to 2026-05-18 / 06-04, all post-2025-12-28), and no agent-file learning entry was pending.

(debate-moderator.md is a deprecated stub with no learnings/knowledge block — nothing to curate.)

Total agent-file line counts after curation (all unchanged, well under cap):
- principal-engineer: 127 / 300 cap
- product-designer: 118 / 300 cap
- qa-tester: 91 / 250 cap

### Knowledge curation pass 2026-07-03

Ran 7 days after the 2026-06-26 pass (itself a no-op). Same result — nothing crossed a threshold. The
last content-bearing curation remains 2026-06-19 (which drained cycles 9851–10950).

**Sedimented into stable:**
- principal-engineer.md: 0 entries — `<what_i_learned>` still holds only the 2026-06-19 curation note; `/planning` step 13 appended no new dated `### Review Cycle` entries since.
- product-designer.md: 0 entries — same; `<what_i_learned>` is just the 2026-06-19 note.
- qa-tester.md: 0 entries — `<learnings>` is just the 2026-06-19 note.
- signs (skill bodies): 0 entries — every sign is <90d or an undatable-foundational contract rule. planning.md gained two override signs since 06-26 (stuck-epic override is count+counter-driven, cycle 20840 / 2026-06-30; false-positive-override on a gate-unmet epic, cycle 20462 / 2026-06-27) — both <90d, don't qualify. senior.md's cycle-8000-era READ-before-EDIT sign remains a live harness-enforced guard, so it fails the "no violation in the period" half of the sediment test and stays. junior.md signs remain timeless role-boundary rules with no dateable incident.

**Pruned (recoverable for 1 cycle):**
- None — no sign is ≥180d old (earliest signs date to 2026-05-18), and no agent-file learning entry was pending.

(debate-moderator.md remains a deprecated stub with no learnings/knowledge block — nothing to curate.)

Total agent-file line counts after curation (all unchanged, well under cap):
- principal-engineer: 127 / 300 cap
- product-designer: 118 / 300 cap
- qa-tester: 91 / 250 cap

### TDEE base formula: sqrt curve → sex-averaged Mifflin default (2026-07-07)

Pre-release audit of TDEE/deficit found the no-profile base `2000·√(w/70)·(act/29)` systematically
lowballed heavier users: 100 kg no-profile got 2390 vs Mifflin ~3020 / "15 kcal per lb" ~3300; even a
FULL profile only pulled 0.4 of the gap (2642, still −12% vs Mifflin). This was the top field-complaint
cluster ("people of different weight groups / people who haven't filled up profile well").

Decisions:
1. `computeBase` = sex-averaged Mifflin with default assumptions (age 30, 170 cm): `(10w + 834.5) ×
   activityFactor`, soft cap raised 2700 → 3000 (0.3 compression above). Linear in weight; tracks the
   lb×15 heuristic for typical weights without exploding at extremes.
2. Mifflin correction weight 0.4 → 0.7 (× profile confidence): a real profile is strictly better
   information than the base's default assumptions; still dampened so a typo'd age can't own the number.
3. `fetchWeightTrendTDEE` now guards `trend.hasInsufficientData`: a calibrating trend publishes
   deficit 0 as a PLACEHOLDER, and anchoring `TDEE = intake − 0` against it told dieting users their
   maintenance was their intake — the "app recommends less calories when I skip/partial-log" complaint.
   No real trend ⇒ no trend anchor (the qualified-day median + 50% consistency gate already handle
   partial logs; this closes the sparse-weigh-in hole).
4. Blend extracted to pure `TDEEEstimator.blend(...)` so Tier-0 tests drive every source combination
   without DB/HealthKit; sanity-band tests now pin base within ±15% of sex-averaged Mifflin across
   45–140 kg and full-profile within ±12% of true Mifflin, so a future "conservative" curve can't
   silently reintroduce the lowball.

Existing users will see a one-time TDEE step-up (e.g. +450 for 100 kg no-profile). That's the fix
working, not a regression — the old number was the complaint.

### Weight-trend rate: significance zeroing → two-tier confidence ramp (2026-07-07 evening)

Operator field session (their own bulk data, cross-checked against a competing tracker): the 2026-05-29
significance gate zeroed a REAL young trend — chart visibly climbing +1.4 lbs over 5 weeks, cards stuck
on "≈0 · Holding steady", Projected flat — while Weekly (raw, added that morning) showed +1.25 lbs/wk.
Operator: "it's fine to report surplus — why is it saying holding steady?" But removing the gate outright
resurrected the May bug verbatim (flat-noisy pinned dataset read −256 kcal/day; original complaint −248).

Measured t-statistics on the pinned datasets found an empirical gap:
pure-noise seeds 0.15–0.89 · May flat-noisy user 0.26 · operator's real-but-young bulk 1.73 ·
established cuts/bulks 2.3–12.

Decisions:
1. Rate smoothing half-life 5d → 8d: the 5d slope overshot a bulk-start week (+0.57 kg/wk → +622 kcal/day
   vs ~0.40 the smoothed trend supports); the full 14d display EMA was tried and REJECTED — it kept the
   wrong SIGN 3+ weeks after a regime change (regimeChange_* tests, the "+1.2 lbs but −213 deficit" class).
2. Publish the rate scaled by a CONFIDENCE RAMP on the raw-window t-stat: weight 0 at t=1.0, full at
   t=1.6 (constants reportRampStartT/reportRampFullT). Noise stays zeroed (max noise t 0.89), young real
   trends fade in, and no hard boundary exists for one weigh-in to flap the card across (stability test
   caught a 270-kcal flip at a hard bar).
3. significanceTThreshold (2.0) survives as trendIsSignificant — UI framing only: "Early trend — firming
   up" between ramp and 2.0, "Based on last N days" above.
4. Weekly, Est. Balance, AND Projected now all derive from the same reported rate — the operator's
   screenshot showed "Weekly +1.25 / Projected +0.0 in 30d" side by side, which read as broken math.

Result on operator's data: +0.40 kg/wk → +437 kcal/day → 30d projection +3.7 lbs — coherent with the
competing tracker (0.38 / 418 / +1.7 kg) while our heavier smoothing stays calmer on spikes.

### Trend report gate: OLS-t → Mann–Kendall Z (2026-07-08 morning)

Field falsification within 12 hours of the t-ramp shipping: the operator's REAL 21-day window — 9
weigh-ins, one +3.8 lb water spike, a 10-day logging gap — scored t=0.96, BELOW the measured pure-noise
ceiling (0.89–1.00 across seeds), so the ramp zeroed a trend that was visibly real (14d/30d trend deltas
read "+1.4/+1.6 Increase" on the same screen as "Weekly ≈0.0 Holding steady"). The 2026-07-07 t=1.73
calibration for this dataset was an artifact: the reconstruction invented points inside the logging gap.

Root cause is structural, not calibration: OLS-t is wrecked by exactly the two shapes real dieters
produce — a single spike (huge squared residual craters R²) and gaps (few points inflate the slope's
standard error). Rank-based Mann–Kendall counts concordant pairs instead of fitting a line: measured
separation on the pinned datasets is decisive — noise seeds Z=0.33–1.00, May flat user Z=0.34, the real
gap+spike bulk Z=1.68, genuine trends Z=2.6–6.3, weekly sparse logger Z=2.6.

Decisions:
1. `trendZStatistic` (MK with tie correction + continuity correction) replaces `tStatistic`; `rSquared`
   deleted (dead). Report ramp on Z: 0 at 1.15, full at 1.65; confident flag at Z ≥ 2.0.
2. The operator's exact 9-point dataset is pinned as
   `regression_gapAndSpikeRealTrend_reportsNotHoldingSteady` — gaining, reported rate, visible surplus.
3. This pulls item 2 of #1024 forward; #1024 keeps daily-grid interpolation + expenditure-card surface.

Method note for future gate changes: calibrate on the pinned real datasets FIRST (scratch diagnostic,
measure, place constants in the measured gap) — the t-ramp shipped on a reconstructed dataset and was
falsified by the real one the next morning.

## 2026-07-15: Hot-path perf discipline — precompute keys, batch per-day loops, bench at year scale

A friend reported a ~1s hang on the food-logging Log button one day after build 352 shipped. Root
cause: the AG1 dedupe fix (same build) fetched EVERY food name and normalized each in Swift, per
logged item, synchronously inside the button press — plus logFood reloading the day + posting
.foodEntryAdded per item (the #949 problem, never applied to logFood). A three-agent sweep then found
the same disease elsewhere: BehaviorInsightService issuing ~100 serial per-day DB queries per dashboard
load, an unbounded food_entry GROUP BY on every Add Food sheet open, a 1MB JSON decode + ~100
UserDefaults blob decodes before first frame, a 5×-per-render CGM re-parse, and a per-day HealthKit
sleep loop.

Decisions:
1. Derived lookup values (dedupe keys) are PERSISTED + INDEXED at write time (food.normalized_key,
   v44), never recomputed over the table at read time. The Food record derives the key from name at
   init/decode/didSet so no write path can forget it; a canary test fails on any NULL key.
2. Per-day query loops are banned on hot paths — use ranged GROUP-BY batch queries
   (fetchDailyNutritionRange pattern) + in-memory bucketing. Same rule as the #1008 HealthKit storms.
3. Multi-item logging goes through batch APIs (logFoods) — one day-reload + one notification per user
   action, never per item.
4. Tier-4 HotPathLatencyBench (DRIFT_LATENCY_BENCH=1) seeds a year-scale DB and asserts
   order-of-magnitude ceilings on the Log press / Add Food / dashboard-insight / dedupe paths. Run it
   after touching those queries. Once-in-a-while checks (Xcode Organizer hang rate per TestFlight
   build, Thread Performance Checker, Instruments Hangs) documented in development-sop.md §9.

Method note: the LIKE-prefilter interim fix silently broke dedupe because `"str".split(separator: " ")`
resolved to a Character-chunk overload whose interpolation produced garbage that matched nothing — the
existing AG1 regression tests caught it. Perf rewrites of correctness-bearing queries need their
correctness tests run BEFORE trusting the timing win.

## 2026-07-15: Doc governance — point-in-time state lives in issues, knowledge lives in .md

Operator-set policy after Docs/failing-queries.md drifted into a queue pretending to be knowledge.
The split:
- **GitHub issues (scoped, labeled, closeable)** = point-in-time state: failing queries
  (`failing-query` label — one issue per query class, closed when it routes correctly), bugs,
  sprint tasks, eval-red trackers. If it has a lifecycle, it's an issue.
- **.md in git** = long-term knowledge that stays true: development SOP, principles, architecture,
  design docs, roadmap, this decisions log. Committed AND local.
- Resolved point-in-time history needs no ledger — git log and closed issues ARE the ledger.

Applied: Docs/failing-queries.md retired; its 5 open classes filed as #1053-#1057 under
`failing-query`; CLAUDE.md Doc Map + SOP §5 updated. The planning-service evidence-guard regex
("failing-quer…") already matches the label name, so sprint-task justification cites keep working.

## 2026-07-15 (later): Docs/ restructure applying the issues-vs-knowledge policy

Swept Docs/ with the same lens. Deleted dead point-in-time docs (sprint-plan.md — 3 months stale,
queue lives on GitHub; llm-eval-results.md — April snapshot of a model we no longer use;
synthetic-queries.md — superseded by eval gold sets in code). Shipped harness-phase-2/3 specs and
the audits/ snapshots moved to Docs/archive/ (frozen history). usda-api-design.md moved to
Docs/designs/. Docs/refactor/ is now ACTIVE plans only — each must have an owning OPEN issue
(estimation-unification ↔ #1052); shipped specs graduate to archive/. state.md retirement is #1058
(it has live harness deps — freshness hook, watchdog, daily-exec routine — so it's a scoped task,
not a doc shuffle). Doc Map in CLAUDE.md now covers every living doc: previously unmapped
tenets.md, drift-control-design.md, ai-chat-architecture.md (deep-dive; architecture.md is the
overview), ai-autoresearch.md, licenses.md, designs/.

## 2026-07-18: Android port — Swift stays the single language (Skip Fuse + official Swift Android SDK)

Operator decided to port Drift to Android with full parity. Chosen architecture: DriftCore
compiles natively for Android with the official Swift 6.3.3 SDK (no Kotlin rewrite), UI via
Skip Fuse (SwiftUI → native Compose from the same source). AI ladder on Android mirrors iOS
with Google intelligence in Foundation Models' slot: Nebius cloud → Gemini Nano (ML Kit
GenAI) → llama.cpp CPU. Distribution: Play Internal Testing (TestFlight equivalent);
workout vertical slice ships to a friend first. Non-obvious findings baked into scripts/:
Xcode's Swift can't cross-compile for Android (module-format mismatch — swiftly toolchain
required); NDK ships no sqlite (vendored + installed into NDK sysroot, MUST be built with
SQLITE_ENABLE_SNAPSHOT for GRDB and -fPIC); SwiftPM binaryTargets are rejected when staged
by skipstone even if platform-conditioned out (#filePath gate in DriftCore/Package.swift);
dependency-package resource bundles never reach the APK (app-module mirror + boot-time
extraction to the exact path Bundle.module probes; NSHomeDirectory() on Android IS files/).
`scripts/android-build-check.sh` is the enforced portability invariant — keep it green like
the macOS build.
