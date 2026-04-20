import XCTest
@testable import Drift

/// Isolated gold set for IntentClassifier — sprint task #161.
/// Tests deterministic JSON parsing (parseResponse/mapResponse) and StaticOverrides routing.
/// Fully deterministic: no LLM, no network. Runs in <5s.
///
/// Run: xcodebuild test -only-testing:'DriftTests/IntentClassifierGoldSetTests'
final class IntentClassifierGoldSetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            if ToolRegistry.shared.allTools().isEmpty {
                ToolRegistration.registerAll()
            }
        }
    }

    // MARK: - parseResponse: Tool Call Parsing

    func testParseResponse_FoodLogging() {
        let cases: [(json: String, tool: String, param: String, value: String)] = [
            (#"{"tool":"log_food","name":"egg","servings":"2"}"#, "log_food", "name", "egg"),
            (#"{"tool":"log_food","name":"biryani"}"#, "log_food", "name", "biryani"),
            (#"{"tool":"log_food","name":"paneer tikka masala","servings":"1"}"#, "log_food", "name", "paneer tikka masala"),
            (#"{"tool":"log_food","name":"chipotle bowl","calories":"800","protein":"40","carbs":"90","fat":"20"}"#, "log_food", "name", "chipotle bowl"),
            (#"{"tool":"log_food","name":"dal","servings":"1"}"#, "log_food", "name", "dal"),
        ]
        var correct = 0
        for (json, expectedTool, param, expectedValue) in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                print("MISS (parseResponse log_food): \(json)")
                continue
            }
            if intent.tool == expectedTool && intent.params[param] == expectedValue {
                correct += 1
            } else {
                print("WRONG (log_food): got tool=\(intent.tool) \(param)=\(intent.params[param] ?? "nil"), expected tool=\(expectedTool) \(param)=\(expectedValue)")
            }
        }
        print("📊 parseResponse food logging: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count, "All log_food JSON should parse correctly")
    }

    func testParseResponse_FoodInfo() {
        let cases: [(json: String, expectedQuery: String)] = [
            (#"{"tool":"food_info","query":"daily summary"}"#, "daily summary"),
            (#"{"tool":"food_info","query":"calories left"}"#, "calories left"),
            (#"{"tool":"food_info","query":"calories in samosa"}"#, "calories in samosa"),
            (#"{"tool":"food_info","query":"weekly summary"}"#, "weekly summary"),
            (#"{"tool":"food_info","query":"protein"}"#, "protein"),
        ]
        var correct = 0
        for (json, expectedQuery) in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                print("MISS (parseResponse food_info): \(json)")
                continue
            }
            if intent.tool == "food_info" && intent.params["query"] == expectedQuery {
                correct += 1
            } else {
                print("WRONG (food_info): got tool=\(intent.tool) query=\(intent.params["query"] ?? "nil"), expected query=\(expectedQuery)")
            }
        }
        print("📊 parseResponse food_info: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count, "All food_info JSON should parse correctly")
    }

    func testParseResponse_WeightAndExercise() {
        let cases: [(json: String, tool: String)] = [
            (#"{"tool":"log_weight","value":"75","unit":"kg"}"#, "log_weight"),
            (#"{"tool":"weight_info","query":"goal progress"}"#, "weight_info"),
            (#"{"tool":"start_workout","name":"push day"}"#, "start_workout"),
            (#"{"tool":"log_activity","name":"yoga","duration":"30"}"#, "log_activity"),
            (#"{"tool":"exercise_info","query":"muscle recovery"}"#, "exercise_info"),
        ]
        var correct = 0
        for (json, expectedTool) in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                print("MISS (parseResponse weight/exercise): \(json)")
                continue
            }
            if intent.tool == expectedTool { correct += 1 }
            else { print("WRONG: got \(intent.tool), expected \(expectedTool)") }
        }
        print("📊 parseResponse weight/exercise: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count)
    }

    func testParseResponse_HealthDomains() {
        let cases: [(json: String, tool: String)] = [
            (#"{"tool":"sleep_recovery"}"#, "sleep_recovery"),
            (#"{"tool":"sleep_recovery","query":"hrv"}"#, "sleep_recovery"),
            (#"{"tool":"mark_supplement","name":"vitamin d"}"#, "mark_supplement"),
            (#"{"tool":"supplements"}"#, "supplements"),
            (#"{"tool":"body_comp"}"#, "body_comp"),
            (#"{"tool":"glucose"}"#, "glucose"),
            (#"{"tool":"biomarkers"}"#, "biomarkers"),
        ]
        var correct = 0
        for (json, expectedTool) in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                print("MISS (parseResponse health): \(json)")
                continue
            }
            if intent.tool == expectedTool { correct += 1 }
            else { print("WRONG: got \(intent.tool), expected \(expectedTool)") }
        }
        print("📊 parseResponse health domains: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count)
    }

    func testParseResponse_NavigationAndGoals() {
        let cases: [(json: String, tool: String, screen: String?)] = [
            (#"{"tool":"navigate_to","screen":"weight"}"#, "navigate_to", "weight"),
            (#"{"tool":"navigate_to","screen":"food"}"#, "navigate_to", "food"),
            (#"{"tool":"navigate_to","screen":"exercise"}"#, "navigate_to", "exercise"),
            (#"{"tool":"set_goal","target":"160","unit":"lbs"}"#, "set_goal", nil),
            (#"{"tool":"delete_food"}"#, "delete_food", nil),
        ]
        var correct = 0
        for (json, expectedTool, expectedScreen) in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                print("MISS (parseResponse nav/goals): \(json)")
                continue
            }
            let toolOK = intent.tool == expectedTool
            let screenOK = expectedScreen == nil || intent.params["screen"] == expectedScreen
            if toolOK && screenOK { correct += 1 }
            else { print("WRONG: got tool=\(intent.tool) screen=\(intent.params["screen"] ?? "nil")") }
        }
        print("📊 parseResponse navigation/goals: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count)
    }

    // MARK: - mapResponse: Text vs Tool Call

    func testMapResponse_ToolCallDetection() {
        let toolJSON = #"{"tool":"log_food","name":"rice"}"#
        guard case .toolCall(let intent) = IntentClassifier.mapResponse(toolJSON) else {
            XCTFail("Valid JSON tool call should return .toolCall")
            return
        }
        XCTAssertEqual(intent.tool, "log_food")
        XCTAssertEqual(intent.params["name"], "rice")
    }

    func testMapResponse_TextDetection() {
        let textResponse = "What did you have for lunch?"
        guard case .text(let text) = IntentClassifier.mapResponse(textResponse) else {
            XCTFail("Text response should return .text")
            return
        }
        XCTAssertFalse(text.isEmpty)
    }

    func testMapResponse_NilOnEmpty() {
        XCTAssertNil(IntentClassifier.mapResponse(nil))
        XCTAssertNil(IntentClassifier.mapResponse(""))
        XCTAssertNil(IntentClassifier.mapResponse("   "))
    }

    func testMapResponse_MalformedJSON() {
        // Missing tool key → should return nil or .text, never crash
        let noTool = #"{"name":"rice"}"#
        let result = IntentClassifier.mapResponse(noTool)
        // Either nil or .text is acceptable — just must not crash or return .toolCall
        if case .toolCall = result {
            XCTFail("JSON without 'tool' key should not produce a toolCall")
        }
    }

    // MARK: - Supplement vs Food Disambiguation

    /// Regression: "had a protein shake" must parse as log_food, NOT mark_supplement.
    /// The 2B model was routing this to mark_supplement because the old RULES said "TOOK/HAD something".
    func testParseResponse_ProteinShakeIsFood() {
        let foodShakeCases: [(String, String)] = [
            (#"{"tool":"log_food","name":"protein shake"}"#, "protein shake"),
            (#"{"tool":"log_food","name":"protein shake","servings":"1"}"#, "protein shake"),
            (#"{"tool":"log_food","name":"whey protein shake"}"#, "whey protein shake"),
        ]
        for (json, expectedName) in foodShakeCases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Protein shake JSON should parse: \(json)")
                continue
            }
            XCTAssertEqual(intent.tool, "log_food", "Protein shake must be log_food, not mark_supplement")
            XCTAssertEqual(intent.params["name"], expectedName)
        }
    }

    /// Regression: mark_supplement JSON must still parse correctly for real supplements.
    func testParseResponse_RealSupplementsStillWork() {
        let supplementCases = [
            #"{"tool":"mark_supplement","name":"fish oil"}"#,
            #"{"tool":"mark_supplement","name":"vitamin d"}"#,
            #"{"tool":"mark_supplement","name":"creatine"}"#,
            #"{"tool":"mark_supplement","name":"omega-3"}"#,
        ]
        for json in supplementCases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Real supplement JSON should parse: \(json)")
                continue
            }
            XCTAssertEqual(intent.tool, "mark_supplement", "Real supplements must stay as mark_supplement")
            XCTAssertNotNil(intent.params["name"])
        }
    }

    /// Supplement advice queries should NOT be mark_supplement — they should use supplements() or text.
    func testParseResponse_SupplementAdviceIsNotMarkSupplement() {
        // These represent LLM responses for advice questions — should route to supplements() or text
        let adviceCases = [
            (#"{"tool":"supplements"}"#, "supplements"),
            (#"{"tool":"supplements","query":"timing"}"#, "supplements"),
        ]
        for (json, expectedTool) in adviceCases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Should parse: \(json)")
                continue
            }
            XCTAssertEqual(intent.tool, expectedTool, "Supplement advice → supplements(), not mark_supplement")
        }
        // Text responses are also acceptable for advice questions
        let textAdvice = "Take vitamin D with a meal for better absorption."
        XCTAssertNil(IntentClassifier.parseResponse(textAdvice), "Advice text should not parse as tool call")
    }

    // MARK: - Supplement Sub-Intent Disambiguation (#168)

    /// "Did I take creatine?" = STATUS → supplements()
    /// "log creatine" / "took creatine" = MARK → mark_supplement(name:)
    func testSupplementSubIntents_MarkVsStatus() {
        // Status (query) cases — LLM should return supplements tool
        let statusCases: [String] = [
            #"{"tool":"supplements"}"#,
            #"{"tool":"supplements","query":"creatine"}"#,
            #"{"tool":"supplements","query":"did I take creatine today"}"#,
        ]
        for json in statusCases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Status query JSON should parse: \(json)"); continue
            }
            XCTAssertEqual(intent.tool, "supplements",
                "'Did I take creatine?' should route to supplements(), not mark_supplement")
            XCTAssertNotEqual(intent.tool, "mark_supplement",
                "Status query must not log intake: \(json)")
        }

        // Mark (intake) cases — LLM should return mark_supplement
        let markCases: [(json: String, name: String)] = [
            (#"{"tool":"mark_supplement","name":"creatine"}"#, "creatine"),
            (#"{"tool":"mark_supplement","name":"vitamin c"}"#, "vitamin c"),
            (#"{"tool":"mark_supplement","name":"zinc"}"#, "zinc"),
        ]
        for (json, expectedName) in markCases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Mark intake JSON should parse: \(json)"); continue
            }
            XCTAssertEqual(intent.tool, "mark_supplement",
                "'log/took creatine' should be mark_supplement")
            XCTAssertEqual(intent.params["name"], expectedName)
            XCTAssertNotEqual(intent.tool, "log_food",
                "Supplement intake must not be routed to log_food: \(json)")
        }

        print("📊 Supplement mark-vs-status: \(statusCases.count) status + \(markCases.count) mark cases verified")
    }

    // MARK: - StaticOverrides Routing Gold Set

    @MainActor
    func testStaticOverrides_Greetings() {
        let greetings = ["hi", "hello", "hey", "yo"]
        for query in greetings {
            guard let result = StaticOverrides.match(query) else {
                XCTFail("Greeting '\(query)' should be caught by StaticOverrides")
                continue
            }
            if case .response = result { /* pass */ }
            else { XCTFail("Greeting '\(query)' should return .response") }
        }
    }

    @MainActor
    func testStaticOverrides_Navigation() {
        let navQueries = [
            "show me my weight chart",
            "go to food tab",
            "open exercise",
        ]
        var navigated = 0
        for query in navQueries {
            let normalized = InputNormalizer.normalize(query).lowercased()
            guard let result = StaticOverrides.match(normalized) else {
                print("MISS (nav): '\(query)'")
                continue
            }
            if case .uiAction(let action, _) = result, case .navigate = action {
                navigated += 1
            } else {
                print("WRONG type (nav): '\(query)' → \(result)")
            }
        }
        print("📊 StaticOverrides navigation: \(navigated)/\(navQueries.count)")
        XCTAssertEqual(navigated, navQueries.count, "All navigation queries must route to .navigate")
    }

    @MainActor
    func testStaticOverrides_NonDomainCommands() {
        let staticCases = ["help", "scan barcode", "thanks", "ok"]
        var caught = 0
        for query in staticCases {
            if StaticOverrides.match(query) != nil { caught += 1 }
            else { print("MISS (static): '\(query)'") }
        }
        print("📊 StaticOverrides non-domain: \(caught)/\(staticCases.count)")
        XCTAssertEqual(caught, staticCases.count)
    }

    // MARK: - Confidence Parsing (ask vs guess)

    /// LLM-emitted confidence is parsed into ClassifiedIntent.confidence and surfaces
    /// to AIToolAgent for observability (low confidence routes still execute but log).
    func testParseResponse_ConfidenceFieldParsed() {
        let cases: [(json: String, expected: String)] = [
            (#"{"tool":"log_food","name":"rice","confidence":"high"}"#, "high"),
            (#"{"tool":"log_food","name":"rice","confidence":"medium"}"#, "medium"),
            (#"{"tool":"log_food","name":"rice","confidence":"low"}"#, "low"),
        ]
        for (json, expected) in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Should parse with confidence: \(json)"); continue
            }
            XCTAssertEqual(intent.confidence, expected,
                "Confidence field should round-trip exactly as emitted")
        }
    }

    /// Missing confidence field → must default to "high" so existing LLM outputs
    /// (which don't emit the field) keep their current behavior.
    func testParseResponse_MissingConfidenceDefaultsHigh() {
        let json = #"{"tool":"log_food","name":"rice"}"#
        guard let intent = IntentClassifier.parseResponse(json) else {
            XCTFail("Should parse without confidence"); return
        }
        XCTAssertEqual(intent.confidence, "high",
            "Absent confidence defaults to high — preserves pre-calibration behavior")
    }

    /// Non-string confidence (malformed LLM output) → fall back to "high".
    func testParseResponse_MalformedConfidenceFallsBackHigh() {
        let cases = [
            #"{"tool":"log_food","name":"rice","confidence":42}"#,     // numeric
            #"{"tool":"log_food","name":"rice","confidence":null}"#,   // null
            #"{"tool":"log_food","name":"rice","confidence":[]}"#,     // array
        ]
        for json in cases {
            guard let intent = IntentClassifier.parseResponse(json) else {
                XCTFail("Should parse with bad confidence: \(json)"); continue
            }
            XCTAssertEqual(intent.confidence, "high",
                "Malformed confidence should fall back to high, not crash or go empty")
        }
    }

    /// Ambiguity branch: bare verbs with no object should produce text clarifying questions,
    /// not tool calls. Verifies the .text mapping path the LLM can choose.
    func testMapResponse_ClarifyTextForBareVerbs() {
        let clarifyResponses = [
            "What would you like to log — food, weight, or a workout?",
            "What should I track?",
            "What would you like to add?",
            "How much what — calories, protein, carbs, or something else?",
        ]
        for text in clarifyResponses {
            guard case .text(let out) = IntentClassifier.mapResponse(text) else {
                XCTFail("Clarifying text should map to .text: \(text)"); continue
            }
            XCTAssertFalse(out.isEmpty)
        }
    }

    // MARK: - Token Ceiling

    /// Locks prompt size after audit v2 (removed 2 redundant examples, -206 chars).
    /// Fails if someone adds new examples without removing equivalent dead weight.
    @MainActor
    func testSystemPrompt_TokenCeiling() {
        let charCount = IntentClassifier.systemPrompt.count
        XCTAssertLessThanOrEqual(charCount, 5600,
            "systemPrompt has \(charCount) chars — over the 5600-char ceiling. Remove redundant examples before adding new ones.")
    }

    // MARK: - Domain-Blend Gold Set (#246)

    /// Verifies that ambiguous domain-blend queries return nil from StaticOverrides,
    /// correctly falling through to the LLM. Catches false-positive static captures.
    @MainActor
    func testDomainBlend_StaticOverridesPassthrough() {
        let cases: [(query: String, rationale: String)] = [
            ("how much protein did I eat after my workout", "food+workout cross-domain — must reach LLM"),
            ("did my run affect my weight", "workout+weight cross-domain — must reach LLM"),
            ("gained weight after cheat day", "weight+food cross-domain — must reach LLM"),
            ("track my run", "'track' is non-canonical verb for log_activity"),
            ("record my yoga session", "'record' is non-canonical verb for log_activity"),
            ("log my walk", "walk could be activity or exercise — LLM decides"),
            ("150", "bare number — weight vs food gram vs calorie, LLM needs context"),
            ("200g protein", "amount+food blend — LLM picks log_food vs food_info"),
            ("75 kgs", "weight with unit but no log verb — LLM decides log vs info"),
            ("last meal", "temporal query vs delete-last ambiguity — must reach LLM"),
            ("calories from yesterday", "temporal food query — LLM routes to food_info"),
            ("how am I doing on protein", "progress check phrasing — LLM routes to food_info"),
            ("5k this morning", "5k = run distance, not 5000 calories — LLM resolves"),
            ("bench 225 for 5", "non-canonical exercise log format — LLM routes"),
            ("hit my macros today", "'hit' as status verb — LLM routes to food_info"),
        ]

        var passedThrough = 0
        for c in cases {
            let normalized = InputNormalizer.normalize(c.query).lowercased()
            if StaticOverrides.match(normalized) == nil {
                passedThrough += 1
            } else {
                print("FALSE CAPTURE ('\(c.query)'): StaticOverrides caught domain-blend query — \(c.rationale)")
            }
        }
        print("📊 Domain-blend StaticOverrides passthrough: \(passedThrough)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(passedThrough, 12,
            "At least 12/15 domain-blend queries must fall through StaticOverrides to LLM")
    }

    /// Given the expected LLM JSON output for each domain-blend case, verifies the
    /// JSON parser routes to the correct tool. Documents intended routing behavior.
    func testDomainBlend_ParseResponse() {
        let cases: [(id: String, json: String, tool: String, rationale: String)] = [
            // Cross-domain questions
            ("protein_post_workout",
             #"{"tool":"food_info","query":"protein after workout"}"#,
             "food_info", "protein eaten after workout — answer lives in food data"),
            ("run_weight_effect",
             #"{"tool":"weight_info","query":"weight trend after run"}"#,
             "weight_info", "workout→weight cross-domain — weight_info has the answer"),
            ("weight_after_cheatday",
             #"{"tool":"weight_info","query":"weight gain after cheat day"}"#,
             "weight_info", "cheat-day weight change — weight_info context"),

            // Ambiguous verbs
            ("track_run",
             #"{"tool":"log_activity","name":"run"}"#,
             "log_activity", "'track my run' → log_activity, not navigate_to"),
            ("record_yoga",
             #"{"tool":"log_activity","name":"yoga","duration":"60"}"#,
             "log_activity", "'record yoga' → log_activity via non-canonical verb"),
            ("log_walk",
             #"{"tool":"log_activity","name":"walk"}"#,
             "log_activity", "walk is an activity, not a structured workout"),

            // Implicit domain
            ("bare_150",
             #"{"tool":"log_weight","value":"150","unit":"lbs"}"#,
             "log_weight", "bare number most likely means weight in lbs context"),
            ("grams_protein",
             #"{"tool":"log_food","name":"protein powder","servings":"1"}"#,
             "log_food", "200g protein → log_food, not a macro query"),
            ("kg_weight",
             #"{"tool":"log_weight","value":"75","unit":"kg"}"#,
             "log_weight", "75 kgs → log_weight even without explicit log verb"),

            // Temporal ambiguity
            ("last_meal_query",
             #"{"tool":"food_info","query":"last meal"}"#,
             "food_info", "'last meal' is a query, not a delete command"),
            ("calories_yesterday",
             #"{"tool":"food_info","query":"calories yesterday"}"#,
             "food_info", "temporal food query routes to food_info"),
            ("protein_progress",
             #"{"tool":"food_info","query":"protein progress"}"#,
             "food_info", "'how am I doing on protein' → food_info progress check"),

            // Abbreviation / blend
            ("5k_run",
             #"{"tool":"log_activity","name":"run","distance":"5k"}"#,
             "log_activity", "5k = run distance, not 5000 calories"),
            ("bench_press",
             #"{"tool":"start_workout","name":"bench press"}"#,
             "start_workout", "bench 225 for 5 → structured exercise log"),
            ("hit_macros",
             #"{"tool":"food_info","query":"macro status"}"#,
             "food_info", "'hit my macros' = check macro status, not a log action"),
        ]

        var correct = 0
        for c in cases {
            guard let intent = IntentClassifier.parseResponse(c.json) else {
                print("MISS (\(c.id)): \(c.json)")
                continue
            }
            if intent.tool == c.tool {
                correct += 1
            } else {
                print("WRONG (\(c.id)): expected \(c.tool), got \(intent.tool) | \(c.rationale)")
            }
        }
        print("📊 Domain-blend parseResponse: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count,
            "All domain-blend JSON should parse to the expected tool — these are deterministic parser tests")
    }
}
