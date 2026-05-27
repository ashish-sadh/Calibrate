# Design #848: V7 Phase 3 — Body Screen Unification

> References: Issue #848 · Parent epic #856 · Roadmap: V7 Phase 3
> State: pending review · Personas: principal-engineer · product-designer

## Problem

V7 collapsed the V6 five-tab IA (Drift / Weight / Food / Exercise / More) to four primary tabs (Today / Food / Body / More). The Today tab and the Food tab were rewritten in Phases 1 + 2 (TodayDonutView, log-method row, BodySummaryCardsRow on Today, FoodTabView). The Body tab, however, is still a V7-shaped shell wrapping the V6 `WeightTabView` verbatim — see `Drift/ContentView.swift:138`:

```swift
WeightTabView(syncComplete: $syncComplete, selectedTab: selectedTabBindingLegacy)
    .tag(PrimaryTab.body)
```

This means the user lands on a screen labeled "Body" in the pill tab bar but sees only a weight chart + weight insights + weight log. Glucose, biomarkers, body composition, and rhythm (sleep/recovery/HRV) all live in unrelated places:

- **Glucose** → reachable only via the More → Glucose deep link (`GlucoseTabView`).
- **Biomarkers** → reachable only via More → Biomarkers (`BiomarkersTabView`).
- **Body composition** (body fat %, lean mass, fat mass, water %, BMI) → reachable only by tapping "Add body composition" inside the `WeightEntryView` sheet that opens from the Weight tab toolbar. There is no read-only surface for the latest body composition values at all.
- **Rhythm** (sleep hours, recovery score, HRV, RHR, respiratory rate) → reachable only via the Today tab's "Sleep & Recovery" card which navigates into `SleepRecoveryView`.

The V7 mocks ship a single scrolling Body screen that surfaces all five domains in one place — chart-hero + supporting cards — so the user can read their body state without bouncing between three top-level tabs and one sheet. This phase replaces `WeightTabView`'s `.tag(PrimaryTab.body)` slot with a new unified `BodyTabView`.

The cost of the current split is not theoretical: BodySummaryCardsRow (V7 Phase 2, `Drift/Views/BodySummaryCardsRow.swift`) renders WEIGHT/SLEEP/READINESS cards on Today whose `onTapBody` callback navigates to the Body tab — but the destination is just a weight screen, so the SLEEP and READINESS taps land somewhere that doesn't show their data. Phase 2 shipped the activation surface assuming Phase 3 would land in the same arc; this design closes that gap.

## IA

The unified Body screen organizes five domains by **read-frequency × data-density**:

| Section | Domain | Why this position |
|---|---|---|
| 1. Weight hero | Weight | Highest read-frequency; the existing `WeightChartView` is the most-polished chart we ship and is what users open the tab for. |
| 2. Rhythm strip | Sleep / Recovery / HRV / RHR / RR | Read-daily, low-density (3-5 numbers). Sits directly under weight so the "how am I doing today" glance is satisfied in the first scroll-position. |
| 3. Glucose chart | Glucose | Read-weekly for CGM users, dormant for non-CGM. Collapsible header — expands to the full chart + stats only on tap to keep non-CGM users from scrolling past dead space. |
| 4. Body composition row | Body fat / Lean mass / Fat mass | Read-monthly. Single-row of 3 stat pills + tap-to-log. |
| 5. Biomarkers donut + recent | Biomarkers (lab reports) | Read-quarterly. Donut summary + most-recent report row; full search/filter list moves under a "See all biomarkers" link to a dedicated detail screen rather than living in the scroll. |

Coach insights surface as a **floating insight card** between the Weight hero and the Rhythm strip when there is something worth surfacing — weekly weight rate vs goal, a glucose spike pattern, an out-of-range biomarker. The insight card is opt-in to render (no card if no insight) so it doesn't become visual debt on a sparse day.

The navigation-bar toolbar collapses the five V6 toolbars (each tab had its own primary action) into:
- Leading: none (no back button — Body is a primary tab).
- Trailing: `+` menu with three actions — "Log weight", "Log body composition", "Upload lab report". Glucose import lives behind `BodyTabView → Glucose section → "···" menu` since it's a power-user CSV path.

## Scroll layout

```
┌─────────────────────────────────────────┐
│ NAV BAR: "Body"           [+] menu      │
├─────────────────────────────────────────┤
│ ┌── Weight hero card ──────────────────┐│  ← always visible (hero)
│ │  Time range bar  D/W  flame-toggle   ││
│ │  ╭─────────────────────────────────╮ ││
│ │  │   WeightChartView (260pt)       │ ││
│ │  ╰─────────────────────────────────╯ ││
│ │  WeightInsightsView (cards row)      ││
│ └──────────────────────────────────────┘│
│                                         │
│ ┌── Coach insight (conditional) ───────┐│  ← only when insight present
│ │  💡 "You're on track to hit goal…"   ││
│ └──────────────────────────────────────┘│
│                                         │
│ ┌── Rhythm strip ──────────────────────┐│  ← always visible (read-daily)
│ │  Recovery score • Sleep h • HRV ms   ││
│ │  RHR bpm • RR rpm                    ││
│ └──────────────────────────────────────┘│
│                                         │
│ ┌── Glucose section ───────────────────┐│  ← collapsed-by-default if no
│ │  ▸ Glucose      (last 24h: 98 avg)   ││     readings in last 7d; else
│ │  [expanded: chart + zones + stats]   ││     expanded
│ └──────────────────────────────────────┘│
│                                         │
│ ┌── Body composition row ──────────────┐│  ← always visible
│ │  Body Fat 18.2%  Lean 138 lb  Fat 30││
│ │              [Log composition →]     ││
│ └──────────────────────────────────────┘│
│                                         │
│ ┌── Biomarkers ────────────────────────┐│  ← always visible (donut only;
│ │  ◯ Donut (3 zones)                   ││     full list is a push-nav)
│ │  Last report: 2026-04-12 · 24 markers││
│ │              [See all biomarkers →]  ││
│ └──────────────────────────────────────┘│
│                                         │
│       (78pt safe-area inset)            │
└─────────────────────────────────────────┘
       ⬜ PillTabBar  💬 ChatIcon
```

Spacing tokens follow V7 Phase 2: 14pt between cards, 16pt horizontal padding, 8pt top inset under the nav bar, 24pt bottom inset before the safe-area inset. Card corner radius 14pt + 0.5pt `Theme.separator` stroke on `Theme.cardBackground`. Hero section dispenses with the card wrapper so the chart visually breathes — this matches the Today donut hero treatment from Phase 2.

Empty states (no weight entries yet, no glucose readings, no lab reports, no body composition) collapse the corresponding card to a single nudge row (one-line copy + CTA). The full screen never renders blank — at least the empty-state nudge keeps the IA pinned so the user learns where each domain lives.

## V6 carry-over

Explicit list of every V6 view/component touched, with the survives-vs-rewrite verdict and the file it lives in (so impl tasks can be filed surgically):

| V6 component | File | Verdict | Notes |
|---|---|---|---|
| `WeightTabView` | `Drift/Views/Weight/WeightTabView.swift` | **Replace** | The whole view is replaced by `BodyTabView`. Routing in `ContentView.swift:138` flips. |
| `WeightChartView` | `Drift/Views/Weight/WeightChartView.swift` | **Carry over** | Hero chart. Reused as-is. |
| `WeightInsightsView` | `Drift/Views/Weight/WeightInsightsView.swift` | **Carry over** | Insights cards row. Reused under the hero chart. |
| `WeightLogListView` | `Drift/Views/Weight/WeightLogListView.swift` | **Move** | Collapsible log moves from `WeightTabView`'s `logSection` into a "Log history" disclosure inside the new Weight hero's bottom. |
| `WeightEntryView` (sheet) | `Drift/Views/Weight/WeightEntryView.swift` | **Carry over** | Add-weight + add-body-comp sheet reused unchanged. Triggered from the new `+` menu. |
| `bigChangeBanner` | inline in `WeightTabView.swift:181-220` | **Extract + carry over** | Pulled into its own view file `WeightBigChangeBanner.swift` so the new BodyTabView can host it without copying the inline closure. |
| `timeRangeBar` | inline in `WeightTabView.swift:224-280` | **Extract + carry over** | Pulled into `WeightTimeRangeBar.swift`. Owned by the Weight hero section. |
| `GlucoseTabView` | `Drift/Views/Glucose/GlucoseTabView.swift` | **Split** | `body` becomes `GlucoseSection.swift` (chart + stats + fasting + spikes/dips, no toolbar/nav). The CSV import sheet trigger moves into the section's `···` menu. The standalone tab entry under More is retired once Body is the canonical home. |
| `glucoseChart` (private) | inline in `GlucoseTabView.swift:118-208` | **Extract** | Becomes its own `GlucoseChartView.swift` so the Body section can compose it without duplicating the spike/dip detection wiring. |
| Spike/dip detection (`detectEvents`, `detectEventIndices`) | inline in `GlucoseTabView.swift:258-300` | **Move to DriftCore** | Pure logic, no SwiftUI — belongs in `DriftCore/Sources/DriftCore/Domain/Glucose/GlucoseEventDetector.swift`. Tier-0 testable independently of the view. This was a `WeightInsightsView` discipline; we owe it to glucose too. |
| `BiomarkersTabView` | `Drift/Views/Biomarkers/BiomarkersTabView.swift` | **Split** | `donutSummary` + most-recent `reportsList[0]` becomes `BiomarkersSummarySection.swift` for the Body screen. The full `searchBar` + `filterChips` + `biomarkerList` move to a pushed `BiomarkersListView.swift` reached via the "See all biomarkers" link. |
| `DonutRing` | inline in `BiomarkersTabView.swift:310-342` | **Extract + carry over** | Pulled into its own view file `BiomarkerDonutRing.swift`. Used by the new summary section. |
| `BiomarkerRow` | inline in `BiomarkersTabView.swift:346-410` | **Carry over** | Used inside the pushed `BiomarkersListView`. |
| `RangeBar` | inline in `BiomarkersTabView.swift:414-456` | **Carry over** | Used by `BiomarkerRow`, transitively reused. |
| `BodyCompEntryView` | `Drift/Views/Weight/BodyCompEntryView.swift` | **Carry over** | Sheet for logging body composition. Triggered from the new `+` menu and from the body composition row's "Log composition →" CTA. |
| `BodySummaryCardsRow` | `Drift/Views/BodySummaryCardsRow.swift` | **No change to file** | Phase 2 component on Today tab. Its `onTapBody` callback gets a new and better destination (the unified Body screen) — no code change needed, just a working endpoint. |
| `SleepRecoveryView` | `Drift/Views/Dashboard/SleepRecoveryView.swift` | **Re-host** | Becomes `RhythmSection.swift` inside the Body screen. The Today-card → SleepRecovery navigation link is removed (replaced by the Today → Body tab navigation that BodySummaryCardsRow already does). |
| `RecoveryEstimator.DailyRecovery` (model) | `DriftCore/Sources/DriftCore/Domain/Health/RecoveryEstimator.swift` | **No change** | Already in DriftCore. Rhythm section consumes it. |
| `WeightViewModel` | `Drift/ViewModels/WeightViewModel.swift` | **Reused** | Hero section binds to it; no changes required. |
| `MoreTabView` Glucose + Biomarkers rows | `Drift/Views/Settings/MoreTabView.swift` | **Remove** | Once Body is the canonical home for both, the More tab's Glucose and Biomarkers rows go away. CSV import for glucose stays reachable via the `···` menu inside the Body screen's Glucose section. |
| `WeightTabView` empty state | inline in `WeightTabView.swift:323-365` | **Replace** | The new Body screen's empty state is multi-domain: shows nudge rows for the domains that have no data ("Log your first weigh-in", "Connect Apple Health for glucose", "Upload a lab report"). Not the full-screen single-domain empty state V6 had. |

## Test-debt

Per-file enumeration of every test that touches the rewritten/carried-over surface. The discipline (per the prior `principal-engineer` debate-fix on this design): test-debt cost is invisible unless we enumerate it.

### Tier-0 (DriftCore) — pure logic, all survive unchanged

| Test file | Coverage | Verdict |
|---|---|---|
| `DriftCore/Tests/DriftCoreTests/WeightServiceAPITests.swift` | Weight CRUD, latestBodyComposition | **Survives** — pure service API unchanged. |
| `DriftCore/Tests/DriftCoreTests/WeightTrendCalculatorTests.swift` | EMA, weekly rate, trend prediction | **Survives** — unchanged. WeightInsightsView consumer carries over. |
| `DriftCore/Tests/DriftCoreTests/WeightTrendPredictionTests.swift` | Goal-date prediction | **Survives** — unchanged. |
| `DriftCore/Tests/DriftCoreTests/WeightChartCaloriesPreferenceTests.swift` | Calories overlay preference persistence | **Survives** — toggle still lives in the carried-over time-range bar. |
| `DriftCore/Tests/DriftCoreTests/GlucoseAnalyticsServiceTests.swift` | Glucose service queries | **Survives** — service unchanged. |
| `DriftCore/Tests/DriftCoreTests/GlucoseFoodCorrelationToolTests.swift` | Analytical tool | **Survives** — pipeline unchanged. |
| `DriftCore/Tests/DriftCoreTests/GlucoseSpikeAlertTests.swift` | Spike alert detection | **Survives** — pure logic in `DriftCore` already. |

### Tier-0 (DriftCore) — new files this phase will add

| New test file | Covers | Why tier-0 |
|---|---|---|
| `DriftCore/Tests/DriftCoreTests/GlucoseEventDetectorTests.swift` | The spike/dip detection lifted out of `GlucoseTabView.detectEventIndices` | Pure logic; no SwiftUI. Currently un-tested because it was inline in a view. |
| `DriftCore/Tests/DriftCoreTests/BodyScreenSectionVisibilityTests.swift` | Section visibility rules (glucose collapsed if no readings ≤7d, biomarker section hidden if 0 reports, etc.) | Pure logic on a `BodyScreenSectionPolicy` struct that the view consumes. |

### Tier-1 (iOS) — survive, but routing changes

| Test file | Verdict |
|---|---|
| `DriftTests/BodySummaryCardsRowTests.swift` | **Survives** — the row's own behavior is unchanged. The `onTapBody` destination is just better. Test asserts the row, not the destination, so no rewrite needed. |

### Tier-1 (iOS) — to rewrite

| Old file | New replacement | Reason |
|---|---|---|
| (none — `WeightTabView` had no iOS-tier tests; charts/insights are tested in DriftCore where pure logic lives) | `DriftTests/BodyTabViewTests.swift` | Asserts section ordering (Weight hero before Rhythm before Glucose before BodyComp before Biomarkers), `+` menu actions present, empty-state nudges render when data missing. |

### Tier-3 (LLM eval) — unchanged

No LLM pipeline touches this UI. The `weight_trend_prediction`, `glucose_food_correlation`, and biomarker query tools all continue to route to the same backing services. The UI rewrite is presentation-only.

### Test-debt summary

- **0 tier-0 tests deleted**, **2 new tier-0 files added** (`GlucoseEventDetectorTests`, `BodyScreenSectionVisibilityTests`).
- **0 tier-1 tests deleted**, **1 new tier-1 file added** (`BodyTabViewTests`).
- **Net delta**: +3 test files, ~30-50 cases. Estimated +1-2s tier-0 wall time.

## Open questions

Pre-mortem hooks for principal-engineer and product-designer. These are explicit prompts the design-doc PR review should answer before impl tasks are filed.

### For principal-engineer:

1. **Splitting `GlucoseTabView` and `BiomarkersTabView` vs reusing them whole.** The current proposal extracts sections (`GlucoseSection`, `BiomarkersSummarySection`). The alternative is composing the existing tab views inside the new Body scroll. Trade-off: extraction is more code but yields a cleaner Body composition + lets us drop the More-tab entries; reuse is faster but ships a "tab inside a tab" anti-pattern. **Recommendation in this doc: extract.** principal-engineer to confirm or push back.
2. **Where does `RhythmSection` live?** `SleepRecoveryView` is in `Drift/Views/Dashboard/` because it was a Today-tab card destination. Moving it to `Drift/Views/Body/RhythmSection.swift` is the directory-honest move, but it leaves the Today-side `SleepRecoveryView` navigation orphaned (currently a `NavigationLink` from the Dashboard's recovery card). Open: do we delete the Dashboard link entirely (Body tab is the only entry point), or keep both with the same view? principal-engineer's call — orphan-paths-vs-duplicate-entry-points framing.
3. **Section visibility policy in `DriftCore` or in the view?** This doc proposes a `BodyScreenSectionPolicy` struct in `DriftCore` so the rules are tier-0 testable. principal-engineer to weigh: is the indirection worth the test coverage, or is `if entries.isEmpty { collapsed }` in the view fine?
4. **`MoreTabView` row removal in the same PR or a follow-up?** Removing the Glucose + Biomarkers rows from MoreTabView in the same commit as adding the Body screen avoids a stale-link window; doing it as a follow-up keeps the diff smaller. principal-engineer's diff-discipline call.

### For product-designer:

1. **Hero ordering: weight vs rhythm.** This doc puts the weight chart first (highest read-frequency, polished chart). product-designer: should the Rhythm strip (sleep + recovery + HRV) be the hero instead, since "how am I today" is a more urgent question than "how am I trending this month"? Mock-driven answer preferred.
2. **Coach insight card placement.** Currently designed as a floating card between Weight hero and Rhythm strip, rendered only when an insight exists. product-designer: is the conditional render acceptable, or should the slot be reserved (with a "Nothing new today" placeholder) so users don't perceive layout shift when an insight appears?
3. **Glucose-section default state for non-CGM users.** Proposal: collapsed if no readings in last 7 days, expanded otherwise. Alternative: hidden entirely if no readings ever, with a "Connect glucose data" nudge row. product-designer: which empty-state strategy matches the V7 "always show the IA, even when empty" tenet?
4. **Biomarkers donut on the main screen, list pushed to detail.** Trade-off: keeping the full searchable biomarker list on the Body scroll matches V6 behavior (no extra tap) but bloats the screen for users who check biomarkers quarterly. The push-nav saves screen real estate but adds a tap to a power-user surface. product-designer to confirm the push-nav choice.
5. **`+` menu vs three separate FAB shortcuts.** The V7 IA has a single `+` FAB on Today (Snap-first photo log). The proposal here is a nav-bar `+` menu inside the Body screen with three actions (Log weight / Log composition / Upload lab report). product-designer: is the nav-bar menu the right surface, or should body-logging follow the Today-screen pattern with a chip row at the top of the scroll (similar to Today's log-method chips)?

## Considered alternatives

Documented so future re-reads of this design can see the road-not-taken:

- **Keep Body = Weight only.** Rejected: BodySummaryCardsRow already promises SLEEP and READINESS land on the Body tab; the SLEEP and READINESS cards on Today are dead taps until Phase 3 lands.
- **Replace the Body tab with a "Health" tab that includes nutrition/exercise summaries too.** Rejected as out-of-scope: Today already aggregates nutrition + activity. Body is specifically the *physical-state* surface (mass, composition, internal signals).
- **Three sub-tabs inside Body (Weight / Glucose / Biomarkers).** Rejected: re-introduces the V6 fragmentation we're explicitly collapsing. The V7 thesis is one-scroll-screens, not nested tab navigation.

## Implementation plan (impl tasks to be filed by /planning step 5 once approved)

These are non-binding sketches; planning will scope the actual `<done_when>` blocks when it files the design-impl-848-{N} sprint-tasks.

1. **design-impl-848-1: Extract V6 inline components into reusable views.** Pull `bigChangeBanner`, `timeRangeBar`, `glucoseChart`, `DonutRing` into their own files (no behavior change). Verifies: existing tier-0 + tier-1 tests still pass.
2. **design-impl-848-2: Move `detectEvents`/`detectEventIndices` to DriftCore.** New `GlucoseEventDetector.swift` + `GlucoseEventDetectorTests.swift`. Verifies: tier-0 spike-detection test cases pass with current `GlucoseTabView` rendering unchanged (using the new module).
3. **design-impl-848-3: `BodyScreenSectionPolicy` in DriftCore.** Pure-logic struct + tier-0 tests for section visibility rules.
4. **design-impl-848-4: New `BodyTabView` + section views.** `Drift/Views/Body/{BodyTabView,WeightHeroSection,RhythmSection,GlucoseSection,BodyCompositionRow,BiomarkersSummarySection}.swift`. Flip `ContentView.swift:138` from `WeightTabView` to `BodyTabView`. Add `DriftTests/BodyTabViewTests.swift`.
5. **design-impl-848-5: Retire `MoreTabView` Glucose + Biomarkers rows + Dashboard SleepRecovery navigation.** Remove the now-duplicate entry points.
6. **design-impl-848-6: Delete `WeightTabView.swift` once `BodyTabView` is the canonical owner.** Tenet 8 (no backwards-compat shims) — change the code, delete the old.

Each impl task is sized to ≤3 files touched + 1 test added, matching the senior context-budget discipline.

---

*To approve: comment with KEEP/DROP/ADD on each Open Question, then add the `approved` label. /planning step 5 will file the design-impl-848-{N} sprint-tasks in the next cycle.*
