import Foundation

/// ViewModel for AIChatView — owns all chat state, message handling, and AI pipeline interaction.
@Observable
@MainActor
final class AIChatViewModel {
    var aiService = LocalAIService.shared
    var screenTracker = AIScreenTracker.shared
    var messages: [ChatMessage] = []
    var inputText = ""
    var generatingState: GeneratingState = .idle
    var streamingMessageId: UUID? = nil
    // Incremented on each new request, then bumped again in defer to invalidate stale onStep callbacks.
    var generationEpoch: Int = 0
    var showingFoodSearch = false
    var foodSearchQuery = ""
    var foodSearchServings: Double? = nil
    var foodSearchMealType: MealType? = nil
    var showingWorkout = false
    var workoutTemplate: WorkoutTemplate? = nil
    var convState = ConversationState.shared
    var speechService = SpeechRecognitionService.shared
    var pendingExercises: [AIActionParser.WorkoutExercise] = []
    var showingRecipeBuilder = false
    var pendingRecipeItems: [QuickAddView.RecipeItem] = []
    var pendingRecipeName = ""
    var showingBarcodeScanner = false
    var showingManualFoodEntry = false
    var pendingManualFoodEntry: ManualFoodPrefill? = nil

    var isGenerating: Bool { generatingState != .idle }

    /// Injectable for tests; production uses the shared singleton.
    let persistence: ConversationStatePersistence

    init(persistence: ConversationStatePersistence = .shared) {
        self.persistence = persistence
        restorePersistedConversation()
        // Save on scenePhase background (posted by DriftApp) — captures phases set by
        // async handlers that sendMessage's defer missed.
        NotificationCenter.default.addObserver(
            forName: .saveConversationState, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveConversationState() }
        }
    }

    /// Apply any fresh on-disk snapshot to the singleton and VM-local pending state.
    /// If the snapshot is old but non-idle, prepend a "picking up where we left off" assistant
    /// message so the user understands why context is pre-loaded.
    private func restorePersistedConversation() {
        guard let snapshot = persistence.loadIfFresh() else { return }
        convState.apply(snapshot)
        pendingRecipeItems = snapshot.pendingRecipeItems
        pendingRecipeName = snapshot.pendingRecipeName
        pendingExercises = snapshot.pendingExercises
        if persistence.shouldShowResumeBanner(snapshot) {
            messages.append(ChatMessage(
                role: .assistant,
                text: "Picking up where we left off — still want to finish \(snapshot.phase.resumeBlurb)?"))
        }
    }

    /// Snapshot current conversation state to disk. Called from `sendMessage` and scene
    /// backgrounding so mid-flow context survives app kill/relaunch.
    func saveConversationState(now: Date = Date()) {
        let snapshot = PersistedConversationState(
            phase: convState.phase,
            lastTopic: convState.lastTopic,
            turnCount: convState.turnCount,
            pendingRecipeItems: pendingRecipeItems,
            pendingRecipeName: pendingRecipeName,
            pendingExercises: pendingExercises,
            savedAt: now)
        if snapshot.isMeaningful {
            persistence.save(snapshot)
        } else {
            // Nothing worth persisting — drop any stale on-disk state so a later restore is clean.
            persistence.clear()
        }
    }

    struct ManualFoodPrefill {
        let name: String
        let calories: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        var fiberG: Double = 0
    }

    // MARK: - Types

    enum GeneratingState: Equatable {
        case idle
        case thinking(step: String)
        case generating
    }

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        var foodCard: FoodCardData?
        var weightCard: WeightCardData?
        var workoutCard: WorkoutCardData?
        var navigationCard: NavigationCardData?
        var supplementCard: SupplementCardData?
        var sleepCard: SleepCardData?
        var glucoseCard: GlucoseCardData?
        var biomarkerCard: BiomarkerCardData?
        let createdAt = Date()
        enum Role { case user, assistant }
    }

    struct FoodCardData {
        let name: String
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
        let servingText: String
    }

    struct WeightCardData {
        let value: Double
        let unit: String
        let trend: String?
    }

    struct WorkoutCardData {
        let name: String
        let durationMin: Int?
        let exerciseCount: Int?
        var muscleGroups: [String] = []
        var confirmed: Bool = true
    }

    struct NavigationCardData {
        let destination: String
        let icon: String
        let tab: Int
    }

    struct SupplementCardData {
        let taken: Int
        let total: Int
        let remaining: [String]
        let action: String?  // e.g. "Marked Creatine as taken"
    }

    struct SleepCardData {
        let sleepHours: Double?
        let remHours: Double?
        let deepHours: Double?
        let recoveryScore: Int?
        let hrvMs: Int?
        let restingHR: Int?
        let readiness: String?
    }

    struct GlucoseCardData {
        let avgMgdl: Int
        let minMgdl: Int
        let maxMgdl: Int
        let inZonePct: Int
        let readingCount: Int
        let spikeCount: Int
        let peakMgdl: Int?
    }

    struct BiomarkerCardData {
        let totalCount: Int
        let optimalCount: Int
        let outOfRange: [OutOfRangeMarker]

        struct OutOfRangeMarker {
            let name: String
            let value: String
            let status: String
        }
    }
}
