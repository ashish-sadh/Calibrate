---
name: ui-review
description: Screenshot Drift on the iOS simulator across all five tabs + key sheets, dump the UI hierarchy for each, and report visible issues (invisible text, broken layout, dark holdovers). Run after any UI change before declaring done, and especially before publishing TestFlight.
---

<role>
You are auditing Drift's UI on the iOS Simulator using the `mobile` MCP
server. You are NOT a stylist: you are a regression-spotter. You're looking
for the specific failure modes that have hit Drift before — invisible text
(white-on-white from dark-era leftovers), unreadable contrast, mis-aligned
glyphs, accidental empty states, broken nav titles, off-theme colors —
not opinions about whether a card is "pretty."
</role>

<inputs>
- Optional `focus`: a single screen or sheet to deep-dive (default: full sweep).
- Optional `compare_to`: a previous screenshot path to diff against.
</inputs>

<setup>
Drift bundle ID: `com.drift.health`. Don't hardcode that elsewhere — read
it from `project.yml` if you need a fresh source of truth.

Boot/install before screenshotting:

1. `xcrun simctl boot "iPhone 17 Pro"` (idempotent — no-op if already booted)
2. Build for simulator if the app isn't already installed at the current SHA:
   `xcodebuild build -project /Users/ashishsadh/workspace/Drift/Drift.xcodeproj
   -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
3. Install: `xcrun simctl install booted <derived-data .app path>`
4. Launch: `mobile_launch_app(bundleId: "com.drift.health")` — or
   `xcrun simctl launch booted com.drift.health` as a fallback.

If the app is mid-launch (splash visible), wait 2s before the first screenshot.
</setup>

<sweep>
Default sweep — every screen the user has flagged at least once:

1. **Drift tab (Dashboard)** — `mobile_take_screenshot` after launch.
   Then scroll the dashboard: `mobile_swipe_on_screen(direction: "up")`.
   Take a second screenshot of the "Body" section + meal timeline area.
2. **Weight tab** — `mobile_click_on_screen_at_coordinates` on the
   "Weight" tab item via `mobile_list_elements_on_screen` to find its
   identifier (`tab-weight` once IDs are backfilled). Screenshot.
3. **Food tab** — same pattern, tap `tab-food`. Screenshot the meals
   list. Don't enter any sub-sheets unless `focus=food`.
4. **Exercise tab** — tap `tab-exercise`. Screenshot the empty/templates
   state + the muscle-group grid. The user has flagged this tab for
   over-red palette — note any monochromatic red CTAs.
5. **More tab** — tap `tab-more`. Screenshot the menu list. Open
   Settings: tap the "Settings" row, screenshot the top section
   (Apple Health, iCloud, Export). Back out.

Then the key sheets:

6. **Set Goal sheet** — More → Goal → Set Goal. Screenshot the form;
   tap `goal-setup-save` with no weight data to verify the alert fires.
7. **AI Chat overlay** — back on Drift tab, tap the floating bubble
   (`ai-floating-bubble`). Screenshot the expanded panel. Confirm:
   - No "Download Drift Brain" prompt (FM is default).
   - No "Beta" pill next to "Drift AI".
   - Background is light, not the legacy Color(white: 0.1).
   - Input bar text is legible.
</sweep>

<context_rules>
- After each screenshot, also call `mobile_list_elements_on_screen` and
  scan the dumped tree for surprises: elements with no label, elements
  whose `value` is empty when it shouldn't be, duplicate tab items.
- Don't compare visual hashes — just look at the tree + the rendered
  text. The user cares about "I can read this" + "this didn't render
  empty by accident," not pixel parity.
- Keep your final report short. Bullet-list per screen:
  PASS — nothing surprising
  FAIL — `tab-weight`: x-axis date labels still rendering as
    textTertiary on white, contrast ~2.8:1, below AA floor for small text.
  → fix: bump Theme.textTertiary or use textSecondary for axis.
- Don't open sheets that aren't in the sweep unless `focus` names one.
  This is a regression scan, not an exploration session.
</context_rules>

<exit_condition>
Return a markdown bullet list of findings, grouped by screen. End with a
single-line verdict:
- `PASS` — nothing to fix.
- `FIX` — 1+ findings; the implementer should address before commit/TestFlight.
Do not file issues, do not commit, do not push. Just report.
</exit_condition>
