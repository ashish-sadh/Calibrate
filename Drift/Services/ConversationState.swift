import Foundation
import DriftCore

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

    // MARK: - Last Tool Result (for follow-up context, #184)

    /// Raw tool-result text captured immediately after tool execution, used to
    /// thread concrete data (macros, values) into the next turn's LLM context.
    /// Retained for exactly one subsequent user turn — goes stale after that
    /// so questions like "what was that?" can't reach back indefinitely.
    var lastToolSummary: String?
    /// The `userTurnIndex` at which `lastToolSummary` was captured. Fresh when
    /// captured during the current turn or the immediately preceding one.
    var lastToolSummaryTurn: Int = -1

    /// Monotonic counter incremented once per user-initiated turn. Distinct
    /// from `turnCount` (which increments on tool execution only) so the
    /// freshness window is measured against the user's perspective.
    var userTurnIndex: Int = 0

    /// Call at the start of every user send to advance the freshness window.
    func beginUserTurn() {
        userTurnIndex += 1
    }

    /// Record the raw tool-result text for the next turn. Called by
    /// AIToolAgent after every successful tool execution. Empty input is
    /// ignored — actions that produce no text (sheet opens) pass a synthetic
    /// summary so follow-ups still have something to reference.
    func captureToolSummary(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastToolSummary = String(trimmed.prefix(300))
        lastToolSummaryTurn = userTurnIndex
    }

    /// Returns the summary only when it was captured during the current or
    /// previous user turn — nil otherwise. Prevents stale context from
    /// leaking into unrelated later conversations.
    func freshToolSummary() -> String? {
        guard let summary = lastToolSummary else { return nil }
        return (userTurnIndex - lastToolSummaryTurn) <= 1 ? summary : nil
    }

    // MARK: - Recent Food Entries (rolling window for multi-turn refs, #227)

    /// Compact reference to a recently-logged food entry. Used for multi-turn
    /// resolution of "delete the rice I just logged", "edit the 500 cal one",
    /// "remove the first one" — so tools operate on the exact row the user
    /// means rather than re-searching by name (which picks wrong rows when
    /// duplicates exist).
    struct FoodEntryRef: Equatable, Sendable {
        let id: Int64
        let name: String
        let mealType: String   // breakfast | lunch | dinner | snack
        let calories: Int      // Per-serving calories rounded for display
        let loggedAt: Date     // Used for TTL eviction and "Nm ago" context
    }

    /// Rolling window of today's most recent entries, newest last. Capped at
    /// `recentEntriesCap`, stale rows beyond `recentEntriesTTL` are dropped
    /// on every read/push. Never persisted — IDs may be invalid across app
    /// relaunches if the user manually deletes in the UI, so the window is
    /// rebuilt from writes during the current session only.
    private(set) var recentEntries: [FoodEntryRef] = []
    static let recentEntriesCap = 10
    /// 2h TTL matches the product-review decision: "just logged" shouldn't
    /// reach back into last night's dinner when the user opens chat in the
    /// morning.
    static let recentEntriesTTL: TimeInterval = 2 * 60 * 60

    /// Push a newly-logged (or edited) entry onto the rolling window. Oldest
    /// entries get evicted when the window exceeds `recentEntriesCap` (LRU).
    /// Duplicate IDs update the existing ref in place — avoids a stale copy
    /// lingering after an edit.
    func pushRecentEntry(_ ref: FoodEntryRef) {
        pruneExpiredRecentEntries()
        recentEntries.removeAll { $0.id == ref.id }
        recentEntries.append(ref)
        if recentEntries.count > Self.recentEntriesCap {
            recentEntries.removeFirst(recentEntries.count - Self.recentEntriesCap)
        }
        // Cross-domain "last thing we touched" pointer — powers pronoun
        // resolution for queries like "how much protein in that". #241.
        recordLastEntry(domain: .food, summary: ref.name, at: ref.loggedAt)
    }

    /// Drop a ref — called after successful delete/remove so stale IDs can't
    /// re-resolve on a follow-up turn.
    func dropRecentEntry(id: Int64) {
        recentEntries.removeAll { $0.id == id }
    }

    /// Evict entries older than the TTL. Called defensively on every window
    /// read and push.
    func pruneExpiredRecentEntries(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.recentEntriesTTL)
        recentEntries.removeAll { $0.loggedAt < cutoff }
    }

    /// Compact prompt-ready view of the window. Includes relative time
    /// ("5m ago") so the LLM can tie references like "the one I just logged"
    /// to the freshest row. Returns nil when the window is empty.
    func recentEntriesContextBlock(now: Date = Date()) -> String? {
        pruneExpiredRecentEntries(now: now)
        guard !recentEntries.isEmpty else { return nil }
        let rows = recentEntries.suffix(Self.recentEntriesCap).map { ref -> String in
            let minsAgo = max(0, Int(now.timeIntervalSince(ref.loggedAt) / 60))
            return "\(ref.id)|\(ref.mealType)|\(ref.name)|\(ref.calories)cal|\(minsAgo)m"
        }
        return "<recent_entries>\n\(rows.joined(separator: "\n"))\n</recent_entries>"
    }

    /// Resolve an ordinal phrase ("first", "last", "second to last", "2nd")
    /// against the rolling window. Returns the matching entry or nil when
    /// the phrase isn't a recognized ordinal or the window is empty.
    /// Ordinal semantics: "first" = oldest in window, "last" = newest. This
    /// matches how a user reads their own diary.
    func resolveOrdinal(_ phrase: String, now: Date = Date()) -> FoodEntryRef? {
        pruneExpiredRecentEntries(now: now)
        guard !recentEntries.isEmpty else { return nil }
        let lower = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // "last" / "most recent" / "just logged" → newest
        if ["last", "last one", "last entry", "most recent",
            "just logged", "just added", "just now", "latest"].contains(lower) {
            return recentEntries.last
        }
        // "second to last" / "second last" / "penultimate" → newest - 1
        if ["second to last", "second last", "next to last",
            "penultimate"].contains(lower) {
            return recentEntries.count >= 2 ? recentEntries[recentEntries.count - 2] : nil
        }
        // "third to last" → newest - 2
        if ["third to last", "third last"].contains(lower) {
            return recentEntries.count >= 3 ? recentEntries[recentEntries.count - 3] : nil
        }
        // Numeric positions from the start: "first", "1st", "second", "2nd", etc.
        let positionMap: [String: Int] = [
            "first": 1, "1st": 1,
            "second": 2, "2nd": 2,
            "third": 3, "3rd": 3,
            "fourth": 4, "4th": 4,
            "fifth": 5, "5th": 5
        ]
        if let pos = positionMap[lower] {
            return pos <= recentEntries.count ? recentEntries[pos - 1] : nil
        }
        return nil
    }

    // MARK: - Topic Tracking

    enum Topic: String, Codable {
        case food, weight, exercise, sleep, supplements, glucose, biomarkers, bodyComp, unknown
    }

    var lastTopic: Topic = .unknown
    var turnCount: Int = 0

    // MARK: - Cross-domain pronoun pointer (#241)

    /// Last entry the user logged / edited *across any domain*. Powers
    /// pronoun resolution on query-type intents: "how much protein in that"
    /// after a food log, "am I under goal" after a weight log, etc.
    /// Goes stale on the same 2h TTL as `recentEntries`.
    struct LastEntryContext: Equatable, Sendable {
        let domain: Topic
        let summary: String     // "150g chicken" | "180 lbs" | "30min yoga"
        let loggedAt: Date
    }

    private(set) var lastAnyEntry: LastEntryContext?

    /// Record the most-recently-touched entry. Called from `pushRecentEntry`
    /// for food and from non-food log paths (weight, exercise) directly.
    func recordLastEntry(domain: Topic, summary: String, at when: Date = Date()) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastAnyEntry = LastEntryContext(domain: domain, summary: trimmed, loggedAt: when)
    }

    /// Fresh-only accessor: returns `lastAnyEntry` only when within TTL.
    func freshLastEntry(now: Date = Date()) -> LastEntryContext? {
        guard let entry = lastAnyEntry else { return nil }
        let cutoff = now.addingTimeInterval(-Self.recentEntriesTTL)
        return entry.loggedAt < cutoff ? nil : entry
    }

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
        /// Asked "Did you mean X or Y?" for a genuinely-ambiguous intent —
        /// waiting for the user to pick one of the offered options. #226.
        case awaitingClarification(options: [ClarificationOption])
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

    // MARK: - Cancel / Reset

    /// Exit any pending phase without committing — used by cancel/nevermind phrases.
    func cancelPending() {
        phase = .idle
        pendingIntent = nil
    }

    func reset() {
        pendingIntent = nil
        lastTool = nil
        lastParams = [:]
        lastToolSummary = nil
        lastToolSummaryTurn = -1
        recentEntries = []
        lastAnyEntry = nil
        phase = .idle
        // Don't reset lastTopic, turnCount, userTurnIndex, or lastWriteAction — those persist across resets
    }

    func recordToolExecution(tool: String, params: [String: String]) {
        lastTool = tool
        lastParams = params
        turnCount += 1
    }

    /// Apply a persisted snapshot to the live singleton.
    /// pendingIntent and lastWriteAction are not persisted (transient / reference DB rows).
    func apply(_ snapshot: PersistedConversationState) {
        phase = snapshot.phase
        lastTopic = snapshot.lastTopic
        turnCount = snapshot.turnCount
    }
}

// MARK: - Codable Phase (tagged union)

extension ConversationState.Phase: Codable {
    private enum Tag: String, Codable {
        case idle, awaitingMealItems, awaitingExercises, planningMeals, planningWorkout, awaitingClarification
    }
    private enum Keys: String, CodingKey {
        case tag, mealName, splitType, iteration, currentDay, totalDays, options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Tag.self, forKey: .tag) {
        case .idle:
            self = .idle
        case .awaitingMealItems:
            self = .awaitingMealItems(mealName: try c.decode(String.self, forKey: .mealName))
        case .awaitingExercises:
            self = .awaitingExercises
        case .planningMeals:
            self = .planningMeals(
                mealName: try c.decode(String.self, forKey: .mealName),
                iteration: try c.decode(Int.self, forKey: .iteration))
        case .planningWorkout:
            self = .planningWorkout(
                splitType: try c.decode(String.self, forKey: .splitType),
                currentDay: try c.decode(Int.self, forKey: .currentDay),
                totalDays: try c.decode(Int.self, forKey: .totalDays))
        case .awaitingClarification:
            self = .awaitingClarification(
                options: try c.decode([ClarificationOption].self, forKey: .options))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .idle:
            try c.encode(Tag.idle, forKey: .tag)
        case .awaitingMealItems(let name):
            try c.encode(Tag.awaitingMealItems, forKey: .tag)
            try c.encode(name, forKey: .mealName)
        case .awaitingExercises:
            try c.encode(Tag.awaitingExercises, forKey: .tag)
        case .planningMeals(let name, let iter):
            try c.encode(Tag.planningMeals, forKey: .tag)
            try c.encode(name, forKey: .mealName)
            try c.encode(iter, forKey: .iteration)
        case .planningWorkout(let split, let day, let total):
            try c.encode(Tag.planningWorkout, forKey: .tag)
            try c.encode(split, forKey: .splitType)
            try c.encode(day, forKey: .currentDay)
            try c.encode(total, forKey: .totalDays)
        case .awaitingClarification(let options):
            try c.encode(Tag.awaitingClarification, forKey: .tag)
            try c.encode(options, forKey: .options)
        }
    }

    /// Human-readable description for the resume banner.
    public var resumeBlurb: String {
        switch self {
        case .idle: return "your conversation"
        case .awaitingMealItems(let mealName): return "logging your \(mealName)"
        case .awaitingExercises: return "logging your workout"
        case .planningMeals(let mealName, _): return "planning your \(mealName)"
        case .planningWorkout: return "building your workout split"
        case .awaitingClarification: return "that clarification"
        }
    }
}

// MARK: - Persisted Snapshot

/// Serializable snapshot of conversation state + AIChatViewModel pending fields.
struct PersistedConversationState: Codable, Equatable {
    var phase: ConversationState.Phase
    var lastTopic: ConversationState.Topic
    var turnCount: Int
    var pendingRecipeItems: [QuickAddView.RecipeItem]
    var pendingRecipeName: String
    var pendingExercises: [AIActionParser.WorkoutExercise]
    var savedAt: Date

    /// True when worth restoring (anything meaningful to pick up).
    var isMeaningful: Bool {
        phase != .idle || !pendingRecipeItems.isEmpty || !pendingExercises.isEmpty
    }
}
