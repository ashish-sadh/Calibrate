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
- [ ] **"I did yoga today"** — No handler for logging a completed workout by name. Should create a workout entry. Similar: "I went running", "did 30 min cardio", "just finished pilates"
- [ ] **"how many workouts this week"** — Falls to LLM, should be instant from WorkoutService. Similar: "workout count", "how often did I train"

### Food
- [ ] **"what's healthy for dinner"** — LLM gets this but response quality is poor. Should use suggestMeal with macro awareness. Similar: "healthy meal ideas", "what's a good dinner"
- [ ] **"I had a cheat meal"** — No handler. Should ask what they ate. Similar: "I went off plan", "I ate out"
- [ ] **"how much sugar today"** — No sugar tracking in daily totals display. Similar: "sugar intake", "how much sugar did I eat"

### Weight
- [ ] **"am I making progress"** — Ambiguous. Should combine weight trend + food adherence. Similar: "how's my progress", "am I doing well"

### Cross-Domain
- [ ] **"should I eat more today"** — Needs food remaining + workout data. Similar: "do I need more calories", "should I eat back exercise calories"
- [ ] **"I feel tired"** — Should check sleep + recovery + food intake. Similar: "I'm exhausted", "no energy today"

### Multi-Turn
- [ ] **"plan my meals for today"** — Should be iterative: suggest breakfast → user confirms → suggest lunch → etc. Currently gives a single response.

## Fixed

_(Queries move here after systematic fix + eval tests added)_
