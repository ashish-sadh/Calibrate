import Foundation

/// Persistent multi-turn conversation state. Singleton — survives navigation.
/// Replaces @State vars in AIChatView for multi-turn tracking.
@MainActor @Observable
final class ConversationState {
    static let shared = ConversationState()

    // MARK: - Pending Intent (what the LLM was trying to do)

    enum PendingIntent {
        /// Tool tried to execute but missing a param — waiting for user to provide it
        case awaitingParam(tool: String, missing: String, partialParams: [String: String])
        /// PreHook asked for confirmation — waiting for user to say yes/no
        case awaitingConfirmation(tool: String, message: String, params: [String: String])
    }

    var pendingIntent: PendingIntent?

    // MARK: - Last Executed Tool

    var lastTool: String?
    var lastParams: [String: String] = [:]

    // MARK: - Topic Tracking

    enum Topic: String {
        case food, weight, exercise, sleep, supplements, glucose, biomarkers, bodyComp, unknown
    }

    var lastTopic: Topic = .unknown
    var turnCount: Int = 0

    // MARK: - Undo (last write action only)

    enum UndoableAction {
        case foodLogged(entryId: Int64, name: String, calories: Double)
        case weightLogged(entryId: Int64, value: Double)
        case supplementMarked(supplementId: Int64, date: String, name: String)
        case activityLogged(workoutId: Int64, name: String)
        case goalSet(previous: WeightGoal?)
        case foodDeleted(entry: FoodEntry)
    }

    var lastWriteAction: UndoableAction?

    // MARK: - Conversation Phase (state machine for multi-turn)

    /// What kind of follow-up input we're expecting from the user.
    /// Replaces scattered pending* booleans/optionals — only one phase at a time.
    enum Phase: Equatable {
        /// Ready for any input
        case idle
        /// Asked "What did you have for X?" — expecting food list
        case awaitingMealItems(mealName: String)
        /// Asked "What exercises did you do?" — expecting exercise list
        case awaitingExercises
        /// Iterative meal planning: suggesting foods to fill remaining macros
        case planningMeals(mealName: String, iteration: Int)
        /// Iterative workout split builder: designing a multi-day program
        case planningWorkout(splitType: String, currentDay: Int, totalDays: Int)
    }

    var phase: Phase = .idle

    // MARK: - Topic Classification (deterministic, no LLM)

    func classifyTopic(_ query: String) -> Topic {
        let lower = query.lowercased()
        let words = Set(lower.split(separator: " ").map(String.init))

        // Multi-word phrases first (more specific than single-word matches)
        // Body comp — "body fat" must beat "fat" triggering food
        if lower.contains("body fat") || words.contains("dexa") || words.contains("bmi")
            || lower.contains("lean mass") || lower.contains("muscle mass") { return .bodyComp }

        // Food
        if words.contains("ate") || words.contains("had") || words.contains("log") || words.contains("calories")
            || words.contains("protein") || words.contains("carbs") || words.contains("fat")
            || words.contains("food") || words.contains("meal") || words.contains("meals") || words.contains("eat")
            || lower.contains("breakfast") || lower.contains("lunch") || lower.contains("dinner")
            || lower.contains("plan my") || lower.contains("suggest meal") { return .food }

        // Weight
        if words.contains("weigh") || words.contains("weight") || words.contains("trend")
            || words.contains("tdee") || words.contains("bmr") || words.contains("goal") { return .weight }

        // Exercise
        if words.contains("workout") || words.contains("exercise") || words.contains("train")
            || words.contains("gym") || words.contains("yoga") || words.contains("running")
            || words.contains("split") || words.contains("ppl")
            || lower.contains("push day") || lower.contains("leg day") { return .exercise }

        // Sleep
        if words.contains("sleep") || words.contains("recovery") || words.contains("hrv")
            || words.contains("rhr") || words.contains("rest") { return .sleep }

        // Supplements
        if words.contains("supplement") || words.contains("vitamin") || words.contains("creatine")
            || lower.contains("took my") { return .supplements }

        // Glucose
        if words.contains("glucose") || words.contains("sugar") || words.contains("spike") { return .glucose }

        // Biomarkers
        if words.contains("biomarker") || words.contains("lab") || words.contains("blood") { return .biomarkers }

        return .unknown
    }

    // MARK: - Reset

    func reset() {
        pendingIntent = nil
        lastTool = nil
        lastParams = [:]
        phase = .idle
        // Don't reset lastTopic, turnCount, or lastWriteAction — those persist across resets
    }

    func recordToolExecution(tool: String, params: [String: String]) {
        lastTool = tool
        lastParams = params
        turnCount += 1
    }
}
