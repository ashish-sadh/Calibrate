import Foundation

// MARK: - Tool Ranker

/// Lightweight keyword-based tool ranking. Scores each tool against the query,
/// returns top N relevant tools for the LLM prompt. Keeps token budget tight.
@MainActor
public enum ToolRanker {

    // MARK: - Public API

    /// Score and return the top N tools most relevant to the query.
    public static func rank(query: String, screen: AIScreen, topN: Int = 4) -> [ToolSchema] {
        let lower = query.lowercased()
        let words = Set(lower.split(separator: " ").map(String.init))
        let intent = classifyIntent(lower, words: words)

        var scores: [(tool: ToolSchema, score: Float)] = []
        for tool in ToolRegistry.shared.allTools() {
            guard let profile = profiles[tool.name] else { continue }
            let score = scoreProfile(profile, query: lower, words: words, intent: intent, screen: screen)
            if score > 0 { scores.append((tool, score)) }
        }

        scores.sort { $0.score > $1.score }
        var result = scores.prefix(topN).map(\.tool)

        // Pad with screen defaults if too few matches
        if result.count < 2 {
            for name in screen.defaultTools where result.count < 2 {
                if let tool = ToolRegistry.shared.tool(named: name),
                   !result.contains(where: { $0.name == name }) {
                    result.append(tool)
                }
            }
        }

        return result
    }

    /// Tiny extraction prompt (~100 tokens). LLM just maps query → tool call JSON.
    /// No context, no history, no examples — pure normalization.
    public static func quickExtractPrompt(query: String, screen: AIScreen) -> (system: String, user: String) {
        let tools = rank(query: query, screen: screen, topN: 3)
        let toolLines = tools.map { t in
            let params = t.parameters.map { "\($0.name):\($0.type)" }.joined(separator: ", ")
            return params.isEmpty ? t.name : "\(t.name)(\(params))"
        }

        let system = """
        Map the user message to a tool call. Output ONLY JSON: {"tool":"name","params":{"key":"value"}}
        If no tool fits, output: {"tool":"none"}
        Tools: \(toolLines.joined(separator: ", "))
        """

        return (system, query)
    }

    /// Try to pick a tool purely from keyword rules. Returns a ToolCall if confident.
    /// High confidence = top tool scores well AND clear gap from #2.
    public static func tryRulePick(query: String, screen: AIScreen) -> ToolCall? {
        let lower = query.lowercased()
        let words = Set(lower.split(separator: " ").map(String.init))
        let intent = classifyIntent(lower, words: words)

        let ranked = rank(query: lower, screen: screen, topN: 2)
        guard let top = ranked.first, let topProfile = profiles[top.name] else { return nil }

        let topScore = scoreProfile(topProfile, query: lower, words: words, intent: intent, screen: screen)

        var secondScore: Float = 0
        if ranked.count > 1, let secondProfile = profiles[ranked[1].name] {
            secondScore = scoreProfile(secondProfile, query: lower, words: words, intent: intent, screen: screen)
        }

        // Need high confidence: score ≥ 4.0 and clear gap ≥ 2.0 from runner-up
        guard topScore >= 4.0, topScore - secondScore >= 2.0 else { return nil }

        let params = extractParamsForTool(top, from: query)
        return ToolCall(tool: top.name, params: ToolCallParams(values: params))
    }

    /// Score a tool profile against the query.
    private static func scoreProfile(_ profile: ToolProfile, query: String, words: Set<String>,
                                      intent: Intent, screen: AIScreen) -> Float {
        var score: Float = 0
        for (keyword, weight) in profile.triggers {
            if keyword.contains(" ") {
                if query.contains(keyword) { score += weight }
            } else {
                if words.contains(keyword) { score += weight }
            }
        }
        switch intent {
        case .log: score += profile.logBoost
        case .query: score += profile.queryBoost
        case .chat: break
        }
        if let screenBoost = profile.screens[screen] { score += screenBoost }
        for anti in profile.antiKeywords {
            if words.contains(anti) { score -= 1.5 }
        }
        return score
    }

    /// Extract minimal params from the query for a tool.
    public static func extractParamsForTool(_ tool: ToolSchema, from query: String) -> [String: String] {
        var params: [String: String] = [:]
        let lower = query.lowercased()

        switch tool.name {
        case "log_food":
            if let intent = AIActionExecutor.parseFoodIntent(lower) {
                params["name"] = intent.query
                if let s = intent.servings { params["amount"] = "\(s)" }
            } else {
                params["name"] = lower
            }
        case "start_workout":
            var stripped = lower
            let workoutPrefixes = ["i want to work on ", "i want to train ", "i want to do ",
                                    "i wanna do ", "i wanna train ", "work on ", "train ",
                                    "let's do ", "lets do ", "start ", "begin "]
            for prefix in workoutPrefixes {
                if stripped.hasPrefix(prefix) { stripped = String(stripped.dropFirst(prefix.count)); break }
            }
            stripped = stripped.replacingOccurrences(of: " workout", with: "")
                .replacingOccurrences(of: " session", with: "")
                .replacingOccurrences(of: " today", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { params["name"] = stripped }
        case "log_activity":
            let activityPrefixes = ["i did ", "i went ", "just did ", "just finished ", "did "]
            var activity = lower
            for prefix in activityPrefixes {
                if activity.hasPrefix(prefix) { activity = String(activity.dropFirst(prefix.count)); break }
            }
            params["name"] = activity.trimmingCharacters(in: .whitespaces)
        case "mark_supplement":
            let supplementPrefixes = ["took my ", "took ", "had my ", "taken my "]
            var name = lower
            for prefix in supplementPrefixes {
                if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)); break }
            }
            params["name"] = name.trimmingCharacters(in: .whitespaces)
        case "log_weight":
            let pattern = #"(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let numRange = Range(match.range(at: 1), in: lower) {
                params["value"] = String(lower[numRange])
                if let unitRange = Range(match.range(at: 2), in: lower) {
                    params["unit"] = String(lower[unitRange])
                }
            }
        case "set_goal":
            let pattern = #"(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let numRange = Range(match.range(at: 1), in: lower) {
                params["target"] = String(lower[numRange])
                if let unitRange = Range(match.range(at: 2), in: lower) {
                    params["unit"] = String(lower[unitRange])
                }
            }
        case "food_info":
            // Pass the FULL query — food_info's handler classifies it (lookup vs
            // macro-intake vs suggest vs period summary) using the complete text.
            // Collapsing to a bare macro word ("protein") destroyed the distinction
            // between "what's my protein today" (intake) and "protein in chicken"
            // (lookup) — both became "protein" and resolved to the same branch. #macro-intake
            params["query"] = lower
        case "weight_info":
            params["query"] = lower
        case "exercise_info":
            params["query"] = lower
        case "sleep_recovery":
            if lower.contains("week") || lower.contains("trend") || lower.contains("last") {
                params["period"] = "week"
            }
        default:
            break
        }

        return params
    }

    /// Full prompt with context for questions that need data. (~1000 tokens)
    public static func buildPrompt(
        query: String, screen: AIScreen, context: String, history: String
    ) -> (system: String, user: String) {
        let tools = rank(query: query, screen: screen, topN: 4)
        let toolLines = tools.map { t in
            let params = t.parameters.map { "\($0.name):\($0.type)" }.joined(separator: ", ")
            return "- \(t.name)(\(params)) — \(t.description)"
        }

        let system = """
        Health assistant.
        LOGGING (ate/did/weigh/took) → JSON {"tool":"name","params":{"key":"value"}}
        QUESTION (how/what/show) → JSON info tool call
        CHAT (greeting/thanks) → short text, no JSON
        Rules: no health advice, no invented numbers, one call or short text (never both).
        "I had 2 eggs"→{"tool":"log_food","params":{"name":"eggs","amount":"2"}}
        "calories left"→{"tool":"food_info","params":{}}
        "start chest"→{"tool":"start_workout","params":{"name":"chest"}}
        "thanks"→You're welcome!
        Tools:
        \(toolLines.joined(separator: "\n"))
        """

        let truncatedContext = PromptUtils.truncateToFit(context, maxTokens: 500)
        let truncatedHistory = String(history.prefix(600))

        var userParts: [String] = []
        if !truncatedContext.isEmpty { userParts.append("Context:\n\(truncatedContext)") }
        if !truncatedHistory.isEmpty { userParts.append("Chat:\n\(truncatedHistory)") }
        userParts.append(query)

        return (system, userParts.joined(separator: "\n\n"))
    }

    // MARK: - Intent Classification

    public enum Intent { case log, query, chat }

    private static func classifyIntent(_ lower: String, words: Set<String>) -> Intent {
        let logVerbs: Set<String> = ["ate", "had", "log", "add", "took", "did", "went",
                                      "finished", "drank", "eaten", "logged", "track", "weigh", "grabbed"]
        let logPhrases = ["i had", "i ate", "i did", "i went", "just had", "just did",
                          "just finished", "log ", "took my", "had my"]
        let queryWords: Set<String> = ["how", "what", "show", "calories", "much", "many",
                                        "trend", "progress", "status", "summary", "left"]

        for phrase in logPhrases {
            if lower.contains(phrase) { return .log }
        }
        if !words.isDisjoint(with: logVerbs) { return .log }
        if !words.isDisjoint(with: queryWords) || lower.hasSuffix("?") { return .query }

        return .chat
    }

    // MARK: - Tool Profiles

    private struct ToolProfile {
        let triggers: [(String, Float)]
        let logBoost: Float
        let queryBoost: Float
        let screens: [AIScreen: Float]
        let antiKeywords: Set<String>
    }

    // swiftlint:disable function_body_length
    private static let profiles: [String: ToolProfile] = {
        var p: [String: ToolProfile] = [:]

        // --- Food ---

        p["log_food"] = ToolProfile(
            triggers: [("ate", 3), ("had", 2.5), ("log", 2), ("add", 1.5), ("eating", 2),
                       ("drank", 2), ("i had", 3), ("i ate", 3), ("just had", 3),
                       ("grabbed", 2), ("just finished", 3),
                       ("eggs", 2), ("chicken", 2), ("rice", 2), ("banana", 2), ("roti", 2),
                       ("dal", 2), ("paneer", 2), ("oatmeal", 2),
                       ("protein shake", 3.5), ("protein bar", 3),
                       ("breakfast", 1), ("lunch", 1), ("dinner", 1), ("snack", 1)],
            logBoost: 2, queryBoost: -1,
            screens: [.food: 0.6, .dashboard: 0.3],
            antiKeywords: ["sleep", "supplement", "weight", "weigh", "how", "what", "calories in", "healthy",
                           // Cardio verbs are activities, never food — stops "log a 30 minute run"
                           // from being parsed as a food search even on the .food screen (#896).
                           "run", "ran", "jog", "jogging", "jogged", "running",
                           "cycle", "cycled", "cycling", "swim", "swam", "swimming"]
        )

        p["food_info"] = ToolProfile(
            triggers: [("calories", 2.5), ("protein", 2), ("macros", 2.5), ("nutrition", 2),
                       ("diet", 1.5), ("hungry", 1.5), ("remaining", 2), ("left", 2),
                       ("calories left", 3), ("how am i doing", 3), ("on track", 2),
                       ("what should i eat", 3), ("what to eat", 2.5),
                       ("daily summary", 3.5), ("summary", 2), ("yesterday", 2.5),
                       ("weekly summary", 3), ("this week", 2.5), ("what did i eat", 3),
                       ("how are you doing", 3), ("how's my day", 3), ("suggest", 2),
                       ("meal ideas", 3), ("food ideas", 3),
                       ("sugar", 2), ("carbs today", 3), ("fat today", 3),
                       ("fiber", 2), ("how much protein", 3.5), ("how much fat", 3.5),
                       ("calories in", 3), ("estimate calories", 3.5),
                       ("protein in", 3), ("healthy", 2),
                       ("reduce fat", 2.5), ("lose fat", 2.5), ("burn fat", 2.5),
                       ("how to lose", 2.5), ("what's a good diet", 3)],
            logBoost: -1, queryBoost: 2,
            screens: [.food: 0.5, .dashboard: 0.3],
            antiKeywords: ["log", "remove", "delete", "ate", "had"]
        )

        p["copy_yesterday"] = ToolProfile(
            triggers: [("copy", 3), ("yesterday", 2.5), ("repeat", 2), ("same", 2),
                       ("same as yesterday", 4), ("copy yesterday", 4), ("repeat yesterday", 4)],
            logBoost: 1, queryBoost: 0,
            screens: [.food: 0.3],
            antiKeywords: ["what", "how"]
        )

        p["delete_food"] = ToolProfile(
            triggers: [("remove", 3), ("delete", 3), ("undo", 3),
                       ("remove the", 3.5), ("delete last", 3.5)],
            logBoost: 1, queryBoost: 0,
            screens: [.food: 0.3],
            antiKeywords: ["supplement", "weight", "workout"]
        )

        p["explain_calories"] = ToolProfile(
            triggers: [("tdee", 3), ("calculated", 2.5), ("target number", 2.5),
                       ("how are calories", 4), ("why is my target", 4),
                       ("how is my calorie", 3.5), ("calorie target", 3)],
            logBoost: 0, queryBoost: 1.5,
            screens: [.food: 0.3],
            antiKeywords: ["log", "ate", "had"]
        )

        // --- Weight ---

        p["log_weight"] = ToolProfile(
            triggers: [("weigh", 3), ("scale", 2.5), ("i weigh", 3.5), ("scale says", 3),
                       ("log weight", 3), ("my weight is", 3),
                       ("weighed in", 3.5), ("weighed myself", 3.5)],
            logBoost: 2, queryBoost: -1,
            screens: [.weight: 0.5],
            antiKeywords: ["food", "eat", "ate", "workout", "trend", "how", "progress"]
        )

        p["weight_info"] = ToolProfile(
            triggers: [("weight", 2), ("trend", 2.5), ("progress", 2), ("gaining", 2.5),
                       ("losing", 2.5), ("how's my weight", 3.5), ("am i on track", 3),
                       ("goal", 1.5), ("how much have i lost", 4), ("weight progress", 3.5),
                       ("am i losing", 3), ("compare this week", 3),
                       ("why am i not losing", 3.5), ("plateau", 3), ("not losing weight", 3.5),
                       ("how am i doing", 2), ("how are you doing", 2), ("daily summary", 2),
                       ("tdee", 3.5), ("bmr", 3.5), ("metabolism", 3), ("how many calories do i burn", 4),
                       ("explain tdee", 4), ("explain calories", 3)],
            logBoost: -1, queryBoost: 2,
            screens: [.weight: 0.5, .goal: 0.5, .dashboard: 0.2],
            antiKeywords: ["log", "set", "target", "i weigh", "scale"]
        )

        p["set_goal"] = ToolProfile(
            triggers: [("goal", 2.5), ("target", 2.5), ("set goal", 4), ("target weight", 4),
                       ("i want to weigh", 4), ("goal weight", 3)],
            logBoost: 1, queryBoost: 0,
            screens: [.weight: 0.3, .goal: 0.5],
            antiKeywords: ["how", "what", "progress"]
        )

        // --- Exercise ---

        p["start_workout"] = ToolProfile(
            triggers: [("start", 2.5), ("begin", 2.5), ("chest", 2), ("legs", 2), ("back", 1.5),
                       ("push", 1.5), ("pull", 1.5), ("arms", 1.5), ("shoulders", 1.5),
                       ("core", 1.5), ("abs", 1.5), ("glutes", 1.5), ("biceps", 1.5), ("triceps", 1.5),
                       ("upper body", 2), ("lower body", 2), ("full body", 2),
                       ("start workout", 4), ("let's do", 3), ("begin workout", 4),
                       ("want to work on", 4), ("want to train", 4), ("want to do", 3),
                       ("work on", 3), ("train", 2)],
            logBoost: 0, queryBoost: 0,
            screens: [.exercise: 0.5],
            antiKeywords: ["history", "how many", "suggest", "what should", "did", "went", "finished"]
        )

        p["exercise_info"] = ToolProfile(
            triggers: [("workout", 1.5), ("train", 2), ("exercise", 1.5), ("gym", 1.5),
                       ("lift", 1.5), ("lifts", 1.5), ("what should i train", 4), ("workout history", 3),
                       ("suggest workout", 3), ("how many workout", 3), ("recovery", 1.5),
                       ("workout count", 3.5), ("workouts this week", 3.5),
                       ("how often did i train", 4), ("how many times did i work", 4),
                       ("progress", 2), ("bench", 2.5), ("squat", 2.5), ("deadlift", 2.5),
                       ("overload", 2.5), ("overloading", 2.5), ("how's my", 2), ("stalling", 2.5)],
            logBoost: -1, queryBoost: 2,
            screens: [.exercise: 0.5],
            antiKeywords: ["start", "begin", "let's"]
        )

        p["log_activity"] = ToolProfile(
            triggers: [("yoga", 2.5), ("running", 2.5), ("swimming", 2.5), ("walked", 2.5),
                       ("cardio", 2), ("pilates", 2.5), ("cycling", 2.5), ("hiking", 2.5),
                       // Bare/inflected cardio verbs — "log a 30 minute run" was missing
                       // these, so log_food's "log" trigger won and opened a food search (#896).
                       ("run", 2.5), ("ran", 2.5), ("jog", 2.5), ("jogging", 2.5), ("jogged", 2.5),
                       ("cycle", 2.5), ("cycled", 2.5), ("swim", 2.5), ("swam", 2.5),
                       ("i did", 3), ("just finished", 3), ("went running", 3.5),
                       ("just did", 3), ("minutes", 1), ("minute", 1)],
            logBoost: 2, queryBoost: -1,
            screens: [.exercise: 0.3],
            antiKeywords: ["start", "begin", "suggest", "what"]
        )

        // --- Health ---

        p["sleep_recovery"] = ToolProfile(
            triggers: [("sleep", 3), ("recovery", 2.5), ("hrv", 3), ("tired", 2), ("energy", 1.5),
                       ("rest", 1.5), ("rested", 2), ("how'd i sleep", 4), ("am i recovered", 3.5),
                       ("heart rate", 2), ("sleep trend", 3.5), ("last night", 3), ("sleep quality", 3),
                       ("sleep score", 3), ("how was my sleep", 3.5)],
            logBoost: 0, queryBoost: 1.5,
            screens: [.bodyRhythm: 0.5],
            antiKeywords: ["food", "ate", "weight", "muscle"]
        )

        p["supplements"] = ToolProfile(
            triggers: [("supplement", 2.5), ("supplements", 2.5), ("vitamin", 2), ("vitamins", 2), ("stack", 2),
                       ("supplement status", 4), ("did i take", 3), ("what supplements", 3)],
            logBoost: 0, queryBoost: 1.5,
            screens: [.supplements: 0.5],
            antiKeywords: ["add", "took", "taken"]
        )

        p["add_supplement"] = ToolProfile(
            triggers: [("add supplement", 4), ("add vitamin", 4), ("add creatine", 4),
                       ("new supplement", 3), ("add to stack", 3), ("add fish oil", 4),
                       ("add magnesium", 4)],
            logBoost: 1, queryBoost: 0,
            screens: [.supplements: 0.3],
            antiKeywords: ["took", "taken", "status", "did i"]
        )

        p["mark_supplement"] = ToolProfile(
            triggers: [("took", 2.5), ("taken", 2), ("took my", 4), ("had my", 3),
                       ("creatine", 1.5), ("fish oil", 1.5), ("vitamin d", 1.5)],
            logBoost: 2, queryBoost: -1,
            screens: [.supplements: 0.3],
            antiKeywords: ["add", "new", "what", "status",
                           "ozempic", "semaglutide", "glp1", "glp-1",
                           "metformin", "mounjaro", "tirzepatide", "wegovy",
                           "insulin", "medication"]
        )

        p["log_medication"] = ToolProfile(
            triggers: [("medication", 2.5), ("log medication", 4.5), ("took ozempic", 4.5),
                       ("took metformin", 4.5), ("took insulin", 4), ("injected", 3),
                       ("semaglutide", 4), ("ozempic", 4), ("wegovy", 4), ("glp-1", 3.5),
                       ("glp1", 3.5), ("mounjaro", 4), ("tirzepatide", 4), ("metformin", 3.5),
                       // "took my <med>" phrases — outscores mark_supplement "took my" trigger
                       ("took my ozempic", 6.5), ("took my glp", 6.5), ("took my semaglutide", 6.5),
                       ("took my metformin", 6.5), ("took my mounjaro", 6.5), ("took my insulin", 6.5),
                       ("took my wegovy", 6.5), ("took my tirzepatide", 6.5)],
            logBoost: 2, queryBoost: -1,
            screens: [:],
            // Single-word antis (the scoring loop is word-membership only — multi-word
            // antis are dead, so we keep these tokens that actually fire). "add"/"i'm"
            // push "add metformin" / "i'm on ozempic" to add_medication; "started"/
            // "prescribed" do the same for prescription-onboarding phrasing.
            antiKeywords: ["food", "weight", "supplement", "workout", "what", "how", "when", "last", "history", "pattern", "did", "time",
                           "started", "starting", "prescribed", "add", "i'm"]
        )

        p["add_medication"] = ToolProfile(
            triggers: [("add medication", 6), ("add a medication", 6), ("add to my meds", 5.5),
                       ("started ozempic", 6), ("started wegovy", 6), ("started mounjaro", 6),
                       ("started semaglutide", 6), ("started metformin", 5.5), ("started tirzepatide", 6),
                       ("starting ozempic", 5.5), ("starting wegovy", 5.5),
                       ("i'm on ozempic", 6), ("i'm on wegovy", 6), ("i'm on mounjaro", 6),
                       ("i'm on metformin", 5.5), ("i'm on glp", 5.5), ("im on ozempic", 6),
                       // "i am on X" variants — common LLM-normalized expansion of "i'm on"
                       ("i am on ozempic", 6), ("i am on wegovy", 6), ("i am on mounjaro", 6),
                       ("i am on metformin", 5.5), ("i am on glp", 5.5),
                       ("prescribed", 4.5), ("was prescribed", 5.5), ("got prescribed", 5.5),
                       ("new prescription", 5), ("new medication", 5), ("add ozempic", 5),
                       ("add wegovy", 5), ("add metformin", 5), ("add mounjaro", 5),
                       ("add tirzepatide", 5), ("add semaglutide", 5), ("add insulin", 5)],
            logBoost: 0, queryBoost: -2,
            screens: [:],
            // "took"/"injected"/"logged" → log_medication (a single dose), not add.
            // Single-word only — see note on log_medication antis above.
            antiKeywords: ["took", "injected", "logged"]
        )

        p["medication_info"] = ToolProfile(
            triggers: [("when did i last take", 6.5), ("last dose", 5), ("last time i took", 7.5),
                       ("when did i take", 5.5), ("when did i inject", 5.5),
                       ("how often do i take", 5), ("how often am i taking", 5),
                       ("medication history", 5), ("dose history", 4.5),
                       ("my medication pattern", 4.5), ("injection history", 4.5),
                       ("last ozempic", 5), ("last metformin", 5), ("last semaglutide", 5),
                       ("last mounjaro", 5), ("last insulin", 5), ("last glp", 4.5),
                       // missed-dose adherence — beats supplement_insight for medication-framed queries
                       ("miss my medication", 6.5), ("missed my medication", 6.5),
                       ("medication dose", 5.0), ("prescription dose", 5.0),
                       ("forget my medication", 5.5), ("forgot my medication", 5.5),
                       // med name boosts — combine with phrase triggers to beat log_medication logBoost
                       ("ozempic", 2.5), ("semaglutide", 2.5), ("metformin", 2.5),
                       ("insulin", 2.5), ("mounjaro", 2.5), ("tirzepatide", 2.5),
                       ("wegovy", 2.5), ("glp-1", 2.5), ("glp1", 2.5)],
            logBoost: -2, queryBoost: 3,
            screens: [:],
            antiKeywords: ["log", "took", "injected", "add", "record"]
        )

        p["glp1_insight"] = ToolProfile(
            triggers: [("glp1 adherence", 6), ("glp-1 adherence", 6),
                       ("ozempic progress", 5.5), ("semaglutide progress", 5.5),
                       ("mounjaro progress", 5.5), ("tirzepatide progress", 5.5),
                       ("semaglutide streak", 5.5), ("ozempic streak", 5.5),
                       ("injection streak", 5.5), ("glp1 streak", 5.5),
                       ("how's my glp", 6), ("how is my glp", 6),
                       ("glp-1 progress", 5.5), ("glp1 progress", 5.5),
                       ("since starting ozempic", 5.5), ("since starting semaglutide", 5.5),
                       ("since starting mounjaro", 5.5), ("since i started ozempic", 5.5),
                       ("weight since ozempic", 5.5), ("weight since semaglutide", 5.5),
                       ("how consistent am i with ozempic", 5), ("how consistent am i with glp", 5)],
            logBoost: -2, queryBoost: 3,
            screens: [:],
            antiKeywords: ["log", "took", "inject", "add", "when did", "last dose", "last time"]
        )

        p["glucose"] = ToolProfile(
            triggers: [("glucose", 3), ("blood sugar", 3), ("spike", 2.5), ("cgm", 3),
                       ("glucose today", 4), ("any spikes", 3.5)],
            logBoost: 0, queryBoost: 1.5,
            screens: [.glucose: 0.5],
            antiKeywords: ["food", "weight", "workout"]
        )

        p["biomarkers"] = ToolProfile(
            triggers: [("biomarker", 3), ("biomarkers", 3), ("blood test", 3), ("lab", 2.5), ("cholesterol", 3),
                       ("a1c", 3), ("lab results", 4), ("blood work", 3.5)],
            logBoost: 0, queryBoost: 1.5,
            screens: [.biomarkers: 0.5],
            antiKeywords: ["food", "weight", "workout"]
        )

        p["body_comp"] = ToolProfile(
            triggers: [("body fat", 3), ("bmi", 2.5), ("lean mass", 3), ("dexa", 3),
                       ("muscle mass", 3), ("body composition", 3), ("recomposition", 3),
                       ("how's my body fat", 4), ("muscle gained", 3.5), ("how much muscle", 3.5),
                       ("muscle", 2.0)],
            logBoost: -0.5, queryBoost: 2,
            screens: [.bodyComposition: 0.5],
            antiKeywords: ["log", "is"]
        )

        p["log_body_comp"] = ToolProfile(
            triggers: [("body fat", 2), ("bmi", 2),
                       ("body fat is", 4), ("bmi is", 4), ("my body fat", 2.5)],
            logBoost: 2, queryBoost: -1,
            screens: [.bodyComposition: 0.3],
            antiKeywords: ["how", "what", "trend", "show"]
        )

        p["supplement_insight"] = ToolProfile(
            triggers: [("adherence", 3.5), ("how consistent", 3), ("missed", 2.5), ("miss", 2.0),
                       ("supplement streak", 4), ("vitamin streak", 3.5),
                       ("how's my vitamin", 3), ("supplement insight", 4),
                       ("am i consistent", 2.5), ("consistency", 2),
                       // "did i miss" overrides logBoost penalty — net 5.5-1=4.5 beats mark_supplement 2.0
                       ("did i miss", 5.5), ("did i forget to take", 5.5),
                       ("forget to take", 4.0), ("miss any", 3.5)],
            logBoost: -1, queryBoost: 2,
            screens: [.supplements: 0.5],
            // "medication"/"prescription" prevent stealing from medication_info on adherence queries
            antiKeywords: ["add", "took", "take", "log", "medication", "prescription"]
        )

        p["food_timing_insight"] = ToolProfile(
            triggers: [("when do i eat", 4), ("meal timing", 3.5), ("late night eating", 4),
                       ("breakfast timing", 3.5), ("eating pattern", 3), ("meal times", 3),
                       ("eating schedule", 3), ("when do i usually", 3),
                       ("consistent meal", 3), ("eating late", 3.5)],
            logBoost: -1, queryBoost: 2,
            screens: [.food: 0.3],
            antiKeywords: ["log", "ate", "had"]
        )

        return p
    }()
    // swiftlint:enable function_body_length
}
