# Failing Queries — AI Chat Fix Backlog

Real queries that don't work well. The self-improvement loop picks from here, fixes systematically, then moves the query to Fixed.

**Rules for fixing:**
- Fix the CATEGORY, not just the exact query. "suggest me workout" fix should also handle "give me a workout", "recommend exercises", etc.
- Small model: add hardcoded handler with keyword matching (reliable, fast)
- Large model: ensure the right tool is called via prompt/schema (LLM decides)
- Add eval harness tests for the query AND 3+ variants
- Test both model paths before marking fixed

## Failing

### Exercise
- [x] **"suggest me workout"** — Fixed: hardcoded handler catches 12 phrasings. Both models use Swift path.
- [x] **"I did yoga today"** — Fixed: parses activity name + optional duration, creates Workout entry. Handles "went running", "did 30 min cardio", "just finished pilates".
- [x] **"how many workouts this week"** — Fixed: instant rule engine handler with streak info.

### Food
- [ ] **"what's healthy for dinner"** — LLM gets this but response quality is poor. Should use suggestMeal with macro awareness. Similar: "healthy meal ideas", "what's a good dinner"
- [ ] **"I had a cheat meal"** — No handler. Should ask what they ate. Similar: "I went off plan", "I ate out"
- [ ] **"how much sugar today"** — No sugar tracking in daily totals display. Similar: "sugar intake", "how much sugar did I eat"

### Weight
- [x] **"am I making progress"** — Fixed: added to needsOverview keywords, gets fullDayContext + weight.

### Cross-Domain
- [x] **"should I eat more today"** — Fixed: cross-domain trigger pulls food + workout context automatically.
- [x] **"I feel tired"** — Fixed: cross-domain trigger pulls sleep + food context automatically.

### Multi-Turn
- [ ] **"plan my meals for today"** — Should be iterative: suggest breakfast → user confirms → suggest lunch → etc. Currently gives a single response.

## Fixed

_(Queries move here after systematic fix + eval tests added)_
