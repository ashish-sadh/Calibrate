# Backlog — Organized by AI Chat Architecture

Items move to `sprint.md` when picked up.

---

## AI Pipeline Improvements

### Normalizer Quality
- ~~Normalizer accuracy tuning~~ ✓ — 330+ eval scenarios, 90-100%
- ~~Multi-turn context resolution~~ ✓ — history-based detection + topic continuation
- ~~Meal continuation~~ ✓ — "also add broccoli" appends to recipe
- ~~Number range handling~~ ✓ — "2 to 3 bananas" → 3
- ~~Word numbers~~ ✓ — "set goal to one sixty" → 160

### Tool-First Execution
- ~~Parallel tool execution~~ ✓ — TaskGroup-based parallel info tool execution
- **Progressive multi-item disclosure** — "rice and dal" → show each item as found, don't batch.
- ~~Parallel rule check + normalize~~ ✓ — StaticOverrides + parsers already instant before normalizer

### Chat Quality
- **Grammar-constrained sampling** — Force valid JSON from SmolLM via llama.cpp grammar.
- **Fine-tune SmolLM** — Collect Gemma 4 tool-calling examples → distill to SmolLM.
- **Larger context window** — Test 4096 tokens (currently 2048). Memory profiling needed.
- **Streaming quality** — Clean artifacts during streaming, not just after.
- **Conversation memory** — Pass tool results back to next turn.

## AI Chat Gap Closing (from ai-parity.md)

### Friction Reducers (ALL DONE)
- ~~Mark supplement taken~~ ✓
- ~~Edit/delete food~~ ✓
- ~~Copy yesterday~~ ✓
- ~~Quick-add calories~~ ✓
- ~~Set weight goal~~ ✓
- ~~Body comp entry~~ ✓
- ~~Add supplement~~ ✓
- ~~Trigger barcode~~ ✓
- ~~Manual macros~~ ✓

### Multi-Turn (Gemma 4)
- **Meal planner** — "plan my meals today". Multi-turn: suggest → adjust → confirm → log all.
- **Workout split** — "build me a PPL split". Design across multiple sessions.
- ~~Cross-domain~~ ✓
- ~~Comparison~~ ✓
- ~~Coaching~~ ✓ — cross-domain handler with contextual real data

## Input Expansion
- **Voice input** — iOS 26 SpeechAnalyzer → on-device speech-to-text → AI chat.
- **Photo food logging** — Core ML food classifier → DB match → chat confirmation.
- **Vision model POC** — llama.cpp vision model for food photo → description → tool call.

## Traditional UI
- **Saved meals** — One-tap re-log of multi-item meals.
- **Inline diary editing** — Tap number to edit directly.
- **iOS widgets** — Calories remaining, recovery score.
- **Accessibility** — VoiceOver labels.
- **Macro rings** — Apple Fitness-style concentric rings.

## Data & Architecture
- **Export CSV** — Weight, food, workout data.
- **UserDefaults centralization** — 30+ hardcoded keys → enum.
- **Cache HealthKit baselines** — 42 queries per dashboard load → cache 6h.
- **Weekly AI summary notification** — Background task → push.
