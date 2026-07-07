import Foundation
import DriftCore

/// ViewModel for AIChatView — owns all chat state, message handling, and AI pipeline interaction.
@Observable
@MainActor
final class AIChatViewModel {
    var aiService = LocalAIService.shared
    var screenTracker = AIScreenTracker.shared
    var messages: [ChatMessage] = []
    var inputText = ""
    var generatingState: GeneratingState = .idle
    var stageStarted: Date? = nil
    var streamingMessageId: UUID? = nil
    // Incremented on each new request, then bumped again in defer to invalidate stale onStep callbacks.
    var generationEpoch: Int = 0
    var showingFoodSearch = false
    var foodSearchQuery = ""
    var foodSearchServings: Double? = nil
    /// Exact food name the Coach preview card resolved to — the confirm sheet
    /// pre-selects this row so preview and sheet never disagree (#930).
    var foodSearchResolvedName: String? = nil
    var foodSearchMealType: MealType? = nil
    var showingWorkout = false
    var workoutTemplate: WorkoutTemplate? = nil
    var convState = ConversationState.shared
    var speechService = SpeechRecognitionService.shared
    /// On-device TTS for voice talk-mode. When `voiceOutputEnabled`, the coach
    /// speaks each reply aloud after it finalizes. #coach-rework.
    var voiceService = CoachVoiceService.shared
    var pendingExercises: [AIActionParser.WorkoutExercise] = []
    var showingRecipeBuilder = false
    var pendingRecipeItems: [QuickAddView.RecipeItem] = []
    var pendingRecipeName = ""
    var showingBarcodeScanner = false
    var showingManualFoodEntry = false
    var pendingManualFoodEntry: ManualFoodPrefill? = nil
    /// "Log my usual lunch" → the editable review sheet (Snap's surface), seeded
    /// with the recalled meal. #usual-meal
    var showingMealReview = false
    var pendingMealReviewItems: [PhotoLogItem] = []

    var isGenerating: Bool { generatingState != .idle }
    /// Bumped when a food logging sheet dismisses so suggestion pills re-evaluate.
    var mealLogRevision = 0
    /// True when the current turn includes a photo attachment. Local backend has
    /// no vision, so this overrides isFallbackable to prevent auto-fallback. #519 Q7.
    var pendingTurnHasPhoto: Bool = false
    /// JPEG bytes of the photo the user has selected but not yet sent.
    var pendingPhotoData: Data? = nil
    /// ID of the assistant message that currently holds a ProposedMealCardData,
    /// so correction turns can replace the card in place.
    var pendingProposalTurnId: UUID? = nil
    /// Entry IDs logged by the most recent meal-card confirm, held for 10s undo.
    var pendingUndoEntryIds: [Int64] = []

    /// True when both local and remote BYOK backends are configured. Drives
    /// the selector visibility; with only one backend the selector is hidden.
    var canToggleBackend: Bool { AIBackendCoordinator.bothBackendsAvailable }

    /// Stored so @Observable tracks it and re-renders the selector on change.
    /// Initialized from persisted preference; updated synchronously in toggleBackend()
    /// before the async backend swap so the UI responds immediately. #540.
    var activeBackend: AIBackendType = Preferences.preferredAIBackend

    /// Flip the backend. Updates the stored property immediately (triggers
    /// @Observable re-render), persists the preference, then applies it async.
    func toggleBackend(to backend: AIBackendType? = nil) {
        guard !isGenerating else { return }
        let next: AIBackendType = backend ?? (activeBackend == .remote ? .llamaCpp : .remote)
        activeBackend = next
        Preferences.preferredAIBackend = next
        Task { await AIBackendCoordinator.applyPreferredBackend() }
    }

    /// Whether the coach speaks replies aloud. Stored (not computed) so
    /// @Observable re-renders the input-bar toggle; mirrored to Preferences.
    var voiceOutputEnabled: Bool = Preferences.coachVoiceEnabled

    /// Flip voice talk-mode. Persists the preference; silences any in-flight
    /// speech when turning off.
    func toggleVoiceOutput() {
        voiceOutputEnabled.toggle()
        Preferences.coachVoiceEnabled = voiceOutputEnabled
        if !voiceOutputEnabled { voiceService.stop() }
    }

    /// Immersive talk-mode master switch (the top speaker button). When ON, the
    /// coach shows the full-screen tap-to-talk circle and runs the hands-free
    /// loop; it's a superset of voice-output, so enabling it implies spoken
    /// replies. Persisted so it survives sheet dismiss/re-present. #coach-talk-mode
    var talkModeEnabled: Bool = Preferences.coachTalkModeEnabled

    /// Flip immersive talk-mode. Turning ON also enables voice replies; turning
    /// OFF silences speech and stops any active recording so the mic doesn't keep
    /// listening behind the text UI.
    func toggleTalkMode() {
        talkModeEnabled.toggle()
        Preferences.coachTalkModeEnabled = talkModeEnabled
        if talkModeEnabled {
            if !voiceOutputEnabled {
                voiceOutputEnabled = true
                Preferences.coachVoiceEnabled = true
            }
        } else {
            voiceService.stop()
            speechService.forceStop()
        }
    }

    /// Speak a finalized assistant reply aloud when voice mode is on. No-op
    /// otherwise. Called from the message-completion seam.
    func speakReply(_ text: String) {
        guard voiceOutputEnabled else { return }
        voiceService.speak(text)
    }

    /// True for one turn when the message came from the mic — drives the
    /// speak-the-action + keep-listening loop. Reset once the turn is handled.
    var lastTurnWasVoice = false

    /// Bumped to ask the View to re-open the mic after the coach finishes
    /// speaking (hands-free continuation). The View owns the audio engine; the
    /// VM only signals — keeps the audio handoff (TTS → record) on one side.
    var rearmMicTick = 0

    /// Short spoken acknowledgement when an action opens mid-voice-turn, so the
    /// coach says what it's doing instead of a silent sheet. #coach-keep-listening
    func actionAckPhrase(for action: ToolAction) -> String {
        switch action {
        case .openFoodSearch, .openManualFoodEntry, .openRecipeBuilder:
            return "Opening add item — keep talking."
        case .openWorkout:        return "Starting your workout."
        case .openWeightEntry:    return "Opening weight entry."
        case .openBarcodeScanner: return "Opening the scanner."
        case .navigate:           return ""
        }
    }

    /// Speak a VOICE turn's reply (+ any action ack) as ONE utterance, then signal
    /// the View to re-arm the mic so the user keeps talking hands-free. No-op when
    /// voice output is off (the user muted) — they can re-tap to continue.
    func speakVoiceTurn(reply: String, action: ToolAction?) {
        guard voiceOutputEnabled else { return }
        let ack = action.map { actionAckPhrase(for: $0) } ?? ""
        let utterance = [reply, ack].filter { !$0.isEmpty }.joined(separator: " ")
        guard !utterance.isEmpty else { rearmMicTick += 1; return }
        voiceService.speak(utterance) { [weak self] in self?.rearmMicTick += 1 }
    }

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
            persistence.clear()
        }
        let turns = messages.map { HistoryTurn(role: $0.role == .user ? .user : .assistant, text: $0.text) }
        CrossSessionHistory.save(turns)
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
        var nutritionCard: NutritionLookupCardData?
        var weightCard: WeightCardData?
        var workoutCard: WorkoutCardData?
        var navigationCard: NavigationCardData?
        var supplementCard: SupplementCardData?
        var medicationCard: MedicationCardData?
        var sleepCard: SleepCardData?
        var glucoseCard: GlucoseCardData?
        var biomarkerCard: BiomarkerCardData?
        var helpCard: HelpCardData?
        /// When the assistant asked "Did you mean X or Y?" — each option
        /// rendered as a tappable chip. Tapping sends the label as a new
        /// user message; the VM resolves it against the active phase. #226.
        var clarificationOptions: [ClarificationOption]?
        /// Non-nil when a cloud backend handled this turn ("Anthropic", "OpenAI",
        /// "Gemini"). Nil means on-device — silence = privacy by default. #533.
        var remoteProvider: String?
        /// Non-nil when the assistant message shows a remote error. Stores the
        /// original user turn text so the Retry chip can re-send it. #519 Q7.
        var retryTurn: String?
        /// JPEG bytes attached by the user. Displayed as a thumbnail in the
        /// user bubble; sent to the remote backend as a vision turn. #518.
        var photoAttachment: Data?
        /// Inline proposed-meal card emitted by the AI via propose_meal. #518.
        var proposedMealCard: ProposedMealCardData?
        let createdAt = Date()
        enum Role { case user, assistant }
    }

    struct ProposedMealCardData {
        struct Item: Identifiable {
            var id = UUID()
            var name: String
            var grams: Int
            var calories: Int
            var protein: Int
            var carbs: Int
            var fat: Int
        }
        var items: [Item]
    }

    struct NutritionLookupCardData {
        let name: String
        let calories100g: Int
        let proteinG100g: Int
        let carbsG100g: Int
        let fatG100g: Int
        let servingSize: Int
        let servingUnit: String
        let servingCalories: Int
        let servingProteinG: Int
        let servingCarbsG: Int
        let servingFatG: Int
    }

    struct FoodCardData {
        let name: String
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
        let servingText: String
        var mealType: MealType = .snack
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

    struct MedicationCardData {
        let name: String
        let doseDisplay: String?   // e.g. "0.5mg" or nil
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
