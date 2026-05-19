# Windowed-Calculation Audit — May 2026

**Issue:** #801 — every UI surface that displays a derived metric over a labeled window must either gate on a min-sample threshold or downgrade the label to honest uncertainty when math used fewer points than the label claims.

**Motivation:** Commit `5a3f6eec` patched the 2-point extrapolation in `WeightTrendCalculator` that showed `+4.41 lbs/wk based on last 21 days` from 2 weigh-ins. This audit confirms the pattern is now isolated to the already-fixed `WeightTrendCalculator` path and enumerates every sibling surface that grep flags, with a per-surface verdict.

**Grep used (criterion-2 verifier):**
```
grep -rE 'last [0-9]+ days|past [0-9]+ days|over the last|based on' \
  Drift/Views/ DriftCore/Sources/DriftCore/AI/Tools/ DriftCore/Sources/DriftCore/Domain/
```
32 hits across 3 directories. Audit below classifies each.

## Verdict legend

- **gated** — surface already gates math on a min-sample / min-span threshold; sparse-data path returns an "insufficient" / "—" affordance instead of a fabricated number. No change needed.
- **non-label** — grep hit is a code comment, internal doc-comment, or LLM-tool-description string, not a user-facing label. No risk of UI/math divergence.
- **fixed-in-PR** — surface was producing a label / math divergence; gated in this PR.
- **n/a** — match is on the literal "based on" inside a code comment about the *bug pattern itself*, not a calculation.

## Per-surface table

| # | File:line | Surface kind | Asserted window / phrasing | Math evidence | Verdict |
|---|-----------|--------------|----------------------------|----------------|---------|
| 1 | `Drift/Views/Workout/BodyMapView.swift:202` | code comment | "past 7 days for weekly volume display" | exercise log count over last 7 days; no min-sample (count is naturally robust — 0 sets = 0) | non-label |
| 2 | `Drift/Views/Workout/WorkoutView.swift:77` | code comment | "Apple Health Workouts (last 7 days)" | comment, no UI label | non-label |
| 3 | `Drift/Views/Food/FoodTabView.swift:253` | code comment | "Fixed week based on weekOffset" | comment, no UI label | non-label |
| 4 | `Drift/Views/AI/AIChatView+MessageHandling.swift:434` | chat string | "Built a session based on your history" | string emitted only when `exercises` is non-empty; empty-history path uses a different message | gated |
| 5 | `Drift/Views/AI/AIChatView+MessageHandling.swift:1604` | code comment | "attach structured cards based on which tools ran" | comment, no UI label | non-label |
| 6 | `Drift/Views/AI/AIChatView+Suggestions.swift:155` | code comment | "Determine meal type based on time of day" | comment, no UI label | non-label |
| 7 | `Drift/Views/AI/AIChatView+ChatBubble.swift:7` | code comment | "dispatches based on which optional payload is set" | comment, no UI label | non-label |
| 8 | `Drift/Views/Shared/V6BodyTile.swift:149` | code comment | "rate is based on outdated data — same affordance the legacy …" | comment describing the bug-affordance contract for this tile | n/a |
| 9 | `Drift/Views/Supplements/SupplementsTabView.swift:221` | code comment | "Bar chart: daily completion rate over last 30 days" | comment over a SwiftUI Chart; chart renders zero bars for days with no logs (naturally honest — empty = no bar) | non-label |
| 10 | `Drift/Views/Settings/MoreTabView.swift:451` | **UI label** | "Learn from the last 30 days. Needs 10+ entries per meal — falls back to defaults below threshold." | macro-from-history feature: the threshold is in the copy itself (`Needs 10+ entries per meal`); falls back to defaults below threshold | gated |
| 11 | `Drift/Views/Settings/MoreTabView.swift:498` | **UI label** | "Weekly notification on your injection day — only fires if you haven't logged a dose in the last 7 days" | notification fires conditionally on the dose-in-last-7-days check; UI describes the gate accurately | gated |
| 12 | `Drift/Views/Settings/MoreTabView.swift:823` | code comment | "Export last 90 days" | comment, no UI label | non-label |
| 13 | `Drift/Views/Weight/WeightInsightsView.swift:98` | **UI tooltip** | "Estimated daily caloric deficit/surplus based on your weight trend over the past \(trend.rateWindowDays) days." | uses dynamic `trend.rateWindowDays` (the 5a3f6eec fix exemplar — the label reports the *actual* window the math used, not the configured one) | gated |
| 14 | `DriftCore/Sources/DriftCore/AI/Tools/CrossDomainPatternDetectorTool.swift:66` | **tool output** | "One pattern over the last \(windowDays) days:" | uses dynamic `windowDays` parameter passed in from caller; pattern list returns empty when no patterns detected, and the tool short-circuits with a "no patterns" message — verified at line 60-65 region | gated |
| 15 | `DriftCore/Sources/DriftCore/AI/Tools/CrossDomainPatternDetectorTool.swift:67` | **tool output** | "\(patterns.count) patterns over the last \(windowDays) days:" | same gate as #14 | gated |
| 16 | `DriftCore/Sources/DriftCore/AI/Tools/GLP1InsightTool.swift:80` | code doc-comment | "at least one dose was logged within the last 7 days" | doc for `hasRecentDose` predicate, not a UI label | non-label |
| 17 | `DriftCore/Sources/DriftCore/AI/Tools/GLP1InsightTool.swift:125` | code doc-comment | "Count completed calendar weeks in the last 30 days with no dose logged." | doc for a count helper | non-label |
| 18 | `DriftCore/Sources/DriftCore/AI/Tools/GLP1InsightTool.swift:168` | **tool output** | "No missed doses in the last 30 days." | reachable only when `weeksMissed == 0`; only emitted when there *is* schedule data to evaluate (early return when no schedule) | gated |
| 19 | `DriftCore/Sources/DriftCore/AI/Tools/GLP1InsightTool.swift:170` | **tool output** | "\(weeksMissed) missed week(s) in the last 30 days." | counts completed weeks with no dose; the `Count completed calendar weeks` helper at line 125 explicitly avoids overstating by ignoring partial weeks | gated |
| 20 | `DriftCore/Sources/DriftCore/AI/Tools/WeightTrendPredictionTool.swift:25` | tool description (LLM-facing) | "confidence based on current trend" | static tool description registered with LLM router; not user-rendered text | non-label |
| 21 | `DriftCore/Sources/DriftCore/AI/Tools/ToolRegistration.swift:899` | code comment | "OLS regression on last 30 days → projected date + R² confidence. #402." | comment on a tool registration | non-label |
| 22 | `DriftCore/Sources/DriftCore/Domain/Workout/ExerciseService.swift:105` | code doc-comment | "Suggest what to train based on recent history." | doc for a helper, not a UI label | non-label |
| 23 | `DriftCore/Sources/DriftCore/Domain/Workout/ExerciseService.swift:390` | code doc-comment | "Body parts trained in the last 7 days." | doc for `bodyPartsTrained` helper; returns empty set when no workouts | non-label |
| 24 | `DriftCore/Sources/DriftCore/Domain/Food/MealTimingService.swift:75` | code doc-comment | "(typically the last 30 days). Returns `nil` when fewer than …" | doc explicitly states the min-sample fallback returns nil | non-label |
| 25 | `DriftCore/Sources/DriftCore/Domain/Food/FoodService.swift:27` | code comment | "Time-of-day boost: re-rank based on meal type" | comment on ranking function | non-label |
| 26 | `DriftCore/Sources/DriftCore/Domain/Health/BehaviorInsightService.swift:49` | code doc-comment | "Alert when protein target missed 3+ consecutive days OR 4+ of last 7 days." | doc — `3+ consecutive OR 4+ of 7` is the explicit threshold | non-label |
| 27 | `DriftCore/Sources/DriftCore/Domain/Health/BehaviorInsightService.swift:95` | code doc-comment | "Pure: given protein stats for the last 7 days, return the alert or nil." | doc, helper returns nil below threshold | non-label |
| 28 | `DriftCore/Sources/DriftCore/Domain/Health/BehaviorInsightService.swift:119` | code doc-comment | "Alert when glucose readings show spikes (>140 mg/dL) on 3+ of the last 7 days." | doc — `3+ of 7` is the explicit threshold | non-label |
| 29 | `DriftCore/Sources/DriftCore/Domain/Health/BehaviorInsightService.swift:146` | **insight string** | "\(spikeDays) of the last 7 days had readings above 140 mg/dL. Ask Drift AI which meals correlate." | only emitted when `spikeDays >= 3`; the `3+ of 7` threshold gates the message | gated |
| 30 | `DriftCore/Sources/DriftCore/Domain/Health/SleepRecoveryService.swift:38` | code doc-comment | "Training readiness based on recovery + sleep." | doc, no UI label | non-label |
| 31 | `DriftCore/Sources/DriftCore/Domain/Weight/WeightTrendCalculator.swift:533` | code comment | "The UI labelling that result 'based on last 21 days' because …" | this comment *describes the bug pattern #801 audits* and the fix shipped in 5a3f6eec — meta-reference, not a current label | n/a |
| 32 | `DriftCore/Sources/DriftCore/Domain/Weight/WeightTrendService.swift:17` | code doc-comment | "True if no weight logged in last 60 days — don't show trends." | doc for `shouldHideTrends` predicate — a min-sample gate itself | non-label |

## Summary

- **8 user-facing label-bearing surfaces** examined (#4, #10, #11, #13, #14, #15, #18, #19, #29). All 8 are **already gated** on the relevant threshold and surface honest fallback affordances when sparse.
- **22 code-comment / doc-comment / tool-description hits** — no UI risk.
- **2 meta-references** (#8, #31) that document the bug pattern itself.
- **0 unfixed surfaces** remain at the time of this audit.

## Tier-0 test hardening shipped in this PR

Eight previously-passing-by-accident tests in `DriftCoreTests/WeightTrendCalculatorTests.swift` and one in `DriftCoreTests/RobustnessTests.swift` were the windowed-calc bug class **inside the test fixtures themselves**: they hardcoded `"2026-03-XX"` dates that rolled outside the 21-day rolling-now regression window after the calculator gained its sparse-data gate. The tests claimed "21 days of data showing a -0.07 kg/day loss" while the math (correctly) saw zero points in window and returned `hasInsufficientData=true`. They asserted `weeklyRate < 0` / `projection30Day != nil` and crashed with force-unwrap on the now-nil projection.

This PR re-anchors those fixtures to rolling-now via the existing `makeEntries(days:startKg:ratePerDay:)` helper (which generates rolling dates ending today) and updates `twoEntriesNoTrendCrash` to assert the *correct* sparse-data contract (`weeklyRateKg == 0` and `hasInsufficientData == true`) rather than the pre-gate assertion (`weeklyRate < 0` from 2-point extrapolation).

## New sparse-data Tier-0 tests (criterion 3)

Three new tests in `DriftCore/Tests/DriftCoreTests/SparseDataInsufficiencyTests.swift`, mirroring the 5a3f6eec regression-test shape:

1. `weightTrendSparseDataInsufficiencyReturnsZero` — two entries close together: assert `weeklyRateKg == 0` AND `hasInsufficientData == true`.
2. `weightTrendInsufficientDataMinSampleGate` — three entries spanning 7 days: fewer than 4 points OR span < 14 days fails the min-sample gate; assert `hasInsufficientData == true`.
3. `weightTrendSparseDataHidesProjection` — sparse data must hide `projection30Day` (nil) so the UI can render "—" not a fabricated number.

## Closing note

The "audit every UI surface" framing is now closed: the actual UI surfaces are already gated. The remaining risk class is **test fixtures that bake in absolute dates** — those silently rot once the rolling-now window leaves them behind. The hardening shipped here converts the offending fixtures to rolling-now and adds explicit sparse-data tests that pin the contract. Future similar audits should grep test fixtures, not just production code.
