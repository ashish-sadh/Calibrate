# Design: Structurally Fix AI Chat (Revised)

> References: Issue #65
> Revision addressing owner review comments on PR #112:
> 1. Removed A/B testing (no telemetry in local app)
> 2. Redesigned flow with proper states and transitions
> 3. Broke unified classifier into specialized per-domain prompts

## Problem

AI chat is brittle. The pipeline has 50+ hardcoded rules in StaticOverrides, 150+ keywords in ToolRanker, and 8+ regex patterns in AIActionExecutor. Voice input makes this worse.

But the core problem isn't the StaticOverrides list — it's the **flow design**. Today's IntentClassifier tries to do classification AND data extraction in a single LLM call. Even on clear input like "log 2 eggs and toast for breakfast", it sometimes:
- Misclassifies the intent (routes to food_info instead of log_food)
- Extracts wrong data (returns `"eggs, toast"` as a single food name, drops `servings: 2`)
- Combines macro text into food names ("Salad And 200 G Of Protein")

A single prompt trying to understand intent, parse food names, extract quantities, resolve meal types, AND handle 13 different tools is doing too much. Production chat systems solve this by separating concerns into stages.

## Proposal

Replace the unified classifier with a **multi-stage pipeline**: normalize → intent classify → domain-specific extraction → confirmation → execute. Each stage has a focused prompt optimized for one job. Multiple LLM passes are acceptable — **a correct answer in 5s beats a wrong answer in 3s**.

## How Production Chat Systems Handle This

Research into production LLM chat architectures reveals consistent patterns:

**OpenAI Function Calling** — Intent detection is implicit in the model's tool-use decision, but extraction happens per-function with typed parameter schemas. Each function has its own parameter spec — the model fills slots for one function at a time.

**Rasa (open-source assistant framework)** — Separates NLU (intent + entity extraction) from dialogue policies (what to do next) from actions (execution). Each component can be trained/tuned independently.

**Google Dialogflow / Vertex AI Agents** — Intents and entities are separate concepts. Intent classifies the user's goal, entities extract the specific values. Different entity types have different extraction rules.

**Common pattern: decompose into stages, specialize each stage, validate between stages.**

For on-device with a 2B model, we can't do fine-tuning, but we CAN:
1. Use separate, focused prompts (fewer instructions → fewer errors)
2. Validate LLM output with Swift-based checks between stages
3. Use existing Swift extraction (parseFoodIntent) as fallback when LLM extraction fails

## Architecture: Multi-Stage Pipeline

```
User message
    │
    ▼
┌─────────────────────────────┐
│ Stage 0: Input Normalizer   │  instant, no LLM
│ Strip filler, whitespace,   │  InputNormalizer (exists)
│ voice artifacts             │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│ Stage 1: Thin Static Layer  │  instant, ~10 patterns
│ Greetings, undo, help,     │  StaticOverrides (trimmed)
│ barcode, navigation         │
└─────────────┬───────────────┘
              │ (unmatched)
              ▼
┌─────────────────────────────┐
│ Stage 2: Intent Classifier  │  LLM, ~2s
│ "What domain is this?"      │  NEW focused prompt
│ Returns: domain + sub-type  │
│ NOT extraction — just intent│
└─────────────┬───────────────┘
              │
    ┌─────────┼──────────┐
    ▼         ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐
│ Food   │ │Exercise│ │ Weight │ ...  Stage 3: Domain Extractors
│Extractor│ │Extractor│ │Extractor│     LLM, ~2s each
│(prompt)│ │(prompt)│ │(prompt)│     NEW specialized prompts
└───┬────┘ └───┬────┘ └───┬────┘
    │          │          │
    ▼          ▼          ▼
┌─────────────────────────────┐
│ Stage 3b: Swift Validation  │  instant
│ Validate extracted params   │  parseFoodIntent / regex
│ Reject nonsense, fix types  │  as fallback + sanity check
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│ Stage 4: Confirmation       │  UI
│ Show user what was parsed   │  ManualFoodEntrySheet,
│ User reviews + confirms     │  workout preview, etc.
└─────────────┬───────────────┘
              │ (confirmed)
              ▼
┌─────────────────────────────┐
│ Stage 5: Execute + Respond  │  DB write
│ Persist, update widgets,    │  ToolRegistry (exists)
│ track undo action           │
└─────────────────────────────┘
```

### Stage 2: Intent Classifier (New Focused Prompt)

The current IntentClassifier prompt tries to classify AND extract in one call with 13 tools and 20+ examples. The new prompt does **classification only**:

```
System: You are an intent classifier for a health tracking app.
Given the user's message, reply with ONLY a JSON object:
{"domain":"food|exercise|weight|supplement|health|navigation|chat","intent":"log|query|delete|plan|other"}

Domains:
- food: logging food, asking about calories/macros/nutrition, meal planning
- exercise: logging workouts, asking about exercises, starting templates
- weight: logging weight, body composition, weight trends
- supplement: marking supplements taken, supplement info
- health: sleep, glucose, biomarkers, recovery, cycle tracking
- navigation: "show me X", "go to Y tab"
- chat: greetings, thanks, general questions, unclear intent

Examples:
"log 2 eggs and toast" → {"domain":"food","intent":"log"}
"how many calories did I eat" → {"domain":"food","intent":"query"}
"I did bench press 3x10" → {"domain":"exercise","intent":"log"}
"how's my bench progressing" → {"domain":"exercise","intent":"query"}
"I weigh 165" → {"domain":"weight","intent":"log"}
"show me my weight chart" → {"domain":"navigation","intent":"other"}
"delete last entry" → {"domain":"food","intent":"delete"}
"plan my meals today" → {"domain":"food","intent":"plan"}
```

**Why this is better:** ~60 tokens of system prompt vs ~150 today. Fewer instructions → less confusion. The model only decides WHAT domain, not HOW to extract. If unsure, it returns `"chat"` → streaming fallback.

### Stage 3: Domain-Specific Extraction Prompts

Each domain gets its own extraction prompt, optimized for its specific data schema.

**Food Extraction Prompt:**
```
System: Extract food items from the user's message.
Reply JSON: {"items":[{"name":"...","servings":1,"unit":"serving"}],"meal":"breakfast|lunch|dinner|snack|null","calories":null}

Rules:
- Split multi-item messages: "2 eggs and toast" → 2 items
- Keep compound food names intact: "mac and cheese" is ONE item
- "with" often separates items: "rice with dal" → 2 items
- Numbers before food = servings: "2 eggs" → servings:2
- Numbers after food with unit = amount: "chicken 200g" → name:"chicken", servings:200, unit:"g"
- Explicit calories override: "salad with 500 cal" → calories:500
- Meal hints from context: "for breakfast" → meal:"breakfast"
```

**Exercise Extraction Prompt:**
```
System: Extract exercise details from the user's message.
Reply JSON: {"name":"...","sets":null,"reps":null,"weight":null,"weight_unit":"lbs","duration_min":null}

Rules:
- "3x10 at 135" → sets:3, reps:10, weight:135
- "bench press" → name:"bench press"
- "ran for 30 minutes" → name:"running", duration_min:30
- "half an hour" → duration_min:30
```

**Weight Extraction Prompt:**
```
System: Extract weight value from the user's message.
Reply JSON: {"value":0,"unit":"lbs|kg"}

Rules:
- "I weigh 165" → value:165, unit:lbs (default)
- "75.5 kg" → value:75.5, unit:kg
```

**Why specialized prompts are better:**
1. Each prompt has ~30-40 tokens of rules (vs 150+ in unified prompt)
2. Food prompt knows about multi-item splitting, compound names, meal types
3. Exercise prompt knows about sets/reps/weight notation
4. No cross-domain confusion ("fat" in food context ≠ "fat" in body comp context)
5. Each prompt can be tested and iterated independently

### Stage 3b: Swift Validation Layer

Between LLM extraction and confirmation, validate with existing Swift code:

```swift
func validateFoodExtraction(_ llmResult: FoodExtractionResult) -> ValidatedFood? {
    for item in llmResult.items {
        // DB lookup — does this food exist?
        let match = AIActionExecutor.findFood(query: item.name, servings: item.servings)
        
        // Sanity checks
        guard item.servings > 0 && item.servings < 100 else { continue }
        
        // If LLM extraction failed, fall back to Swift extraction
        if match == nil {
            let swiftParse = AIActionExecutor.parseFoodIntent(item.name)
            // Use Swift result as fallback
        }
    }
}
```

This catches LLM hallucinations: nonsense food names, impossible serving sizes, wrong data types.

### Query Path (No Extraction Needed)

For `intent: "query"`, skip Stage 3 extraction entirely. Route directly to the existing info tools:

```
food + query → food_info tool → streamPresentation (existing)
exercise + query → exercise_info tool → streamPresentation (existing)
weight + query → weight_info tool → streamPresentation (existing)
```

The Stage 2 intent already tells us which info tool to use. No extraction needed — just pass the raw query.

### Multi-Turn Context

Each stage receives conversation history as a prefix:

```
Stage 2 (intent): "Chat:\nAI: What did you have for lunch?\n\nUser: rice and dal"
→ Classifier sees context → {"domain":"food","intent":"log"}

Stage 3 (extraction): Same history prefix
→ Food extractor sees "rice and dal" with lunch context → items:[{name:"rice"},{name:"dal"}], meal:"lunch"
```

History window: 400 chars (from current 200). At ~4 chars/token, this is ~100 tokens — well within Gemma's 2048 budget even with 2 LLM calls.

## Latency Analysis

| Path | Current | New | Notes |
|------|---------|-----|-------|
| Static (greetings, undo) | ~0ms | ~0ms | Unchanged |
| Log food (Gemma) | ~3s (1 LLM call) | ~5s (2 LLM calls) | +2s but correct extraction |
| Query (Gemma) | ~3-6s | ~5-8s | +2s for intent, then existing tool+stream |
| SmolLM path | ~0ms rules | ~0ms rules | Unchanged |

The +2s for a second LLM pass is the right tradeoff. A food logging error (wrong food, wrong calories) costs the user trust and takes effort to fix. A 2s wait costs nothing.

**Mitigation:** Both LLM calls use small, focused prompts (~40-60 tokens system). Smaller prompts → faster inference on Gemma 2B.

## Files That Change

| File | Change |
|------|--------|
| `Services/AIToolAgent.swift` | Reorder pipeline: normalize → thin static → intent classify → domain extract → validate → confirm → execute |
| `Services/IntentClassifier.swift` | Replace unified prompt with classification-only prompt. New method: `classify(message:history:) -> IntentResult` returning domain+intent only |
| `Services/DomainExtractor.swift` | **New file.** Per-domain extraction prompts. Methods: `extractFood()`, `extractExercise()`, `extractWeight()`, `extractSupplement()` |
| `Services/StaticOverrides.swift` | Trim to ~10 essential patterns (greetings, undo, help, barcode, navigation) |
| `Services/ToolRanker.swift` | Remove `tryRulePick()` for Gemma path. Keep `rank()` for SmolLM and `buildPrompt()` for streaming fallback |
| `Services/AIActionExecutor.swift` | Keep all extraction logic — used as Stage 3b validation fallback |

## Dual-Model Handling

- **Gemma 4 (8GB+ devices):** Full multi-stage pipeline (Stage 0-5)
- **SmolLM (6GB devices):** Keep current rules-first pipeline unchanged. SmolLM can't reliably do classification in 2048 context. Phase 1 (ToolRanker.tryRulePick) remains the primary path.

## Edge Cases

- **Intent classifier unsure:** Returns `domain: "chat"` → streaming fallback (existing Phase 4). No extraction attempted.
- **Extraction fails:** Swift validation catches it → falls back to `parseFoodIntent()` / regex extraction. If that also fails → ask user to clarify.
- **Classifier timeout (10s):** Same as today — fall through to streaming.
- **Multi-domain message:** "log 2 eggs and I weigh 165" — classifier picks the first/primary domain. Second intent is lost. Acceptable for v1; v2 could support multi-intent.
- **Undo after multi-stage action:** ConversationState.lastWriteAction tracking unchanged. Undo stays in thin static layer.
- **SmolLM device:** Pipeline unchanged — no regression.

## Measurement

No A/B testing — the app is fully local with no telemetry infrastructure. Instead:

1. **Gold set eval (before/after):** Run the existing 55-query gold set eval + the food logging gold set. Compare accuracy metrics.
2. **Per-stage eval:** Add test harnesses for Stage 2 (intent accuracy) and Stage 3 (extraction accuracy) independently. This lets us pinpoint which stage degrades.
3. **Failing queries regression:** Run `Docs/failing-queries.md` queries through both old and new pipelines. New pipeline must resolve more failures.

## Implementation Order

1. **Stage 2: Intent classifier prompt** — Replace unified prompt with classification-only. Measure intent accuracy on gold set.
2. **Stage 3: Food extraction prompt** — Food is the highest-volume domain. Build and test food-specific extraction.
3. **Stage 3b: Validation layer** — Wire Swift extraction as fallback/sanity check.
4. **Pipeline integration** — Wire stages together in AIToolAgent.
5. **Stage 3: Other domain extractors** — Exercise, weight, supplement extraction prompts.
6. **Prune StaticOverrides** — Remove rules now handled by the LLM pipeline.
7. **Prune ToolRanker** — Remove tryRulePick for Gemma path.

Each step is independently testable and shippable.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
