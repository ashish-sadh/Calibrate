# Design: UX & Theme Redesign — Alternatives-First

> References: Issue #250

## Problem

Feedback from the owner: "The current theme is really boring." This matches our own self-review from the last two product reviews — the palette works but doesn't earn delight. Users see the dark-plus-violet look once and never come back with "wow this is beautiful." For a local-first, privacy-first app competing against MyFitnessPal and Whoop on vibes, a utility-grade theme is a competitive liability.

**Concrete symptoms:**
- The accent (#8B7CF6) is fine but doesn't sing — it's a safe, generic "SaaS violet."
- Card surface (#1A1B24) and background (#0E0E12) are too close in value; cards don't pop, chart rings don't punch.
- Macro ring colors (#3B82F6 blue / #EF4444 red / #22C55E green / #EAB308 yellow) are the default Tailwind palette — readable but unbranded.
- Typography uses `.rounded` for titles and `.default` for body — inconsistent vibe ("friendly" vs "neutral") in the same view.
- No motion language. Every state change is an instant swap. Whoop and Strava earn their feel largely through micro-motion.
- No signature moment. Users can't describe what Drift "feels like" in one sentence.

**The brief also asks for a process, not just a palette.** The owner wants alternatives generated (using Claude-with-design tooling) and **approval before any alternative is applied**. That shapes this doc: it's half product direction, half process/guardrails.

## Proposal

This design doc proposes a **two-stage process** rather than a final palette:

**Stage 1 — Generate three theme alternatives** as static design artifacts (screenshots and palette specs), reviewed before any code changes. Each alternative is a coherent *brand direction*, not a color swap:

- **A. "Clinical Warmth"** — inspired by Oura/Eight Sleep. Cream-on-ink, single warm accent, serif headlines, generous negative space. Feels like a wellness journal.
- **B. "Performance Graphite"** — inspired by Whoop/Strava. True-black base, saturated signature accent (electric lime or cyan), condensed display font for stats. Feels like a dashboard for athletes.
- **C. "Ambient Gradient"** — inspired by Linear/Arc/Raycast. Subtle animated gradient backgrounds that shift by meal period and time of day, translucent glass cards, soft-neon accent. Feels like a modern AI product.

**Stage 2 — After the owner picks a direction**, we land it in three bounded PRs (palette + typography → cards/rings → motion/signature moments). Each PR behind a compile-time theme flag so we can A/B against the current look until sign-off.

**Scope in:**
- Three complete theme alternatives, including palette tokens, typography pairings, chart colors, one hero screen mock per alternative (dashboard), and a one-paragraph rationale.
- After selection: concrete file list for adoption, gated rollout.
- Motion language (durations, easing, what animates) — a one-page spec.

**Scope out:**
- Icon system redesign (SF Symbols stay).
- Onboarding flow redesign.
- New information architecture (tabs stay where they are).
- Light mode — still dark-first. A light mode is its own design doc.
- Marketing site / App Store screenshots — downstream, not in this doc.

## UX Flow

### Stage 1 — Alternatives Review (no code)

```
Owner: "/generate theme alternatives"
Claude: produces 3 mock dashboards (A / B / C), each with:
  - Palette swatches (background, card, card-elevated, accent, semantic, macro)
  - Typography pair (display + body + monospaced-digit for stats)
  - Sample dashboard screenshot (existing component tree, new skin)
  - One-paragraph "what it feels like"
Owner: reviews, picks one (or mixes — "A's palette, B's typography")
Outcome: single direction locked into Stage 2 plan.
```

### Stage 2 — Adoption (three PRs)

```
PR-1: Tokens & typography
  - Theme.swift color overhaul
  - New Font helpers (display, body, stat)
  - Compile flag `DRIFT_NEW_THEME`, off by default
  - Screenshot tests updated with new palette snapshots

PR-2: Cards, rings, charts
  - CardStyle revisit (shadow, stroke, radius)
  - MacroRing color update
  - Chart axis/grid colors
  - Any view that hardcoded a color (should be zero after DDD refactor — audit and fix)

PR-3: Motion & signature moments
  - List entry animations (Theme.animationStandard)
  - Ring-fill animation on dashboard open
  - Chat "thinking" spinner visual upgrade
  - Meal-period background wash (if Alternative C)
```

Behind `DRIFT_NEW_THEME`, off by default until the owner flips it with visual QA on-device. Then the flag is removed in PR-4.

### Example: Alternative A ("Clinical Warmth") palette draft

```
Background      #0B0A08  (warm near-black, no blue)
Card            #1C1915  (warm dark, 2-stop separation from bg)
Card-elevated   #2A2620
Separator       white @ 6%

Accent          #D4A574  (warm tan — the signature)
Accent-secondary #E8C497 (light tan for hover/active)

Positive (goal) #7FB069  (muted sage, not fluorescent)
Negative (off)  #C06C64  (terracotta, not hex-red)

Macro-calories  #B89968  (gold)
Macro-protein   #C06C64  (terracotta)
Macro-carbs     #7FB069  (sage)
Macro-fat       #E8C497  (cream)
Macro-fiber     #8B7355  (bark)

Text-primary    #F5EFE6  (cream on ink)
Text-secondary  rgba(F5EFE6, 0.55)
Text-tertiary   rgba(F5EFE6, 0.30)

Typography
  Display    New York Medium, 28pt  (iOS built-in serif)
  Body       SF Pro Text,   15pt
  Stat       SF Mono,       22pt bold
```

Alternatives B and C get comparable palette specs in the generated artifact — not expanded inline here to keep this doc focused on process.

## Technical Approach

**Theme.swift stays the single source.** All current hardcoded hex values already route through `Theme.*`; the DDD refactor that finished last quarter eliminated most outliers. We audit once more before PR-1 — any stragglers are fixed in that PR, not in a separate sweep.

**Compile flag, not runtime toggle.** We don't want two themes shipped to TestFlight — that doubles the surface area. The flag is local: `#if DRIFT_NEW_THEME` gates the new tokens; old tokens stay until PR-4 deletes them.

**Dual-model interaction:** none. This is a presentation change. AI pipeline (SmolLM + Gemma) is untouched. No eval changes expected. If any chat card's hardcoded color breaks — that's a bug to fix in PR-2.

**Motion budget:**
- All animations ≤250ms.
- Respect `UIAccessibility.isReduceMotionEnabled` — fall back to instant swap.
- No continuous animations on always-visible surfaces (battery cost, attention cost).
- One signature moment per session — ring fill on dashboard open, nothing more.

**Typography:**
- Must support Dynamic Type. Any new font pair is defined via `Font.system(.title, design: ...)` with a size-class-aware fallback or via `UIFontMetrics.default.scaledFont(for:)` if we use a custom font.
- Fixed-size fonts only for stats (where number width matters). Monospaced digits are non-negotiable for the rings.

**Performance:**
- No new image assets for a gradient background — use `LinearGradient` / `MeshGradient` (iOS 18+) in SwiftUI.
- Ring animation runs on the GPU via `.animation(_:value:)`, not a timer.
- Any glass/blur effect measured on iPhone 12 before merge (60fps floor).

**Files expected to change (final list locked in Stage 2):**
- `Drift/Utilities/Theme.swift` — all color/typography tokens
- `Drift/Utilities/Theme+Motion.swift` — new file for animation constants
- `Drift/Views/Dashboard/*` — ring, hero card
- `Drift/Views/Chat/*` — message bubbles, avatar
- `Drift/Views/Food/*` — meal cards
- Snapshot tests if they exist (otherwise we eyeball on-device; UI snapshot tests are a separate backlog item)

## Edge Cases

- **Colorblind users** — Any palette we pick must pass a two-color distinguishability test for macro rings (don't rely on red-vs-green alone). Score color helper already uses a gradient, not a binary color — keep that pattern.
- **OLED burn-in** — True black + high-contrast accent is fine; it's static gradients over hours that risk burn-in. The ambient gradient (Alternative C) must not hold the same gradient for >5 minutes; shift by meal period mitigates this.
- **Dynamic Type at XXL / accessibility sizes** — Test the dashboard with largest accessibility size. Stats card must not truncate.
- **Reduce Motion on** — All signature motion becomes fades or instant swaps. Don't silently disable the animation; have an explicit branch.
- **Reduce Transparency on** — Alternative C's glass cards become solid. Design requires a fallback solid color per alternative, chosen at spec time.
- **High Contrast mode** — Increase separator opacity and stroke widths. Token layer must have a `highContrast` variant or we route through system semantic colors.
- **Chat card color references** — Several chat confirmation cards have their own accent use (food logged, weight logged, workout logged). Each gets reviewed in PR-2; no card keeps a hardcoded color.
- **Dark-only app** — We're not introducing light mode here. If the OS is in light mode, we still render dark (intentional). A light mode gets its own doc.
- **TestFlight users with muscle memory** — The flip from old to new is a noticeable change. Plan a brief in-app "what's new" toast on first launch after the flag goes on.

## Open Questions

1. **Do we use a custom font, or stay on system fonts?** Custom gives identity, costs ~400 KB, and adds license friction. System fonts (New York for serif, SF Pro for sans, SF Mono for digits) cover every alternative cheaply. **Recommend:** system fonts unless the owner sees a specific custom font they want in the alternatives.
2. **Should Alternative C's ambient gradient shift by data state (e.g., green tint when goal met)?** Cool in principle; risks cognitive overload. **Recommend:** shift only by time-of-day, not by data — data has its own surfaces (rings, cards).
3. **Ship all three alternatives as code and let the user pick in Settings?** Tempting and very "privacy-first." But tripling surface area is how themes rot. **Recommend:** no — pick one, ship one. A user theme picker is a later phase, maybe post-1.0.
4. **Does the redesign coincide with a TestFlight promo / marketing moment?** If yes, sequence matters — land PR-3 before the promo, not during. **Recommend:** sync the flip day with a TestFlight build, but don't delay the design work for a marketing slot.
5. **Who generates the Stage 1 artifacts?** Claude can produce palette specs and describe mock screens in detail, but not pixel-accurate screenshots without the design tool handoff. **Recommend:** start with text/palette specs + annotated wireframes in Markdown; if the owner wants pixel mocks, spin up the design tool as a follow-up before locking Stage 2.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR. After approval, generate Stage 1 alternatives in a follow-up PR labeled `theme-alternatives`.*
