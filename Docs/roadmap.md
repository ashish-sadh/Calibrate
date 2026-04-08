# Product Roadmap

## Vision
AI-first health tracker. AI chat is the primary interface — every data entry doable through conversation. Traditional UI for visual analytics and fallback.

## Phase 1: Core Health Tracking (DONE)
Built the foundation: weight, food, exercise, sleep, supplements, body comp, glucose, biomarkers, cycle tracking. All local, no cloud.

## Phase 2: AI Chat Foundation (DONE)
- On-device inference: llama.cpp, Metal GPU
- Dual-model: SmolLM (reliable harness) + Gemma 4 (intelligence)
- 19 JSON tools, screen bias removed, chain-of-thought
- Food/weight/exercise/health logging and queries from chat
- Eval harness: 212+ tests + 100-query LLM eval

## Phase 3: AI Chat Architecture (CURRENT)

### 3a: Tiered Pipeline (DONE)
- ToolRanker: keyword scoring, 19 tool profiles, rule-based tool pick
- AIToolAgent: tiered normalize → rules → tool-first → stream
- Universal StaticOverrides (no isLargeModel gate)
- LLM normalizer: spell correction, number normalization, query rewriting
- 20s timeout on all LLM calls
- Early JSON termination, spell correction in findFood

### 3b: Parity Gaps Closed (DONE)
- Mark supplement, edit/delete food, copy yesterday, quick-add calories
- Set weight goal, barcode scan, body comp, add supplement
- Weekly comparison, cross-domain analysis
- Handler ordering: all view-state + multi-turn handlers before LLM pipeline

### 3c: Pipeline Quality (IN PROGRESS)
- Multi-turn via normalizer context (replace pendingMealName state vars)
- Normalizer accuracy tuning for Gemma 4 2B
- Multi-turn pronoun resolution
- Tool-first streaming presentation (execute tools → inject data → stream)
- Eval expansion (300+ tests)
- Food search quality (singular-first, extractAmount patterns)

## Phase 4: Input Expansion (NEXT)
- Voice input: iOS 26 SpeechAnalyzer (on-device) → AI chat
- Photo food logging: Core ML classifier → chat confirmation
- iOS widgets: calories remaining, recovery score
- Apple Watch: workout detection hints

## Phase 5: Deep Intelligence (FUTURE)
- Fine-tuned SmolLM on Drift tool-calling dataset
- Grammar-constrained sampling for reliable JSON
- On-device embeddings: semantic food/exercise search
- Training programming across weeks
- Weekly AI summary push notification
- Conversation memory (tool results persist across sessions)
- Multi-turn meal planning dialogue
