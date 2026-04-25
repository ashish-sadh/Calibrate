import Foundation
@testable import DriftCore
import Testing

/// Regression floor for #242: concrete queries that accidentally tripped the
/// keyword-based ambiguity detector even though they carry enough structure
/// for the extractor. Every case here must return `nil` — if any start
/// producing options, we're prompting users on the success path.

// MARK: - Food + quantity

@Test func foodWithGramsDoesNotTriggerClarify() {
    let cases = [
        "100g biryani", "250g chicken", "50g paneer", "200 g rice",
        "30g whey", "150g salmon"
    ]
    for msg in cases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' has weight — extractor should handle it")
    }
}

@Test func foodWithCountDoesNotTriggerClarify() {
    let cases = [
        "2 eggs", "3 bananas", "log 3 eggs", "track 2 bananas",
        "ate 1 pizza", "add 4 rotis"
    ]
    for msg in cases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' has count — extractor should handle it")
    }
}

// MARK: - Supplement + dose

@Test func supplementWithDoseDoesNotTriggerClarify() {
    let cases = [
        "5g creatine", "creatine 5g", "vitamin d 2000iu",
        "2000iu vitamin d", "1000mg vitamin c", "500mg magnesium"
    ]
    for msg in cases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' has dose — extractor should handle it")
    }
}

// MARK: - Weight + unit

@Test func weightWithUnitDoesNotTriggerClarify() {
    let cases = ["150 lbs", "68kg", "180 pounds", "75 kg"]
    for msg in cases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' has unit — extractor should handle it")
    }
}

// MARK: - Meal-time context

@Test func mealTimeContextDoesNotTriggerClarify() {
    let cases = [
        "chicken for lunch", "biryani for dinner", "creatine at breakfast",
        "eggs for breakfast", "snack pasta"
    ]
    for msg in cases {
        #expect(ClarificationBuilder.buildOptions(for: msg) == nil,
            "'\(msg)' has meal-time — extractor should handle it")
    }
}

// MARK: - Regression floor: genuine ambiguity still triggers

@Test func genuineAmbiguityStillTriggersAfterGate() {
    let cases = [
        ("biryani", "log_food"),
        ("creatine", "mark_supplement"),
        ("vitamin d", "mark_supplement"),
        ("chicken", "log_food"),
    ]
    for (msg, firstTool) in cases {
        guard let opts = ClarificationBuilder.buildOptions(for: msg) else {
            Issue.record("'\(msg)' should still clarify"); continue
        }
        #expect(opts.first?.tool == firstTool, "'\(msg)' first tool changed")
    }
}

@Test func bareWeightNumberStillTriggers() {
    // "150" alone (no unit) is the hardest-to-resolve case — keep clarifier.
    guard let opts = ClarificationBuilder.buildOptions(for: "150") else {
        Issue.record("bare weight number should still clarify"); return
    }
    #expect(opts.count == 3)
}

// MARK: - hasCompleteParams

@Test func hasCompleteParamsForLogFoodRequiresQuantity() {
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_food",
        params: ["name": "eggs", "servings": "3"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_food",
        params: ["name": "chicken", "grams": "150"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_food",
        params: ["name": "eggs"]) == false, "name alone is not complete")
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_food",
        params: ["servings": "3"]) == false, "servings alone is not complete")
}

@Test func hasCompleteParamsForLogWeightRequiresBoth() {
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_weight",
        params: ["value": "150", "unit": "lbs"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_weight",
        params: ["value": "150"]) == false)
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_weight",
        params: ["unit": "kg"]) == false)
}

@Test func hasCompleteParamsForLogActivityRequiresDurationOrDistance() {
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_activity",
        params: ["name": "run", "duration_min": "30"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_activity",
        params: ["name": "run", "distance": "5km"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_activity",
        params: ["name": "run"]) == false)
}

@Test func hasCompleteParamsForInfoToolsAcceptsQueryOrName() {
    #expect(ClarificationBuilder.hasCompleteParams(tool: "food_info",
        params: ["query": "calories in chicken"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "supplements",
        params: ["name": "creatine"]))
    #expect(ClarificationBuilder.hasCompleteParams(tool: "food_info",
        params: [:]) == false)
}

@Test func hasCompleteParamsUnknownToolIsFalse() {
    #expect(ClarificationBuilder.hasCompleteParams(tool: "mystery_tool",
        params: ["anything": "everything"]) == false)
}

@Test func hasCompleteParamsIgnoresWhitespaceOnlyValues() {
    #expect(ClarificationBuilder.hasCompleteParams(tool: "log_food",
        params: ["name": "eggs", "servings": "   "]) == false)
}
