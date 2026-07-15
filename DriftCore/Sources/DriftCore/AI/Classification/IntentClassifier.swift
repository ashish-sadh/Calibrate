import Foundation

/// LLM-driven intent classification + tool calling.
/// Pure (nonisolated) parts live here so tests on macOS can exercise the
/// classifier without an iOS simulator. The MainActor-bound methods that
/// reach into `ConversationState` / `LocalAIService` live in the Drift app.
public enum IntentClassifier {

    // MARK: - Intent Types

    public struct ClassifiedIntent: Sendable {
        public let tool: String
        public let params: [String: String]
        public let confidence: String

        public init(tool: String, params: [String: String], confidence: String) {
            self.tool = tool
            self.params = params
            self.confidence = confidence
        }
    }

    public enum ClassifyResult: Sendable {
        case toolCall(ClassifiedIntent)
        case text(String)
    }

    // MARK: - System Prompts (router + intelligence split)

    /// Tight router prompt for the small model (SmolLM 360M, 8K context).
    /// Used by `classifyFull` when the active LocalAIService backend is the
    /// small tier. Every token must earn its place — see token-ceiling test.
    public static let routerPrompt: String = """
    Health app. Reply JSON tool call or short text. Fix typos, word numbers, slang.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) log_weight(value,unit?) weight_info(query?) start_workout(name?) log_activity(name,duration?) exercise_info(query?) sleep_recovery(period?) mark_supplement(name) supplements() set_goal(target,unit?,goal_type?) delete_food(entry_id?,name?) edit_meal(entry_id?,meal_period?,action,target_food?,new_value?) body_comp() glucose() biomarkers() navigate_to(screen) add_medication(name,brand?,dose,unit?,schedule?,reminder_time?,start_date?) log_medication(name,dose?,unit?) cross_domain_insight(metric_a,metric_b,window_days?) cross_domain_pattern_detector(window_days?) weight_trend_prediction() supplement_insight(supplement?,window_days?) food_timing_insight(window_days?) sleep_food_correlation(window_days?) exercise_volume_summary(window_days?) medication_info(medication?,window_days?) cycle_biomarker_correlation(biomarker?,window_days?) protein_consistency_vs_recovery(window_days?)
    <recent_entries>: match user's row reference (ordinal/calories/meal/"just logged") → entry_id. Default: name/target_food.
    Rules: never invent health data — call a tool. "calories in X"→food_info (not log_food). log_food when user ate/had OR said log/add/track/record with a named food. Bare "log lunch/breakfast/dinner" (no food)→ask what they had. "search/find X in my logs"→food_info, not log_food. summary/intake/macros/micronutrients(fiber/sodium/sugar)→food_info. calorie/protein/carb/fat goal progress/hitting/on track→food_info. weight trend / "on track for my goal" / weight history / "how much have I lost"→weight_info. ONLY "when will I reach my goal weight" (ETA prediction)→weight_trend_prediction. body fat/lean mass/DEXA→body_comp. blood sugar/glucose spike→glucose. lab results/biomarkers/cholesterol→biomarkers. sleep/HRV→sleep_recovery. "go to X"/"open X"→navigate_to. supplements() for any supplement status question (never text). mark_supplement when user took/had one. "when did I last take X"/"last dose"/"how often do I take X"→medication_info. Medications: "took my X"/"injected X"/"log my X"→log_medication (a single dose). "I'm on X"/"started X"/"prescribed X"/"add X to my meds"→add_medication (new profile). Never use log_food for meds.
    Act when user names food/supplement/exercise/weight/screen. Ask only when no object (bare "log"/"track"/"add") or two tools fit.
    "had biryani"→{"tool":"log_food","name":"biryani"}
    "I had 2 to 3 banans"→{"tool":"log_food","name":"banana","servings":"3"}
    "chipotle bowl 3000 cal 30p 45c 67f"→{"tool":"log_food","name":"chipotle bowl","calories":"3000","protein":"30","carbs":"45","fat":"67"}
    "calories left"→{"tool":"food_info","query":"calories left"}
    "calories in samosa"→{"tool":"food_info","query":"calories in samosa"}
    "how am I doing"→{"tool":"food_info","query":"daily summary"}
    "am I hitting my protein goal"→{"tool":"food_info","query":"protein goal"}
    "set protein target 150g"→{"tool":"set_goal","target":"150","goal_type":"protein"}
    "log 2 eggs"→{"tool":"log_food","name":"egg","servings":"2"}
    "I weigh 75 kg"→{"tool":"log_weight","value":"75","unit":"kg"}
    "start push day"→{"tool":"start_workout","name":"push day"}
    "did yoga for like half an hour"→{"tool":"log_activity","name":"yoga","duration":"30"}
    "took vitamin d"→{"tool":"mark_supplement","name":"vitamin d"}
    "took my metformin"→{"tool":"log_medication","name":"metformin"}
    "took my ozempic 0.5mg"→{"tool":"log_medication","name":"ozempic","dose":"0.5","unit":"mg"}
    "I'm on Wegovy"→{"tool":"add_medication","name":"semaglutide","brand":"Wegovy","dose":"0.25","unit":"mg","schedule":"weekly"}
    "started ozempic 0.5mg weekly"→{"tool":"add_medication","name":"semaglutide","brand":"Ozempic","dose":"0.5","unit":"mg","schedule":"weekly"}
    "add metformin 500mg daily"→{"tool":"add_medication","name":"metformin","dose":"500","unit":"mg","schedule":"daily"}
    "did I take my vitamins"→{"tool":"supplements"}
    "any glucose spikes"→{"tool":"glucose"}
    "my hrv today"→{"tool":"sleep_recovery","query":"hrv"}
    "set my goal to one sixty"→{"tool":"set_goal","target":"160","unit":"lbs"}
    "delete last"→{"tool":"delete_food"}
    "undo my last food log"→{"tool":"delete_food"}
    "skipping lunch today"→Got it — tracking your fast.
    "remove rice from lunch"→{"tool":"edit_meal","meal_period":"lunch","action":"remove","target_food":"rice"}
    "update oatmeal in breakfast to 200g"→{"tool":"edit_meal","meal_period":"breakfast","action":"update_quantity","target_food":"oatmeal","new_value":"200g"}
    "swap chicken for tofu in dinner"→{"tool":"edit_meal","meal_period":"dinner","action":"replace","target_food":"chicken","new_value":"tofu"}
    <recent_entries> "42|lunch|rice|180cal|3m": "delete the rice"→{"tool":"delete_food","entry_id":"42"}. id 7: "2 servings"→{"tool":"edit_meal","entry_id":"7","action":"update_quantity","new_value":"2"}.
    "when will I reach my goal weight"→{"tool":"weight_trend_prediction"}
    "did I lose weight on workout days"→{"tool":"cross_domain_insight","metric_a":"weight","metric_b":"workout_volume"}
    "glucose vs carbs last week"→{"tool":"cross_domain_insight","metric_a":"glucose_avg","metric_b":"carbs","window_days":"7"}
    "what patterns do you see"→{"tool":"cross_domain_pattern_detector"}
    "how consistent am I with creatine"→{"tool":"supplement_insight","supplement":"creatine"}
    "when do I usually eat"→{"tool":"food_timing_insight"}
    "does eating late affect my sleep"→{"tool":"sleep_food_correlation"}
    "is my protein affecting my recovery"→{"tool":"protein_consistency_vs_recovery"}
    "does my iron drop during my period"→{"tool":"cycle_biomarker_correlation","biomarker":"iron"}
    "how's my training volume this week"→{"tool":"exercise_volume_summary"}
    "how many sets did I do for legs"→{"tool":"exercise_volume_summary"}
    "show me my weight chart"→{"tool":"navigate_to","screen":"weight"}
    "is it okay to take fish oil on an empty stomach"→Fish oil is generally fine with or without food.
    "what's my stress level"→Stress isn't tracked — try sleep or HRV for recovery signals.
    "log lunch"→What did you have for lunch?
    "hi"→Hi! How can I help?
    "log"→What would you like to log — food, weight, or a workout?
    If chat context shows "What did you have for lunch?" and user says "rice and dal"→{"tool":"log_food","name":"rice, dal"}
    JSON when ready. Ask if missing details. Text for chat.
    """

    /// Richer prompt for the intelligence model (Gemma 4 e2b, 128K context).
    /// Built as `routerPrompt + intelligenceExtras` so router updates auto-
    /// propagate. Adds multi-turn nuance, edge-case patterns, and tighter
    /// disambiguation that SmolLM can't fit / can't use.
    public static let intelligencePrompt: String = routerPrompt + intelligenceExtras

    /// Extras appended to routerPrompt for the intelligence model. Cap at
    /// ~5K chars so total stays under the 12K intelligencePrompt ceiling
    /// — well below Gemma 4's 128K context window, leaving headroom for
    /// chat history + recent_entries context + user input.
    private static let intelligenceExtras: String = """


    Multi-turn nuance:
    - "and X too"/"also add Y" after confirmed food → log_food for new item only. E.g. "Logged eggs." + "also add toast" → {"tool":"log_food","name":"toast"}.
    - "no wait, X" / "actually, X" / "I meant X" → user is contradicting prior turn. If prior was a log, undo via {"tool":"delete_food","name":"<prior food>"} then log X. If prior was a question, re-answer with the new context.
    - Topic switch ("how was my sleep" after a food turn) → ignore food context entirely. Pick the new topic's tool.
    - "yes" / "confirm" / "go ahead" after assistant asked a yes/no → carry prior intent, set the appropriate confirmation field (e.g. log_weight after value preview).
    - Empty / unclear answer to follow-up question ("uh", "hmm", "idk") → ask a tighter, more specific clarifier rather than guessing.

    Edge cases for log_food:
    - Quantity ranges ("2 to 3 eggs", "like 5 or 6 chips") → use the upper bound as servings.
    - Multi-item meals ("eggs and toast and oj") → log_food name="eggs, toast, oj" (comma-separated, single call).
    - Hedged voice input ("um, I had like, two eggs I guess") → strip filler words; log_food name=egg, servings=2.
    - Brand + food ("starbucks oat latte") → keep brand in name as-is.
    - Time-relative ("yesterday I had biryani") → log_food still triggers; the date-shift is handled downstream.
    - Quantity in name ("paneer biryani 200g") → log_food name="paneer biryani", amount="200g".
    - "I ate the rest" / "finished it" → ask "finished what?" if no recent food in context; else delete_food to inverse-log if user is correcting.

    Disambiguation deep-dive:
    - "how am I doing" / "give me a check-in" → food_info (daily summary). Default-broad → food_info.
    - "how am I doing on weight" → weight_info. The qualifier wins.
    - "calorie X" wins toward food_info even if "weight" is in history.
    - "X this week"→info tool (food_info/weight_info/sleep_recovery/exercise_info). Insight tools only for explicit "trend/pattern/correlation".
    - cross_domain_insight only fires for explicit two-metric phrasing ("X vs Y", "did X affect Y", "correlation between X and Y"). For open-ended "what patterns / any insights / anything interesting"→cross_domain_pattern_detector instead.
    - "how's my recovery" / "am I recovered" / "recovery score" → sleep_recovery (HRV + sleep quality is the recovery signal). "muscle recovery" / "how recovered are my muscles" → exercise_info.
    - Medications: mark_supplement always (adherence). If no clear adherence value ("I'm on chemo"), reply as text.

    Recovery patterns:
    - If two tools fit nearly equally, prefer the safer one: info > log (don't log without clear intent), supplements() > mark_supplement, food_info > delete_food.
    - No matching tool ("what's the weather") → reply as text, never invent a tool call.
    "I plan to have idli tomorrow morning"→{"tool":"chat"}

    Common failure clusters (Stage 1 routing):
    - State/symptom + meal-word: a meal word alone is NOT a log signal when paired with skipping/fasting/feeling/haven't-eaten. "skipping lunch today"/"I'm fasting"/"feeling bloated after dinner" → reply as text, never log_food. Negated/absence verbs ("haven't eaten", "didn't eat", "missed breakfast", "no food today") also → text, never log_food. NEVER log_food with name="nothing"/"none"/"food"/an empty value — if there is no concrete food, ask or reply text.
    "I haven't eaten all day"→Want to log something now, or tracking a fast?
    "didn't eat breakfast"→Got it — skipping breakfast today.
    - Indirect delete phrasing: "undo my last food log"/"take back that last entry"/"oops, remove that last food"/"I made a mistake with my last food entry"/"cancel that food log" → {"tool":"delete_food"}.
    - Supplement timing/advice (not intake): timing-question phrasings ("what time should I take X", "when should I take X", "before/after meal", "with food", "on an empty stomach") → text advice, NEVER mark_supplement / supplement_insight / log_food. mark_supplement is only for past-tense intake ("took X", "had my X"). Supplement status questions ("supplement status", "did I take my X", "what supplements am I missing") → {"tool":"supplements"}, never log_food.
    "what time should I take vitamin D"→Morning is fine for most people.
    "should I take creatine before workout"→Either works — post-workout is most common.
    - Supplement nouns (fish oil, omega 3, magnesium, zinc, creatine, multivitamin) taken past-tense → mark_supplement, never log_food/log_medication (meds = prescription drugs).
    "had my fish oil today"→{"tool":"mark_supplement","name":"fish oil"}
    "just had my omega 3"→{"tool":"mark_supplement","name":"omega 3"}
    "took magnesium before bed"→{"tool":"mark_supplement","name":"magnesium"}
    - Past/present weight Qs → weight_info (see Rules). Bare "my goal" = weight goal. weight_history is not a tool.
    "what is my weight trend"→{"tool":"weight_info","query":"trend"}
    "weight history this month"→{"tool":"weight_info","query":"history"}
    "how much have I lost this week"→{"tool":"weight_info","query":"lost this week"}
    "am I on track for my goal"→{"tool":"weight_info","query":"goal"}

    Common failure clusters (Stage 3 domain extraction):
    - Implicit sleep complaints: rough night / short-hours / felt-awful phrasing routes to sleep, not food. "rough night last night"/"only got 4 hrs"/"woke up feeling awful"/"didn't sleep well" → {"tool":"sleep_recovery"}.
    - Multi-item no-comma meal: comma-join the items into a single log_food name. "had eggs toast and coffee this morning"→{"tool":"log_food","name":"eggs, toast, coffee"}. "ate rice dal and roti for lunch"→{"tool":"log_food","name":"rice, dal, roti"}.

    JSON ALWAYS uses double-quoted keys + values. Single quotes / bare keys are invalid.
    """

    /// Backward-compat alias. Returns routerPrompt by default — code that
    /// needs the active prompt should call `activeSystemPrompt(backend:)`.
    public static var systemPrompt: String { routerPrompt }

    /// Picks the right prompt for the active backend. The intelligence
    /// prompt has ~3-4× more tokens; only worth shipping when the model
    /// can actually leverage it (Gemma 4 / large tier).
    public static func activeSystemPrompt(isLargeModel: Bool) -> String {
        isLargeModel ? intelligencePrompt : routerPrompt
    }

    /// Picks the right prompt for the active backend type. Remote backends
    /// (cloud BYOK) get `remotePrompt` — strict brevity targets baked in to
    /// reshape verbose cloud-LLM defaults toward Drift's terse house style.
    /// On-device backends (local llama.cpp + Apple Foundation Models) share
    /// `intelligencePrompt` — same role, same prompt-shape constraints,
    /// validated against FM during the #662 eval.
    public static func activeSystemPrompt(backend: AIBackendType) -> String {
        switch backend {
        case .remote: return remotePrompt
        case .llamaCpp, .mlx, .foundationModels: return intelligencePrompt
        }
    }

    /// Prompt for remote BYOK backends (Anthropic / OpenAI / Gemini).
    /// `intelligencePrompt + remoteExtras`. Cloud LLMs default to verbose;
    /// the extras enforce Drift's terse house style and the inline-card
    /// photo flow protocol. Hard-capped at 16K chars (token-ceiling test).
    public static let remotePrompt: String = intelligencePrompt + remoteExtras

    /// Extras layered on top of intelligencePrompt for cloud backends.
    /// Three jobs: (1) reshape verbose defaults toward Drift's terse house
    /// style; (2) describe the inline-card / propose_meal protocol for
    /// photo-attached conversations; (3) clamp output structure (no
    /// markdown, no preamble, no closing flourishes). Keep under ~3K chars
    /// so total remotePrompt stays under the 16K ceiling.
    private static let remoteExtras: String = """


    Brevity is the bar. Cloud models default to verbose; here you write like a friend texting:
    - Direct answer: 5–15 words. "You've had 67g protein, 53g to go."
    - Status / summary: 15–30 words. "On track — 1.8kg lost in 3 weeks, ~10 weeks to your 72kg goal."
    - Photo description for a meal card: 10–25 words. The card carries the macros — DON'T repeat them in prose.
    - Clarification question: under 15 words. ONE question per turn, never two.
    - Greeting / conversational: 5–10 words.
    - Hard ceiling: 50 words per response. If you need more, ask a clarifying question instead.
    - No headers, no bullet lists, no markdown. No preamble ("Sure!", "Let me check..."). No closing flourishes ("Hope this helps!"). Skip the throat-clearing. End on the data.

    Photo-attached conversational logging:
    - When a photo arrives, identify foods, ask ONE clarifying question per turn. Don't itemize macros in prose — emit a propose_meal tool call. The UI renders an inline card the user can edit, regenerate, or confirm.
    - propose_meal schema: {"tool":"propose_meal","items":[{"name":"...","grams":N,"calories":N,"protein":N,"carbs":N,"fat":N}, ...]}. One tool call per turn; the card replaces in place.
    - User talks back ("actually 2 parathas not 1") → emit a fresh propose_meal with the corrected items. Never log_food until the user confirms.
    - User confirms ("log it" / "yes" / taps ✓) → emit one log_food per item, batched in a single turn.
    - New photo → discard prior proposal entirely. Don't merge with the old card.

    Tool-call format: native function-calling per provider (Anthropic tool_use / OpenAI function_call / Gemini function_declarations). Drift normalizes them to {"tool":"...", "key":"val"}. Keep argument keys exactly as listed in the tools registry above — the parser is strict about names.

    JSON ALWAYS uses double-quoted keys + values. Single quotes / bare keys are invalid.
    """

    // MARK: - Recent-Entries Triggers

    /// Trigger tokens that switch on recent-entries context injection. Kept
    /// narrow to avoid leaking the window into unrelated turns where the
    /// tokens would just waste budget.
    public static let deleteEditTriggers: [String] = [
        "delete", "remove", "undo", "edit", "change", "update",
        "replace", "swap", "the one", "the first", "the second",
        "the last", "the 500", "just logged", "just added",
        "instead", "actually i had", "actually i took", "no, i had", "no i had",
        "wait it was", "wait, it was", "no, that was", "no that was",
        "that was actually", "replace that with", "not that"
    ]

    /// Heuristic: does this message plausibly reference a recent entry?
    public static func needsRecentEntries(_ message: String) -> Bool {
        let lower = message.lowercased()
        return deleteEditTriggers.contains(where: { lower.contains($0) })
    }

    // MARK: - Build User Message

    /// Build the user message with optional history context. Deterministic, test-friendly.
    /// The MainActor-aware variant in the Drift app injects recent-entries context.
    public static func buildUserMessage(message: String, history: String) -> String {
        composeUserMessage(message: message, history: history, recentBlock: nil)
    }

    /// Pure composer. Order of precedence: `<recent_entries>` → profile → `Chat:` → `User:`.
    /// Falls back to the bare message when no context applies.
    public static func composeUserMessage(
        message: String, history: String, recentBlock: String?,
        literalHint: String? = nil, profileContext: String? = nil
    ) -> String {
        if recentBlock == nil && history.isEmpty && literalHint == nil && profileContext == nil {
            return message
        }
        var parts: [String] = []
        if let recentBlock { parts.append(recentBlock) }
        if let profileContext { parts.append(profileContext) }
        if !history.isEmpty { parts.append("Chat:\n\(String(history.prefix(400)))") }
        if let literalHint { parts.append("Hint: \(literalHint)") }
        parts.append("User: \(message)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Parse Response

    /// Map raw LLM response string to a ClassifyResult.
    public static func mapResponse(_ response: String?) -> ClassifyResult? {
        guard let response else { return nil }
        if let intent = parseResponse(response) {
            return .toolCall(intent)
        }
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return .text(cleaned)
    }

    /// Near-miss tool names the model occasionally invents (e.g. Gemma emitting
    /// "weight_history" for "weight history this month"). Mapped to the real
    /// registered tool instead of failing downstream as "unknown tool".
    static let hallucinatedToolAliases: [String: String] = [
        "weight_history": "weight_info",
        "weight_trend": "weight_info",
    ]

    /// Parse LLM response into intent. Returns nil for non-tool-call responses.
    public static func parseResponse(_ response: String) -> ClassifiedIntent? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}"),
              jsonStart <= jsonEnd else {
            return nil
        }

        let jsonStr = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String,
              !tool.isEmpty else {
            return nil
        }

        var params: [String: String] = [:]
        for (key, value) in json where key != "tool" {
            if let str = value as? String {
                params[key] = str
            } else if let arr = value as? [String] {
                params[key] = arr.joined(separator: ", ")
            } else if let num = value as? Int {
                params[key] = "\(num)"
            } else if let num = value as? Double {
                params[key] = "\(num)"
            }
        }

        return ClassifiedIntent(
            tool: hallucinatedToolAliases[tool] ?? tool,
            params: params,
            confidence: json["confidence"] as? String ?? "high"
        )
    }

    // MARK: - Timeout Helper

    public static func withTimeout<T: Sendable>(seconds: Int, operation: @Sendable @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
