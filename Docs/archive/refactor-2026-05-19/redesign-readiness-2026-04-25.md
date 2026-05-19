# Redesign-Readiness Refactor

**Status:** plan only — NOT executed.
**Date authored:** 2026-04-25
**Trigger condition:** before any drastic visual redesign of the iOS app, OR when the design brief is in hand.

## Why this exists

The user wants the option to drastically change the look of the Drift iOS app at some point. This document captures the audit + recommended sequence so the refactor can happen in a focused window when the redesign timing is known, rather than as preemptive churn.

## Current state (audit summary, 2026-04-25)

| Area | Verdict | Why |
|---|---|---|
| **Color theme (`Drift/Theme.swift`)** | Strong | 141 lines, semantic tokens (`deficit`, `surplus`, `cardBackground`, macro colors). Goal-aware coloring centralized. >80% of color references go through `Theme.X`. 0 hex literals leak into Views. |
| **Typography** | Weak | **93 inline `.font(.system(size: N, weight: .X))`** calls across Views with hardcoded sizes 10/11/12/18 etc. Theme has a few font tokens (`fontLargeTitle`, `fontBody`, `fontCaption`, `fontStat`) but they don't cover the actual usage range. |
| **Spacing** | Mixed (~60–70% disciplined) | Theme has `spacingXS`–`spacingXL` (4–28pt). But `FoodTabView.swift` alone has 41 raw `.padding(N)` literals. Other views similar. |
| **Component library** | Almost absent | `Drift/Views/Shared/` has only **2 files** (`MacroRingsView`, `GoalProgressCard`). The 8 confirmation-card variants and ~50 pill/chip/button patterns are inlined per-view. |
| **Dark/light mode** | Forced dark | `.preferredColorScheme(.dark)` at app launch. All colors are `Color(hex: "...")` — no Asset Catalog, no automatic light/dark variants. |
| **Dynamic Type** | Not supported | All font sizes are fixed. No `.scaled(relativeTo:)` use. |
| **Top-level shell** | Clean | `ContentView.swift` is 56 lines, each tab independently rendered. Redesign of the shell itself is contained. |

## Concrete pain points (where a redesign would hurt today)

**5 hardest views to redesign:**

1. `Drift/Views/Food/FoodTabView.swift` (960L) — 41 mixed-magic-number `.padding()` calls; inlined `macroPill`, `recentChip`, `comboChip`, `groupedEntryBlock` styling each repeated 5+ times with bespoke colors and corner radii.
2. `Drift/Views/AI/AIChatView.swift` (885L) — 93 of those `.font(.system(...))` calls live here; inline `messageBubble`, `thinkingIndicator`, `suggestionsRow`.
3. `Drift/Views/AI/AIChatView+MessageHandling.swift` (1399L) — largest file in the iOS target; bespoke message rendering.
4. `Drift/Views/Workout/ActiveWorkoutView.swift` (762L) — timer/countdown UI with custom drawing and animation state.
5. `Drift/Views/Food/FoodSearchView.swift` (811L) — list rows + category headers + filter chips, all inlined.

**5 easy views (already disciplined, leave alone):**

1. `Drift/Views/AI/TypingDotsView.swift` (28L) — pure `Theme.accent` use, simple animation.
2. `Drift/Views/Shared/MacroRingsView.swift` (59L) — Theme-driven, parameterized.
3. `Drift/Views/Shared/GoalProgressCard.swift` (94L) — uses `.card()` modifier + Theme tokens.
4. `Drift/Views/Weight/WeightChartView.swift` (121L) — Charts framework, Theme-colored.
5. `Drift/Views/Settings/GoalSetupView.swift` — wizard with consistent token use.

## Refactor sequence (ordered by ROI)

Sequence matters: do **#2 → #3 → #4** before **#1** so the extracted components consume tokenized fonts/spacing instead of literals.

### #2. Typography scale tokens — `~2h`

**Goal:** eliminate ~85% of font drift. Make a redesign of typography a Theme-only change.

**Plan:**
1. Read all 93 `.font(.system(size: N, weight: W, design: D))` call sites in `Drift/Views/`. Bucket them by (size, weight) pairs. Expect ~8–12 distinct buckets.
2. Add tokens to `Theme.swift` for each bucket. Suggested names: `fontLabel` (size 11), `fontCaption` (size 12), `fontMetric` (size 10, monospaced), `fontSubheading` (size 13 semibold), `fontTitle` (size 18 bold), etc.
3. Mechanical sweep: for each bucket, perl/sed-replace the literal call with the new token across all view files.
4. Build + run UI smoke check (open each tab, look for visual regressions).

**Critical files:** `Drift/Theme.swift` (additions), all 56 files under `Drift/Views/` (call-site updates).

### #3. Spacing token sweep — `~3h`

**Goal:** make a spacing redesign a Theme-only change.

**Plan:**
1. Inventory all `.padding(N)` and `.padding(.horizontal, N)` / `.padding(.vertical, N)` calls with literal numeric values across `Drift/Views/`.
2. Map to existing `Theme.spacingXS/SM/MD/LG/XL` tokens. For values that don't fit (e.g., `.padding(10)` falls between SM=8 and MD=14), either add a new token (`spacingCompact = 10`) or pick the nearest.
3. Sweep call sites.
4. Visual regression check.

**Caveat:** some paddings are intentionally bespoke (e.g., a button needs exactly 12pt for icon alignment). Keep a "raw OK" allow-list for those — don't fight a real design constraint to fit a token.

**Critical files:** `Drift/Theme.swift` (potential new tokens), all view files with literal padding.

### #4. Goal-aware coloring helper — `~30min`

**Goal:** centralize the `is this value aligned with the goal direction?` ternary scattered across views.

**Plan:**
1. Find existing `isGoalAligned(_:)` in `Drift/Views/Dashboard/DashboardView+Cards.swift`. Promote it to `Theme.goalColor(_ value: Double, against direction: GoalDirection) -> Color`.
2. Sweep all `(deficit < 0 ? Theme.deficit : Theme.surplus)` -style branches and replace with the helper call.

**Critical files:** `Drift/Theme.swift`, `Drift/Views/Dashboard/DashboardView+Cards.swift`, scattered call sites in Weight/Food/Dashboard views.

### #1. Component library extraction — `~6h`

**Goal:** reduce a redesign from "edit 50 view files" to "edit 10 components."

**Plan:**
1. Survey: list every `pill`, `chip`, `card`, `button`, `sectionHeader`, `tabBarItem`, `confirmationCard` pattern across views. Catalog the variants.
2. Decide a small base set:
   - `DriftButton(label, style, size)` — primary/secondary/ghost variants
   - `MacroPill(label, value, color)` — consolidates `macroPill`, `recentChip`, `comboChip`
   - `Card { content }` — consolidates the 8 confirmation card variants by accepting domain-specific content
   - `SectionHeader(title, trailing)` — for list section dividers
3. Extract to `Drift/Views/Shared/Components/`.
4. Migrate views one tab at a time (Food → Weight → Dashboard → AI → Settings). Each migration is a separate commit.
5. Visual regression check per tab.

**Caveat:** **DO NOT do this preemptively.** Premature component libraries get the API wrong. Start this when you have the design brief in hand — extract components shaped by what the new design needs, not what today's UI happens to do.

**Critical files:** `Drift/Views/Shared/Components/*.swift` (new), every view file (per-tab migration).

### #5. Asset Catalog migration — `~4h` *(only if light mode is ever wanted)*

**Goal:** unlock light/dark variants without code changes.

**Plan:**
1. For each `Color(hex: "...")` in `Theme.swift`, create a named color in `Drift/Resources/Assets.xcassets` with `Any Appearance` (current dark hex) AND `Light Appearance` (a TBD light variant — design work, not code work).
2. Replace each `Color(hex: "...")` with `Color("ColorName", bundle: .main)`.
3. Drop `.preferredColorScheme(.dark)` from `DriftApp` so the app respects system preference.

**Caveat:** light-mode hex values are a *design* deliverable, not a code one. This refactor's code part is mechanical (~1h), but the design part is the real work.

**Critical files:** `Drift/Theme.swift`, `Drift/Resources/Assets.xcassets/` (new color sets), `Drift/DriftApp.swift`.

### #6. Dynamic Type support — `~3h` *(accessibility, not redesign-blocking)*

**Goal:** font sizes scale with the user's system text-size setting.

**Plan:**
1. After #2 (typography tokens), add `.scaled(relativeTo: .body)` or use `Font.TextStyle`-relative sizes in each token.
2. Add `@Environment(\.sizeCategory)` checks in views with custom layouts that break at large sizes.

**Critical files:** `Drift/Theme.swift`, view files with strict layouts.

## Recommended timing decision

| If redesign is happening in… | Do these refactors |
|---|---|
| **<1 month** | #2 + #3 + #4 only (~6h). Skip #1 — let the design brief shape the components. Skip #5/#6 — defer. |
| **3+ months** | #2 + #3 + #4 now (low effort, pay-it-forward). #1 once design brief is in hand. #5 if light mode is on the roadmap. |
| **Uncertain timing** | #2 + #3 + #4 only. Code is strictly better even if no redesign ever happens. |

**My bet:** #2 + #3 + #4 ≈ ~6 hours, mechanical, low-risk. Defer #1 until design-led. Defer #5/#6 until light mode or a11y becomes a real ask.

## Out of scope

- **Premature component extraction.** Tempting but wrong-shaped without a design brief.
- **Custom drawing replacement.** `ActiveWorkoutView` and chart views are bespoke for a reason; redesign them in the design pass, not as prep.
- **Full Asset Catalog now.** Only do this if light mode is wanted. Dark-only is fine.
- **Removing `.preferredColorScheme(.dark)`.** Coupled to #5 — don't do alone.
- **Refactoring `AIChatView+MessageHandling.swift` (1399L)** — largest file but tightly coupled to AI pipeline; redesign should treat the message bubble as an opaque component.

## Verification (when this lands)

After each refactor item:
- `xcodebuild build -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — must succeed
- `pkill -9 -f xcodebuild; sleep 2; xcodebuild test ... -only-testing:DriftTests` — 1211 tests must still pass
- **Visual smoke**: open each tab in the simulator, compare to baseline screenshots. The audit's "5 hardest views" are the ones to scrutinize most.
- For #2 (typography): grep should show 0 remaining `.font(.system(size:` literal-numeric calls in `Drift/Views/`.
- For #3 (spacing): grep should show ~0 remaining literal-numeric `.padding(N)` calls (or only allow-listed ones).

## Companion files

- `Drift/Theme.swift` — single source of truth for tokens. Most refactors add to this file.
- `Drift/Views/Shared/` — destination for #1 component library.
- `Drift/Resources/Assets.xcassets/` — destination for #5 Asset Catalog colors.
