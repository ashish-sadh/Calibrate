# Drift Tenets

Consolidated from CLAUDE.md design tenets, GitHub issue #111 (active campaigns), `program.md`, and persona-accumulated learnings. Changes infrequently. Read by `/planning` step 6 (feature-request triage) and as ground truth for product decisions.

If you're editing this file: add a single line at the top of "Recently sedimented" describing what changed and why, and remove it from there only when 90+ days have passed and no rules have changed in response.

## Core tenets

1. **AI chat is the showstopper.** Every data entry must be doable through conversation; UI exists for visual analytics and as a fallback.
2. **Privacy-first.** Health data lives on-device; no account is required to use the app. A cloud touchpoint is allowed only when it is opt-in, minimal, server-enforced and surfaced (the five-part test in `Docs/decisions.md`). Amended 2026-07-28: this used to read "no cloud, no accounts, no analytics" — BYOK photo logging, the Nebius Coach, friends/sharing and anonymous usage telemetry all now exist under that test. What survives is the intent: nothing SILENT leaves the device.
3. **Goal-aware color, never "good/bad".** Green = aligned with the user's goal direction; red = against it. Default goal: losing weight.
4. **Indian food is the bar.** Every food list, search, parser, and eval works for Indian cuisine first; everything else is downstream.
5. **Friend feedback first, telemetry second.** When unsure if a feature is RIGHT, ask a user — counts tell you what happened, never why. Amended 2026-07-28: anonymous usage telemetry now exists (ON by default, opt-out) to answer "what do people actually reach for", and opt-in AI-conversation capture to answer "where does the Coach get it wrong". Neither replaces asking someone.
6. **DriftCore by default.** If a file doesn't import UIKit/SwiftUI/HealthKit/WidgetKit/AVFoundation/Speech/Photos/AppIntents, it belongs in DriftCore.
7. **One tier per test file.** Mixing Tier-0 logic with Tier-3 LLM-backed asserts is the failure mode that turned the old suite into a liability.
8. **No backwards-compat shims.** Change the code, delete the old, no `_oldXxx` aliases or "removed" comment markers.
9. **Three similar lines beats premature abstraction.** Don't extract on the second occurrence; consider it on the third.
10. **Build and test after every change.** The harness will block the commit if you skip; trust the discipline, not your gut.
11. **Engine-without-surface is half-shipped.** Always pair engine PR with surface task in the same sprint.
12. **TestFlight reach is part of the product.** Failed archive within 24h = auto-P0.
13. **Eval coverage ships in the same commit as the feature.** "File eval cases later" is the root cause of eval debt.
14. **Tenets without rules are aspirations; tenets WITH rules are infrastructure.** When a tenet matters operationally, promote it to a check (hook, label, auto-P0 trigger).

## Operational rules (auto-firing)

These are tenets that have been promoted to rules and now fire automatically (via hooks, planning steps, or watchdog):

- **Failed TestFlight archive within last 24h** → auto-P0 senior task at next planning (issue #770).
- **Same gap surfaces in 3 consecutive product reviews** → auto-P0 regardless of competing priorities (push-notifications precedent).
- **Sprint-task deferred 3+ cycles** → auto-P0.
- **Issue created >500 cycles ago** → re-validation required before re-claim.
- **Queue cap 70; senior queue ≤15 = healthy drain.** Senior task additions ≤2 per planning cycle when SENIOR queue >15.
- **Sprint scope: 4-5 items max** drives 100% completion.
- **Same-sprint response** to user-filed bug batches AND competitive market signals.
- **Run eval before AND after every AI change.** If accuracy drops, revert — no exceptions.
- **Every commit to main has a `<verifier_verdict decision="PASS">`** (post-rewrite). No WIP commits to main.
- **TestFlight build with no user-visible features** in description auto-flags at next planning cycle.
- **Passive activation lever shipped without paired active ask** → file the active-ask task in the same sprint.

## Feature-request triage rubric

Used in `/planning` step 6 (feature-request triage). Explicit version of what was implicit before.

```
FR is a sprint-task this cycle IF any:
  - aligns with a current #111 campaign tenet
  - same FR reported by ≥3 distinct users (count by author + email/handle)
  - blocks privacy/data-correctness/AI-chat top-feature paths
Else: label `deferred`, comment "Deferred; re-assessed next planning cycle if [tenet]/[reports] change."
After 3 cycles deferred AND no new evidence: label `declined`, close with rationale.
```

## Performance budgets (hard limits)

- **iOS cold launch <2s.** Heavy work (Notification + widget refresh + ~35 DB fetches) must run in `Task { @MainActor in ... }`, not awaited in `DriftApp.task`.
- **n_ctx** progression 2048 → 4096 → 6144. Every bump ships with a prompt audit.
- **Auto-unload after 60s idle** keeps memory in check.
- **iOS 20s watchdog** at cold-launch; any blocking work must be detached.

## What we do NOT do

- No multi-agent fork ships without an experimental flag and rollback.
- Telemetry-dependent sprint tasks are allowed as of 2026-07-28 (anonymous usage + opt-in AI capture ship to Supabase). Still avoid tasks that need data the pipeline does not collect — there is no per-user funnel, no retention cohort, no session replay.
- No `_oldXxx` rename pattern; no "removed" comment markers; no backwards-compat shims.
- No `/compact` in autopilot sessions (planning re-splits over-budget tasks instead).
- No commits to main without PASS verdict (post-rewrite).
- No Anthropic cloud routines that need local Xcode (TestFlight stays local launchd).
