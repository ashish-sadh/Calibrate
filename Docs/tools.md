# Tool Registry — AI Tool-Calling Surface

AI chat is the primary interface. Tools are how chat controls the app.
Each service exposes tools the model can invoke via JSON. See `Docs/ai-parity.md` for gap tracking.

**LLM's job:** Understand language (normalize messy queries, stream natural presentations).
**Rules' job:** Pick tools (keyword scoring, deterministic, fast).
**Swift's job:** Execute tools, compute results, present UI.

## Tool Call Format

```json
{"tool": "log_food", "params": {"name": "eggs", "amount": "2"}}
```

Parsed via `parseToolCallJSON()` (strips `()` from tool names). Executed via `ToolRegistry.shared.execute()` with pre-hook → validate → handler → post-hook chain.

## Tool Selection: Tiered Architecture

### Tier 0 — StaticOverrides (instant)
Exact-match and regex handlers bypass the LLM entirely. Universal for both models.

### Tier 1 — LLM Normalizer (~3s)
Rewrites messy input ("I had 2 to 3 banans" → "log 3 banana"), then re-runs rules.

### Tier 2 — ToolRanker Rule Pick (instant)
Keyword scoring with 19 tool profiles. If top tool scores ≥ 4.0 with ≥ 2.0 gap from #2, executes directly. No LLM needed for tool selection.

### Tier 3 — Tool-First + Stream
Executes relevant info tools (instant DB queries), injects real data into streaming LLM prompt. First token in ~2s.

### Tier 4 — Full Streaming
Context + history + ranked tools → LLM streams response. 20s timeout.

---

## Food Tools (5)

**Source:** `ToolRegistration.swift`, `FoodService.swift`, `AIActionExecutor.swift`

| Tool | Parameters | Returns | UI Action |
|------|-----------|---------|-----------|
| `log_food` | name, amount? | — | Opens FoodSearchView (pre-hook: DB lookup, gram conversion) |
| `food_info` | query? | Calories/macros/suggestions. Focus: protein/carbs/fat | Inline |
| `copy_yesterday` | — | Copies yesterday's entries | Inline |
| `delete_food` | name | Removes matching entry | Inline |
| `explain_calories` | — | TDEE breakdown | Inline |

**`food_info`** is macro-aware: `query:"protein"` → protein-specific with target + remaining + high-protein suggestions.

---

## Weight Tools (3)

| Tool | Parameters | Returns | UI Action |
|------|-----------|---------|-----------|
| `log_weight` | value, unit? | Confirmation prompt | Inline ("Say yes") |
| `weight_info` | — | Trend, weekly rate, goal progress | Inline |
| `set_goal` | target, unit? | Sets weight goal | Inline |

---

## Exercise Tools (3)

| Tool | Parameters | Returns | UI Action |
|------|-----------|---------|-----------|
| `start_workout` | name | Template or smart session | Opens ActiveWorkoutView |
| `exercise_info` | exercise? | Suggestion, overload, streak | Inline |
| `log_activity` | name, duration? | Activity confirmation | Inline ("Say yes") |

---

## Health Tools (8)

| Tool | Parameters | Returns | UI Action |
|------|-----------|---------|-----------|
| `sleep_recovery` | — | Sleep, HRV, recovery, readiness | Inline |
| `supplements` | — | Taken/total, remaining | Inline |
| `add_supplement` | name, dosage? | Adds to stack | Inline |
| `mark_supplement` | name | Marks as taken | Inline |
| `glucose` | — | Readings, spikes | Inline |
| `biomarkers` | — | Lab results | Inline |
| `body_comp` | — | Body fat, BMI, DEXA | Inline |
| `log_body_comp` | body_fat?, bmi? | Logs entry | Inline |

---

## StaticOverrides (Instant — No Model Needed)

Both models check these first. Universal (no isLargeModel gate).

| Pattern | Handler |
|---------|---------|
| Emoji, greetings, thanks, help | Direct response |
| "daily summary" | `AIRuleEngine.dailySummary()` |
| "calories left" | `AIRuleEngine.caloriesLeft()` |
| "how's my protein" / "how is my protein" | Computed from nutrition + targets |
| "what did I eat today" | `AIContextBuilder.foodContext()` |
| "yesterday" | `AIRuleEngine.yesterdaySummary()` |
| "weekly summary" / "this week" | `AIRuleEngine.weeklySummary()` |
| "supplements" / "did I take" | `AIRuleEngine.supplementStatus()` |
| "copy yesterday" | `FoodService.copyYesterday()` |
| "body fat X%" / "bmi X" | Direct DB log (bf >= 3 && <= 60, bmi >= 12 && <= 60) |
| "set goal to X" | `WeightGoal.save()` |
| Quick-add calories | `FoodService.quickAddCalories()` |
| "took my creatine" | `SupplementService.markTaken()` |
| "scan barcode" | Opens barcode scanner |

---

## Hardcoded Intent Parsers (No Model Needed)

| Intent | Parser | Example |
|--------|--------|---------|
| Food logging | `AIActionExecutor.parseFoodIntent()` | "log 2 eggs", "ate chicken" |
| Multi-food | `AIActionExecutor.parseMultiFoodIntent()` | "log chicken and rice" |
| Weight logging | `AIActionExecutor.parseWeightIntent()` | "I weigh 165" |
| Activity logging | Prefix match + duration regex | "I did yoga 30 min" |
| Template start | String matching | "start push day" |
| Smart workout | Exact match | "start smart workout" |
| Delete food | Prefix match | "remove the rice", "undo" |
| Log exercise trigger | Noun match | "log exercise" → multi-turn |

---

## Food Search Pipeline

```
findFood(query, servings, gramAmount)
  1. Singular-first: "bananas" → try "banana" first
  2. Exact DB search (searchFoodsRanked)
  3. Spell correction: SpellCorrectService.correct()
  4. Qualifier stripping: "cups of rice" → "rice"
  5. First word: "chicken breast" → "chicken"
```

## Amount Parsing

`extractAmount()` handles:
- Word numbers: "three" → 3, "couple" → 2
- Multi-word: "a couple of", "a few"
- NUMBER UNIT of FOOD: "100 gram of rice" → (food: "rice", 100g)
- Trailing: "paneer biryani 300 gram"
- Compact: "chicken 200g"
- Fractions: "1/3 avocado"

## ToolRanker Profiles

19 tool profiles with trigger keywords, intent affinity (log/query), screen affinity, anti-keywords. Example:

```
log_food: triggers=[ate:3, had:2.5, log:2, eggs:2, chicken:2...]
          logBoost=2, queryBoost=-1
          screens=[food:0.5, dashboard:0.3]
          anti=[sleep, workout, supplement, how, what]
```
