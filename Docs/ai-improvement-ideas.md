# AI Improvement Ideas (Curated)

## Implemented So Far
- Raw llama.cpp C API (bypasses Metal crash on A19 Pro)
- Chain-of-thought with visible "thinking" steps
- Token streaming (word-by-word text appearance)
- Screen awareness (11 views tracked)
- Full context: food, weight, sleep, glucose, biomarkers, DEXA, cycle, supplements, workouts
- Multi-food logging, weight entry via chat
- Natural phrasing ("I just had a samosa")
- AI-enhanced lab report parsing
- Few-shot examples in system prompt
- Pre-computed insights ("losing at healthy pace", "low protein by afternoon")
- Response cleaner (artifacts, disclaimers, deduplication)
- Quality gate (filters generic/repetitive responses)
- Nutrition lookup from DB ("how many calories in banana?")
- Comparison context (this week vs last week)
- Pronoun resolution ("log it" after discussing banana)
- Token budget management (800 token context cap + backend truncation)
- Data-aware greetings

## Research Findings (from web search)
1. Small models (< 2B) benefit from:
   - Very explicit, terse instructions over verbose prompts
   - 1-2 few-shot examples (more wastes tokens)
   - Temperature 0.3-0.5 for factual responses
   - Doing ALL math in Swift, model just phrases it
   - Structured output formats (fill-in-the-blank over free-form)
   - Short responses (hallucination increases with length)
   - repeat_penalty 1.1-1.3

2. "LLM is the voice, Swift is the brain":
   - Calculate deficits, projections, trends in Swift
   - Model's job: turn structured data into friendly sentences
   - Never ask model to do arithmetic or retrieve from memory

## Ideas for Next Session

### High Impact
- [ ] **Direct food logging without search sheet** — when exact DB match found, log immediately and confirm ("Logged 2 eggs (156cal)")
- [ ] **Meal plan builder** — "plan my meals for today" generates a full day plan based on remaining macros and user's food history
- [ ] **Smart time-of-day suggestions** — at 7am, suggest breakfast items; at 6pm, dinner items with remaining macro targets
- [ ] **Exercise recommendation** — based on last 7 days of workouts, suggest which body part hasn't been trained

### Medium Impact
- [ ] **Image-based food logging** — take a photo of food, describe it to LLM, auto-log (needs MLX vision model or simple image classifier)
- [ ] **Voice input** — iOS speech-to-text → AI chat, hands-free food logging
- [ ] **Weekly AI summary push notification** — generate a weekly insight via background task
- [ ] **Goal adjustment recommendations** — "based on your 30-day trend, consider adjusting your deficit to -300kcal/day"
- [ ] **Supplement interaction warnings** — flag when supplements might interact or when timing matters

### Research Required
- [ ] **On-device embedding for semantic search** — MiniLM or similar for better food matching
- [ ] **Exercise form videos** — link exercises to demonstration videos (YouTube API or bundled clips)
- [ ] **Fine-tuning the model** — create a small dataset of health Q&A pairs and fine-tune Qwen2.5-1.5B
- [ ] **Metal shader fix** — build llama.cpp from source with A19 Pro compatible Metal shaders (would enable GPU inference = 3-5x faster)
- [ ] **Larger context window** — increase to 4096 tokens for more context (needs memory testing on device)
- [ ] **Model distillation** — fine-tune SmolLM2-360M to match Qwen2.5-1.5B quality for faster inference
