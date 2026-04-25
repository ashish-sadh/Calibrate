import Foundation
@testable import DriftCore
import Testing

// MARK: - AIToolAgent stage label helpers

@Test @MainActor func toolLookupMessage_foodInfo_usesParamName() {
    let call = ToolCall(tool: "food_info", params: ToolCallParams(values: ["name": "banana"]))
    #expect(AIToolAgent.toolLookupMessage(for: call, query: "nutrition in banana") == "Looking up banana...")
}

@Test @MainActor func toolLookupMessage_foodInfo_fallsBackToQuery() {
    let call = ToolCall(tool: "food_info", params: ToolCallParams(values: [:]))
    let msg = AIToolAgent.toolLookupMessage(for: call, query: "calories in chicken")
    #expect(msg.hasPrefix("Looking up"))
}

@Test @MainActor func toolLookupMessage_weightInfo_returnsWeightLabel() {
    let call = ToolCall(tool: "weight_info", params: ToolCallParams(values: [:]))
    #expect(AIToolAgent.toolLookupMessage(for: call, query: "weight trend") == "Looking up your weight...")
}

@Test @MainActor func toolLookupMessage_sleepRecovery_returnsSleepLabel() {
    let call = ToolCall(tool: "sleep_recovery", params: ToolCallParams(values: [:]))
    #expect(AIToolAgent.toolLookupMessage(for: call, query: "how did I sleep") == "Looking up your sleep...")
}

@Test @MainActor func toolLookupMessage_unknown_returnsGeneric() {
    let call = ToolCall(tool: "unknown_tool", params: ToolCallParams(values: [:]))
    #expect(AIToolAgent.toolLookupMessage(for: call, query: "something") == "Looking that up...")
}

@Test @MainActor func toolFoundMessage_foodInfo_returnsMacrosLabel() {
    #expect(AIToolAgent.toolFoundMessage(for: "food_info") == "Finding macros...")
}

@Test @MainActor func toolFoundMessage_weightInfo_returnsTrendsLabel() {
    #expect(AIToolAgent.toolFoundMessage(for: "weight_info") == "Reading your trends...")
}

@Test @MainActor func toolFoundMessage_sleepRecovery_returnsRecoveryLabel() {
    #expect(AIToolAgent.toolFoundMessage(for: "sleep_recovery") == "Checking your recovery...")
}

@Test @MainActor func toolFoundMessage_unknown_returnsGeneric() {
    #expect(AIToolAgent.toolFoundMessage(for: "unknown_tool") == "Putting it together...")
}

@Test @MainActor func stageLabels_foodInfo_areDistinct() {
    let call = ToolCall(tool: "food_info", params: ToolCallParams(values: ["name": "oats"]))
    let stage1 = AIToolAgent.toolLookupMessage(for: call, query: "nutrition in oats")
    let stage2 = AIToolAgent.toolFoundMessage(for: "food_info")
    #expect(stage1 != stage2, "Lookup and found messages must differ for visible UI transition")
}

// MARK: - validateExtraction — food params

@Test @MainActor func validateFood_renamesServingsToAmount() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "rice", "servings": "2"]))
    let result = AIToolAgent.validateExtraction(call, message: "log 2 servings of rice")
    #expect(result.params.values["amount"] == "2")
    #expect(result.params.values["servings"] == nil)
}

@Test @MainActor func validateFood_removesOutOfRangeAmount_zero() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "egg", "amount": "0"]))
    let result = AIToolAgent.validateExtraction(call, message: "log 0 eggs")
    #expect(result.params.values["amount"] == nil)
}

@Test @MainActor func validateFood_removesOutOfRangeAmount_tooHigh() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "apple", "amount": "200"]))
    let result = AIToolAgent.validateExtraction(call, message: "log 200 apples")
    #expect(result.params.values["amount"] == nil)
}

@Test @MainActor func validateFood_keepsValidAmount() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "banana", "amount": "1"]))
    let result = AIToolAgent.validateExtraction(call, message: "log 1 banana")
    #expect(result.params.values["amount"] == "1")
}

@Test @MainActor func validateFood_removesHugeCalories() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "pizza", "calories": "99999"]))
    let result = AIToolAgent.validateExtraction(call, message: "log pizza")
    #expect(result.params.values["calories"] == nil)
}

@Test @MainActor func validateFood_removesNegativeMacros() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "oats", "protein": "-5", "carbs": "-10", "fat": "-2"]))
    let result = AIToolAgent.validateExtraction(call, message: "log oats")
    #expect(result.params.values["protein"] == nil)
    #expect(result.params.values["carbs"] == nil)
    #expect(result.params.values["fat"] == nil)
}

@Test @MainActor func validateFood_keepsValidMacros() {
    let call = ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": "chicken", "protein": "30", "carbs": "0", "fat": "5"]))
    let result = AIToolAgent.validateExtraction(call, message: "log chicken")
    #expect(result.params.values["protein"] == "30")
    #expect(result.params.values["carbs"] == "0")
    #expect(result.params.values["fat"] == "5")
}

// MARK: - validateExtraction — weight params

@Test @MainActor func validateWeight_keepsValidWeight() {
    let call = ToolCall(tool: "log_weight", params: ToolCallParams(values: ["value": "75", "unit": "kg"]))
    let result = AIToolAgent.validateExtraction(call, message: "log weight 75kg")
    #expect(result.params.values["value"] == "75")
}

@Test @MainActor func validateWeight_outOfRangeBelow20_fallsBackOrKeeps() {
    let call = ToolCall(tool: "log_weight", params: ToolCallParams(values: ["value": "5", "unit": "kg"]))
    let result = AIToolAgent.validateExtraction(call, message: "log weight 75kg")
    // Either Swift extraction kicks in (and finds 75kg) or value remains unchanged — never crash
    #expect(result.params.values["value"] != nil)
}

@Test @MainActor func validateWeight_outOfRangeAbove500_fallsBackOrKeeps() {
    let call = ToolCall(tool: "log_weight", params: ToolCallParams(values: ["value": "999", "unit": "kg"]))
    let result = AIToolAgent.validateExtraction(call, message: "log weight 80kg")
    // Swift extraction should find 80 from message
    #expect(result.params.values["value"] != nil)
}

// MARK: - validateExtraction — activity params

@Test @MainActor func validateActivity_removesOutOfRangeDuration() {
    let call = ToolCall(tool: "log_activity", params: ToolCallParams(values: ["name": "run", "duration": "9999"]))
    let result = AIToolAgent.validateExtraction(call, message: "log run 9999 minutes")
    #expect(result.params.values["duration"] == nil)
}

@Test @MainActor func validateActivity_removesZeroDuration() {
    let call = ToolCall(tool: "log_activity", params: ToolCallParams(values: ["name": "walk", "duration": "0"]))
    let result = AIToolAgent.validateExtraction(call, message: "log walk")
    #expect(result.params.values["duration"] == nil)
}

@Test @MainActor func validateActivity_keepsValidDuration() {
    let call = ToolCall(tool: "log_activity", params: ToolCallParams(values: ["name": "yoga", "duration": "30"]))
    let result = AIToolAgent.validateExtraction(call, message: "log 30 min yoga")
    #expect(result.params.values["duration"] == "30")
}

@Test @MainActor func validateExtraction_defaultTool_passesThrough() {
    let call = ToolCall(tool: "food_info", params: ToolCallParams(values: ["name": "oats"]))
    let result = AIToolAgent.validateExtraction(call, message: "nutrition in oats")
    #expect(result.tool == "food_info")
    #expect(result.params.values["name"] == "oats")
}

// MARK: - addInsightPrefix

@Test @MainActor func addInsightPrefix_noFoodLogged_noPrefix() {
    let result = AIToolAgent.addInsightPrefix(to: "No food logged today.")
    #expect(result == "No food logged today.")
}

@Test @MainActor func addInsightPrefix_overTarget_headsUp() {
    let result = AIToolAgent.addInsightPrefix(to: "You're over target today by 200 cal.")
    #expect(result.hasPrefix("Heads up"))
}

@Test @MainActor func addInsightPrefix_lowRecovery_takeItEasy() {
    let result = AIToolAgent.addInsightPrefix(to: "Low recovery score — rest is advised.")
    #expect(result.hasPrefix("Take it easy"))
}

@Test @MainActor func addInsightPrefix_onTrack_niceWork() {
    let result = AIToolAgent.addInsightPrefix(to: "You're on track — 1800 of 2000 cal.")
    #expect(result.hasPrefix("Nice work"))
}

@Test @MainActor func addInsightPrefix_remaining_lookingGood() {
    let result = AIToolAgent.addInsightPrefix(to: "400 cal remaining for dinner.")
    #expect(result.hasPrefix("Looking good"))
}

@Test @MainActor func addInsightPrefix_workout_activityPrefix() {
    let result = AIToolAgent.addInsightPrefix(to: "Workout streak: 5 days.")
    #expect(result.hasPrefix("Here's your activity"))
}

@Test @MainActor func addInsightPrefix_trend_trendPrefix() {
    let result = AIToolAgent.addInsightPrefix(to: "You're losing 0.4kg/week.")
    #expect(result.hasPrefix("Here's the trend"))
}

@Test @MainActor func addInsightPrefix_default_foundPrefix() {
    let result = AIToolAgent.addInsightPrefix(to: "Your BMR is 1650 kcal.")
    #expect(result.hasPrefix("Here's what I found"))
}

// MARK: - stepMessage

@Test @MainActor func stepMessage_ateKeyword_loggingFood() {
    #expect(AIToolAgent.stepMessage(for: "I ate chicken") == "Logging food...")
}

@Test @MainActor func stepMessage_logKeyword_loggingFood() {
    #expect(AIToolAgent.stepMessage(for: "log 2 eggs") == "Logging food...")
}

@Test @MainActor func stepMessage_workoutKeyword_settingUp() {
    #expect(AIToolAgent.stepMessage(for: "start chest workout") == "Setting up workout...")
}

@Test @MainActor func stepMessage_supplementKeyword_updatingSupplements() {
    #expect(AIToolAgent.stepMessage(for: "took vitamin D") == "Updating supplements...")
}

@Test @MainActor func stepMessage_glucoseKeyword_checkingGlucose() {
    #expect(AIToolAgent.stepMessage(for: "any glucose spikes today") == "Checking glucose...")
}

@Test @MainActor func stepMessage_mealPlanKeyword_planningMeals() {
    #expect(AIToolAgent.stepMessage(for: "plan my meals for today") == "Planning meals...")
}

@Test @MainActor func stepMessage_caloriesKeyword_checkingData() {
    #expect(AIToolAgent.stepMessage(for: "how many calories left") == "Checking your data...")
}

@Test @MainActor func stepMessage_unknown_lookingThatUp() {
    #expect(AIToolAgent.stepMessage(for: "random query xyz") == "Looking that up...")
}

// MARK: - toolFoundMessage

@Test @MainActor func toolFoundMessage_foodInfo_findingMacros() {
    #expect(AIToolAgent.toolFoundMessage(for: "food_info") == "Finding macros...")
}

@Test @MainActor func toolFoundMessage_weightInfo_readingTrends() {
    #expect(AIToolAgent.toolFoundMessage(for: "weight_info") == "Reading your trends...")
}

@Test @MainActor func toolFoundMessage_sleepRecovery_checkingRecovery() {
    #expect(AIToolAgent.toolFoundMessage(for: "sleep_recovery") == "Checking your recovery...")
}

@Test @MainActor func toolFoundMessage_exerciseInfo_reviewingHistory() {
    #expect(AIToolAgent.toolFoundMessage(for: "exercise_info") == "Reviewing your history...")
}

@Test @MainActor func toolFoundMessage_unknown_puttingItTogether() {
    #expect(AIToolAgent.toolFoundMessage(for: "unknown_tool") == "Putting it together...")
}

// MARK: - toolStepMessage

@Test @MainActor func toolStepMessage_logFood_lookingUpFood() {
    #expect(AIToolAgent.toolStepMessage(for: "log_food") == "Looking up food...")
}

@Test @MainActor func toolStepMessage_logWeight_checkingWeightData() {
    #expect(AIToolAgent.toolStepMessage(for: "log_weight") == "Checking weight data...")
}

@Test @MainActor func toolStepMessage_startWorkout_checkingWorkoutHistory() {
    #expect(AIToolAgent.toolStepMessage(for: "start_workout") == "Checking workout history...")
}

@Test @MainActor func toolStepMessage_sleepRecovery_checkingRecovery() {
    #expect(AIToolAgent.toolStepMessage(for: "sleep_recovery") == "Checking recovery...")
}

@Test @MainActor func toolStepMessage_copyYesterday_copyingFood() {
    #expect(AIToolAgent.toolStepMessage(for: "copy_yesterday") == "Copying yesterday's food...")
}

@Test @MainActor func toolStepMessage_unknown_processing() {
    #expect(AIToolAgent.toolStepMessage(for: "mystery_tool") == "Processing...")
}

// MARK: - fallbackText

@Test @MainActor func fallbackText_food_mentionsLogFood() {
    let text = AIToolAgent.fallbackText(for: .food)
    #expect(text.contains("log food") || text.contains("log 2 eggs"))
}

@Test @MainActor func fallbackText_weight_mentionsWeight() {
    let text = AIToolAgent.fallbackText(for: .weight)
    #expect(text.contains("weight"))
}

@Test @MainActor func fallbackText_exercise_mentionsWorkout() {
    let text = AIToolAgent.fallbackText(for: .exercise)
    #expect(text.contains("workout"))
}

@Test @MainActor func fallbackText_supplements_mentionsSupplements() {
    let text = AIToolAgent.fallbackText(for: .supplements)
    #expect(text.contains("supplement"))
}

// MARK: - isInfoTool

@Test @MainActor func isInfoTool_foodInfo_isTrue() {
    #expect(AIToolAgent.isInfoTool("food_info") == true)
}

@Test @MainActor func isInfoTool_weightInfo_isTrue() {
    #expect(AIToolAgent.isInfoTool("weight_info") == true)
}

@Test @MainActor func isInfoTool_logFood_isFalse() {
    #expect(AIToolAgent.isInfoTool("log_food") == false)
}

@Test @MainActor func isInfoTool_unknown_isFalse() {
    #expect(AIToolAgent.isInfoTool("unknown") == false)
}
