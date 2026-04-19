import Foundation

/// Resolves multi-turn references to food entries — preferring a stable
/// `entry_id` from the ConversationState recent-entries window, then
/// ordinal phrases ("first", "last"), and finally falling back to
/// name-match in FoodService. Owns the disambiguation logic so the tool
/// handlers stay thin (#227).
@MainActor
enum FoodEntryRefResolver {

    /// Attempt to resolve a concrete entry id from the LLM-extracted params.
    /// Order of precedence:
    ///   1. `entry_id` numeric param, validated against today's recent window
    ///   2. ordinal phrase in `name` / `target_food` ("first", "last", etc.)
    /// Returns nil when neither applies — callers fall back to name search.
    static func resolveEntryId(
        from params: ToolCallParams,
        phraseKeys: [String] = ["name", "target_food", "query"]
    ) -> Int64? {
        if let id = extractEntryId(params: params) { return id }
        for key in phraseKeys {
            if let phrase = params.string(key),
               let ref = ConversationState.shared.resolveOrdinal(phrase) {
                return ref.id
            }
        }
        return nil
    }

    /// Validate an LLM-supplied entry_id: must be a positive integer AND
    /// appear in the current recent-entries window. Stale / invented ids
    /// are rejected so the tool degrades to name-match instead of
    /// operating on the wrong row.
    private static func extractEntryId(params: ToolCallParams) -> Int64? {
        guard let raw = params.string("entry_id"),
              let id = Int64(raw.trimmingCharacters(in: .whitespaces)),
              id > 0 else { return nil }
        let window = ConversationState.shared.recentEntries
        return window.contains(where: { $0.id == id }) ? id : nil
    }
}

/// Thin adapter: extracts params, resolves id, routes to FoodService.
@MainActor
enum DeleteFoodHandler {
    static func run(params: ToolCallParams) -> String {
        if let id = FoodEntryRefResolver.resolveEntryId(from: params),
           let msg = FoodService.deleteEntry(id: id) {
            return msg
        }
        let name = params.string("name") ?? "last"
        return FoodService.deleteEntry(matching: name)
    }
}

/// Thin adapter: extracts params, resolves id, routes to FoodService.
@MainActor
enum EditMealHandler {
    static func run(params: ToolCallParams) -> String {
        let action = params.string("action") ?? "remove"
        let newValue = params.string("new_value")
        let mealPeriod = params.string("meal_period")
        let target = params.string("target_food") ?? ""

        let resolvedId = FoodEntryRefResolver.resolveEntryId(from: params)

        if resolvedId == nil, target.isEmpty {
            return "Tell me which food to edit."
        }

        return FoodService.editMealEntry(
            mealPeriod: mealPeriod,
            targetFood: target,
            action: action,
            newValue: newValue,
            entryId: resolvedId
        )
    }
}
