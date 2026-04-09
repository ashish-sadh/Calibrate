# Human-Reported Bugs & Feature Requests

Bugs and features reported directly by the user. Fix these with high priority.

---

## BUG-001: "Calories left" shows wrong number

**Reported:** 2026-04-06
**Status:** Fixed (commit 5476a41)
**Severity:** High

When user asks "how many calories left", the AI chat returns the wrong number. It uses total needed calories (TDEE / estimated burned) as the value instead of remaining calories (TDEE - consumed).

**Fix:** Removed TDEE from weight context line (LLM was confusing TDEE with target/remaining). Split nutrition into explicit "Calories: X eaten, Y target, Z remaining" format. LLM now sees unambiguous remaining count.

**How to reproduce:** Ask "how many calories left" in AI chat. Compare with the Food tab's actual remaining.

**Where to look:** Rule engine in `AIChatView.swift` (calories left handler), `AIContextBuilder.swift` (food context values).

---

## FEAT-001: Estimate calories from description

**Reported:** 2026-04-06
**Status:** Partially done (commit a342697 + 93095e6)
**Priority:** Medium

User should be able to ask "how many calories in a samosa?" or "estimate calories for butter chicken with 2 roti" and get a reasonable answer from the AI — without logging it. This is a lookup/estimation feature, not a logging action.

**Done so far:**
- Instant DB lookup for "calories in X" — shows nutrition + offers to log (a342697)
- Expanded routing keywords: "estimate calories", "nutrition for", "calories for" (93095e6)
- Falls through to LLM for estimation if food not in DB

**Implementation ideas:**
- Route "how many calories" / "estimate calories" / "calories in X" queries to a new intent
- Look up foods in the local `foods.json` database first (exact + fuzzy match)
- If found: return the real nutritional data from the database
- If not found: let the LLM estimate based on its training data (small models know rough calorie counts)
- Show breakdown: calories, protein, carbs, fat per serving
- Offer to log it after showing the estimate: "Want me to log this?"
- Add eval harness tests: "calories in a banana", "how many calories in dal rice", "estimate calories for 2 eggs and toast"
- Should work for Indian foods, restaurant meals, homemade dishes
- Multi-item: "calories in a thali" should break down components

**Not in scope:** Photo-based estimation (that's a separate vision model POC).

---

## BUG-002: Recent foods missing macros on manual entries

**Reported:** 2026-04-08
**Status:** Open
**Severity:** Medium

When a user adds a manual entry (quick-add with custom calories/macros), it doesn't properly save nutrition data to the recents system. Re-logging the food from "Recent" shows 0 calories and 0 macros.

**How to reproduce:** Quick-add a food with macros → check Recent foods → try to re-log it → shows 0 cal.

**Where to look:** `FoodLogViewModel.logFood()` or `quickAdd()` → how it calls `trackFoodUsage()`. Check if `trackFoodUsage` stores calories/macros or just the name.

---

## FEAT-002: Copy food to today from past day view

**Reported:** 2026-04-08
**Status:** Open
**Priority:** Medium

When viewing a past day's food log, user should be able to copy individual items (or all) to today. Should show a brief confirmation toast without navigating away. Don't show copy option when already viewing today.

---

## BUG-003: Plant points "Today" label doesn't update with date

**Reported:** 2026-04-08
**Status:** Open
**Severity:** Low

Plant points section shows "Today" even when user navigates to a different date. Should show the actual date (e.g. "Apr 5") when not viewing today. Week and month sections are fine.
