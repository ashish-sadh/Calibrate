# Architecture: AI-First Health Tracker

## Philosophy

AI chat is the primary interface — the showstopper. Every data entry should be doable through conversation. Traditional UI exists for visual analytics and as a fallback.

**Dual-model approach:**
- **SmolLM (360M)** — Reliable harness. Hardcoded keyword/rule engine does heavy lifting.
- **Gemma 4 (2B)** — Intelligence layer. LLM normalizes queries, handles ambiguity, streams answers.

**Separation of concerns:**
- **LLM handles:** Language understanding (spelling, numbers, phrasing), natural presentation
- **Rules handle:** Tool selection (keyword scoring, deterministic, fast)
- **Swift handles:** All computation, database, HealthKit, UI. Model never does math or recalls data.

## Tiered Pipeline (Gemma 4)

```
User message
    |
    v
Tier 0: Rules on RAW input (instant)
  StaticOverrides → Swift parsers → view-state handlers
  "calories left", "log 3 eggs", "start push day", "remove the rice"
  Catches ~60-70% of queries
    |  no match
    v
Tier 1: LLM Normalizer → Re-run rules (~3s)
  Rewrites messy input: "I had 2 to 3 banans" → "log 3 banana"
  ~80 token prompt, spell correction, number normalization
  Re-runs rules on clean output
  Catches ~20% more
    |  no match
    v
Tier 2: Rule-based Tool Picker (instant)
  ToolRanker keyword scoring → direct tool execution
  "how is my sleep" → sleep_recovery (high confidence)
  No LLM needed for tool selection
    |  no confident match
    v
Tier 3: Tool-First Execution → Stream Presentation (~5-8s)
  Execute relevant info tools (instant DB queries)
  Inject real data into streaming prompt
  LLM streams natural answer grounded in actual data
    |  no tool matched
    v
Tier 4: Pure Streaming (~10-20s)
  Full context + history + ranked tools → stream answer
  For true questions/conversation only
  20s timeout — falls back if model hangs
```

## SmolLM Path (Small Model)

- Same Tier 0 rules (StaticOverrides, Swift parsers)
- No normalizer (too slow for 360M)
- 6 tools per screen, 800-token context
- Chain-of-thought: keyword → data fetch → single LLM call

## Key Components

### ToolRanker (`Services/ToolRanker.swift`)
Keyword-based tool scoring with 19 tool profiles. Each profile has:
- Trigger keywords with weights
- Intent affinity (log vs query vs chat)
- Screen affinity bonuses
- Anti-keywords for suppression

Methods:
- `rank()` — score and return top N tools
- `tryRulePick()` — confident tool selection without LLM (score ≥ 4.0, gap ≥ 2.0)
- `normalizePrompt()` — ~80 token universal normalizer prompt
- `buildPrompt()` — full streaming prompt with context
- `extractParamsForTool()` — extract params from query per tool type

### AIToolAgent (`Services/AIToolAgent.swift`)
Orchestrates the tiered pipeline:
- `normalizeQuery()` — LLM rewrites messy input to clean form
- `run()` — tiered: rules → normalize → tool pick → tool-first → streaming
- `executeRelevantTools()` — execute top info tools before streaming
- `streamPresentation()` — LLM streams with pre-fetched data injected
- 20s timeout on all LLM calls

### StaticOverrides (`Services/StaticOverrides.swift`)
Instant deterministic handlers for both models:
- Greetings, thanks, help, barcode scan
- Rule engine: daily summary, calories left, protein status, supplements, etc.
- Regex handlers: body comp, weight goal, inline macros, quick-add calories
- All handlers are universal (no isLargeModel gate)

## Token Budgets

| Component | Normalizer (Tier 1) | Full Stream (Tier 3/4) |
|-----------|--------------------|-----------------------|
| System prompt | ~50 | ~200 |
| Tools | 0 | ~150 (top 4) |
| Context | 0 | ~500 |
| History | ~50 | ~150 |
| User message | ~15 | ~100 |
| **Total** | **~115** | **~1100** |

Hard limits: 2048 context, 1776 max prompt, 256 max generation.

## Tool Registry

19 tools (JSON tool-calling with pre/post hooks):

| Tool | What it does |
|------|-------------|
| `log_food` | Log food (pre-hook: DB lookup, gram conversion) |
| `food_info` | Calories, macros, protein/carbs/fat focus, suggestions |
| `copy_yesterday` | Copy yesterday's food |
| `delete_food` | Remove a food entry |
| `explain_calories` | TDEE breakdown |
| `log_weight` | Log body weight (with confirmation) |
| `weight_info` | Trend, goal progress |
| `set_goal` | Set weight goal |
| `start_workout` | Start template or smart session |
| `exercise_info` | Workout suggestion, overload, streak |
| `log_activity` | Log completed activity (yoga, running, etc.) |
| `sleep_recovery` | Sleep, HRV, recovery, readiness |
| `supplements` | Supplement status |
| `add_supplement` | Add new supplement to stack |
| `mark_supplement` | Mark supplement as taken |
| `glucose` | Readings, spike detection |
| `biomarkers` | Lab results |
| `body_comp` | Body fat, BMI, DEXA, lean mass |
| `log_body_comp` | Log body fat % or BMI |

## Performance Optimizations

- **Early JSON termination**: LlamaCppBackend stops generation as soon as `{}`brackets balance (saves ~1-2s)
- **Spell correction in findFood()**: `SpellCorrectService` catches "bannana"→"banana" via Levenshtein distance
- **Singular-first search**: "bananas" searches "banana" first for better matches
- **extractAmount patterns**: Handles "100 gram of rice", "2 cups of dal", "NUMBER UNIT of FOOD"
- **Bulk food "piece" filtering**: Nuts, grains, powder don't get misleading "piece" unit

## Models

| Model | Size | Devices | Speed | Role |
|-------|------|---------|-------|------|
| SmolLM2-360M Q8 | 368MB | 6GB (iPhone 15) | <2s CPU | Reliable harness |
| Gemma 4 E2B Q4_K_M | 2900MB | 8GB+ (iPhone 16 Pro) | ~3-5s GPU | Intelligence |

Auto-detect: `ramGB >= 6.5 → Gemma 4, >= 5.0 → SmolLM`.
GPU: Metal, all layers offloaded on A19 Pro. CPU fallback if Metal fails.
Auto-unload after 60s idle.

## Key Files

| File | Role |
|------|------|
| `Services/AIToolAgent.swift` | Tiered pipeline: normalize → rules → tools → stream |
| `Services/ToolRanker.swift` | Tool ranking, normalizer prompt, rule-based tool pick |
| `Services/ToolSchema.swift` | Tool registry, JSON parsing (strips parens), execution |
| `Services/ToolRegistration.swift` | 19 tool registrations with pre/post hooks |
| `Services/StaticOverrides.swift` | Universal deterministic handlers |
| `Services/LocalAIService.swift` | Backend orchestrator, respondDirect/respondStreaming |
| `Services/LlamaCppBackend.swift` | llama.cpp C API, early JSON termination |
| `Services/AIChainOfThought.swift` | Query classification, context fetching |
| `Services/AIContextBuilder.swift` | Per-domain context builders |
| `Services/AIActionExecutor.swift` | Food/weight intent parsing, findFood with spell correction |
| `Views/AI/AIChatView.swift` | Chat UI, sendMessage routing |
| `Docs/ai-chat-architecture.md` | Detailed architecture with diagrams |
