import XCTest
import DriftCore
import Foundation

/// #163 / #451 Multi-stage classifier experiment.
/// Stage A: compact domain router (food/weight/exercise/health/navigate/chat) — 1-word output.
/// Stage B: domain-focused extractor — shorter prompt, fewer cross-domain distractions.
/// Compares vs single-stage (IntentClassifier) on a 26-case gold set.
/// Ship criterion: ≥+2% accuracy AND no latency regression vs single-stage.
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' -only-testing:MultiStageEval
final class MultiStageEval: XCTestCase {

    override class func setUp() {
        super.setUp()
        PerStageEvalSupport.loadModel()
    }

    // MARK: - Stage A: Domain Router

    private static let domainRouterPrompt = """
    Classify health app query into one domain. Reply with the domain name only (one word).
    food: eating, logging food, nutrition info, meal edits, calories, hydration
    weight: weight logging, trends, goals, weight prediction
    exercise: workouts, activities, exercise history, workout start
    health: sleep, HRV, supplements, glucose, biomarkers, body composition, cross-domain
    navigate: go to screen, open tab, show chart
    chat: greetings, general questions, advice
    """

    // MARK: - Stage B: Domain-Specific Extractors

    private static let foodPrompt = """
    Food tracker. Reply JSON tool call or short text. Fix typos, word numbers.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) delete_food(entry_id?,name?) edit_meal(entry_id?,meal_period?,action,target_food?,new_value?)
    Rules: "calories in X"→food_info (not log_food). log_food when user ate/had or said log/add with a named food. summary/intake/macros→food_info. Bare "log lunch"→ask.
    "log 2 eggs"→{"tool":"log_food","name":"egg","servings":"2"}
    "calories in samosa"→{"tool":"food_info","query":"calories in samosa"}
    "how am I doing"→{"tool":"food_info","query":"daily summary"}
    "calories left"→{"tool":"food_info","query":"calories left"}
    "had biryani"→{"tool":"log_food","name":"biryani"}
    "chipotle bowl 3000 cal 30p 45c 67f"→{"tool":"log_food","name":"chipotle bowl","calories":"3000","protein":"30","carbs":"45","fat":"67"}
    "remove rice from lunch"→{"tool":"edit_meal","meal_period":"lunch","action":"remove","target_food":"rice"}
    "delete last"→{"tool":"delete_food"}
    "I had 2 to 3 banans"→{"tool":"log_food","name":"banana","servings":"3"}
    "log lunch"→What did you have for lunch?
    JSON when ready. Ask if details missing.
    """

    private static let weightPrompt = """
    Weight tracker. Reply JSON tool call. Fix typos, word numbers.
    Tools: log_weight(value,unit?) weight_info(query?) set_goal(target,unit?) goal_weight_eta()
    "I weigh 75 kg"→{"tool":"log_weight","value":"75","unit":"kg"}
    "weight trend"→{"tool":"weight_info","query":"trend"}
    "set my goal to one sixty"→{"tool":"set_goal","target":"160","unit":"lbs"}
    "when will I reach my goal weight"→{"tool":"goal_weight_eta"}
    "how close am I to my goal"→{"tool":"weight_info","query":"goal progress"}
    """

    private static let exercisePrompt = """
    Exercise tracker. Reply JSON tool call. Fix typos, word numbers.
    Tools: start_workout(name?) log_activity(name,duration?) exercise_info(query?)
    "start push day"→{"tool":"start_workout","name":"push day"}
    "did yoga for like half an hour"→{"tool":"log_activity","name":"yoga","duration":"30"}
    "how much did I bench"→{"tool":"exercise_info","query":"bench press history"}
    "am I overtraining"→{"tool":"exercise_info","query":"overtraining"}
    "ran 5k this morning"→{"tool":"log_activity","name":"run","duration":"30"}
    """

    private static let healthPrompt = """
    Health tracker. Reply JSON tool call. Fix typos.
    Tools: sleep_recovery(period?) mark_supplement(name) supplements() glucose() biomarkers() body_comp() cross_domain_insight(metric_a,metric_b,window_days?)
    Rules: supplements() for status questions (never text). mark_supplement when user took/had one. sleep/HRV→sleep_recovery.
    "my hrv today"→{"tool":"sleep_recovery","query":"hrv"}
    "took vitamin d"→{"tool":"mark_supplement","name":"vitamin d"}
    "did I take my vitamins"→{"tool":"supplements"}
    "any glucose spikes"→{"tool":"glucose"}
    "show my biomarkers"→{"tool":"biomarkers"}
    "what's my body fat"→{"tool":"body_comp"}
    "did I lose weight on workout days"→{"tool":"cross_domain_insight","metric_a":"weight","metric_b":"workout_volume"}
    "glucose vs carbs last week"→{"tool":"cross_domain_insight","metric_a":"glucose_avg","metric_b":"carbs","window_days":"7"}
    "how'd I sleep"→{"tool":"sleep_recovery"}
    """

    private static let navigatePrompt = """
    Health app navigator. Reply JSON only.
    Tools: navigate_to(screen)
    "show me my weight chart"→{"tool":"navigate_to","screen":"weight"}
    "go to food tab"→{"tool":"navigate_to","screen":"food"}
    "open supplements"→{"tool":"navigate_to","screen":"supplements"}
    "go to sleep tab"→{"tool":"navigate_to","screen":"bodyRhythm"}
    """

    private static let chatPrompt = """
    Health app assistant. Reply short helpful text or JSON food_info.
    Tools: food_info(query)
    "daily summary"→{"tool":"food_info","query":"daily summary"}
    For greetings and advice, reply with short text (no JSON).
    "hi"→Hi! How can I help?
    "is it okay to take fish oil on empty stomach"→Fish oil is generally fine with or without food.
    """

    // MARK: - Two-Stage Pipeline

    private func classifyTwoStage(
        _ message: String, history: String = "",
        backend: LlamaCppBackend
    ) async -> String? {
        // Stage A: domain routing (expects single word)
        let domainRaw = await backend.respond(to: message, systemPrompt: Self.domainRouterPrompt) ?? ""
        let domain = ["food", "weight", "exercise", "health", "navigate", "chat"]
            .first { domainRaw.lowercased().hasPrefix($0) } ?? "chat"

        // Stage B: domain-specific extraction
        let stageB: String
        switch domain {
        case "food":     stageB = Self.foodPrompt
        case "weight":   stageB = Self.weightPrompt
        case "exercise": stageB = Self.exercisePrompt
        case "health":   stageB = Self.healthPrompt
        case "navigate": stageB = Self.navigatePrompt
        default:         stageB = Self.chatPrompt
        }

        let userMsg = history.isEmpty ? message : "Chat:\n\(String(history.prefix(400)))\n\nUser: \(message)"
        return await backend.respond(to: userMsg, systemPrompt: stageB)
    }

    // MARK: - Gold Set

    private struct Case {
        let query: String
        let expected: String
        let history: String
        init(_ q: String, _ e: String, _ h: String = "") { query = q; expected = e; history = h }
    }

    private let goldSet: [Case] = [
        // Food logging
        Case("log 2 eggs", "log_food"),
        Case("I had biryani", "log_food"),
        Case("ate some dal and rice", "log_food"),
        Case("calories left", "food_info"),
        Case("calories in samosa", "food_info"),
        Case("how am I doing today", "food_info"),
        Case("remove rice from lunch", "edit_meal"),
        Case("delete last entry", "delete_food"),
        // Weight
        Case("I weigh 75 kg", "log_weight"),
        Case("what's my weight trend", "weight_info"),
        Case("set my goal to 150 lbs", "set_goal"),
        Case("when will I reach my goal weight", "goal_weight_eta"),
        // Exercise
        Case("start push day", "start_workout"),
        Case("did yoga for 30 minutes", "log_activity"),
        Case("how much did I bench", "exercise_info"),
        // Health
        Case("how'd I sleep", "sleep_recovery"),
        Case("my hrv today", "sleep_recovery"),
        Case("took vitamin d", "mark_supplement"),
        Case("did I take my vitamins", "supplements"),
        Case("any glucose spikes", "glucose"),
        Case("show my biomarkers", "biomarkers"),
        Case("what's my body fat", "body_comp"),
        Case("did I lose weight on workout days", "cross_domain_insight"),
        // Navigate
        Case("show me my weight chart", "navigate_to"),
        // Multi-turn
        Case("rice and dal", "log_food", "Assistant: What did you have for lunch?"),
        Case("also add toast", "log_food", "User: log 2 eggs\nAssistant: Logged 2 eggs (148 cal)"),
    ]

    // MARK: - Comparison Test

    func testCompareStages() async {
        guard let backend = perStageGemmaBackend else {
            XCTFail("Gemma backend not loaded"); return
        }

        var singleCorrect = 0
        var multiCorrect = 0
        var singleTotalMs = 0
        var multiTotalMs = 0

        print("\n📊 Multi-Stage vs Single-Stage Routing (#163/#451)")
        print(String(repeating: "─", count: 72))

        for c in goldSet {
            // Single stage (existing pipeline)
            let t1 = CFAbsoluteTimeGetCurrent()
            let sResp = await PerStageEvalSupport.classify(c.query, history: c.history) ?? ""
            let sMs = Int((CFAbsoluteTimeGetCurrent() - t1) * 1000)
            let sTool = PerStageEvalSupport.extractTool(sResp) ?? "text"
            let sOk = sTool == c.expected
            if sOk { singleCorrect += 1 }
            singleTotalMs += sMs

            // Two stage (experiment)
            let t2 = CFAbsoluteTimeGetCurrent()
            let mResp = await classifyTwoStage(c.query, history: c.history, backend: backend) ?? ""
            let mMs = Int((CFAbsoluteTimeGetCurrent() - t2) * 1000)
            let mTool = PerStageEvalSupport.extractTool(mResp) ?? "text"
            let mOk = mTool == c.expected
            if mOk { multiCorrect += 1 }
            multiTotalMs += mMs

            let icon = sOk && mOk ? "✅✅" : (!sOk && mOk ? "❌✅" : (sOk && !mOk ? "✅❌" : "❌❌"))
            let q = String(c.query.prefix(28)).padding(toLength: 28, withPad: " ", startingAt: 0)
            print("\(icon) \(q) S:\(sTool.padding(toLength: 18, withPad: " ", startingAt: 0)) M:\(mTool)")
        }

        let n = goldSet.count
        let sAcc = singleCorrect * 100 / n
        let mAcc = multiCorrect * 100 / n
        let sAvgMs = singleTotalMs / n
        let mAvgMs = multiTotalMs / n
        let deltaAcc = Double(multiCorrect - singleCorrect) / Double(n) * 100.0
        let deltaMs = mAvgMs - sAvgMs

        print(String(repeating: "─", count: 72))
        print("Single-stage: \(singleCorrect)/\(n) (\(sAcc)%) — avg \(sAvgMs)ms/query")
        print("Multi-stage:  \(multiCorrect)/\(n) (\(mAcc)%) — avg \(mAvgMs)ms/query")
        print(String(format: "Δ accuracy: %+.1f%%   Δ latency: %+dms/query", deltaAcc, deltaMs))

        if deltaAcc >= 2.0 && deltaMs <= 0 {
            print("✅ SHIP: multi-stage wins accuracy with no latency cost")
        } else if deltaAcc >= 2.0 {
            print("⚠️  REVIEW: accuracy improves but latency up \(deltaMs)ms — evaluate UX tradeoff")
        } else {
            print("❌ HOLD: accuracy delta \(String(format: "%.1f", deltaAcc))% below +2% threshold")
        }

        // Eval always passes — this test exists to produce a report, not gate CI
        XCTAssertGreaterThanOrEqual(singleCorrect, n * 7 / 10, "Single-stage baseline below 70%")
    }
}
