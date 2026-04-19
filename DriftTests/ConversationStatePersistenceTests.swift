import Foundation
import Testing
@testable import Drift

// MARK: - Phase Codable round-trip

@Test @MainActor func phaseIdleRoundTrip() throws {
    let phase = ConversationState.Phase.idle
    let data = try JSONEncoder().encode(phase)
    let decoded = try JSONDecoder().decode(ConversationState.Phase.self, from: data)
    #expect(decoded == .idle)
}

@Test @MainActor func phaseAwaitingMealItemsRoundTrip() throws {
    let phase = ConversationState.Phase.awaitingMealItems(mealName: "dinner")
    let data = try JSONEncoder().encode(phase)
    let decoded = try JSONDecoder().decode(ConversationState.Phase.self, from: data)
    #expect(decoded == .awaitingMealItems(mealName: "dinner"))
}

@Test @MainActor func phaseAwaitingExercisesRoundTrip() throws {
    let phase = ConversationState.Phase.awaitingExercises
    let data = try JSONEncoder().encode(phase)
    let decoded = try JSONDecoder().decode(ConversationState.Phase.self, from: data)
    #expect(decoded == .awaitingExercises)
}

@Test @MainActor func phasePlanningMealsRoundTrip() throws {
    let phase = ConversationState.Phase.planningMeals(mealName: "lunch", iteration: 2)
    let data = try JSONEncoder().encode(phase)
    let decoded = try JSONDecoder().decode(ConversationState.Phase.self, from: data)
    #expect(decoded == .planningMeals(mealName: "lunch", iteration: 2))
}

@Test @MainActor func phasePlanningWorkoutRoundTrip() throws {
    let phase = ConversationState.Phase.planningWorkout(splitType: "PPL", currentDay: 1, totalDays: 6)
    let data = try JSONEncoder().encode(phase)
    let decoded = try JSONDecoder().decode(ConversationState.Phase.self, from: data)
    #expect(decoded == .planningWorkout(splitType: "PPL", currentDay: 1, totalDays: 6))
}

// MARK: - PersistedConversationState round-trip

@Test @MainActor func persistedStateRoundTripIncludesPendingArrays() throws {
    let recipeItem = QuickAddView.RecipeItem(
        name: "Coffee (black)", portionText: "240 ml",
        calories: 5, proteinG: 0.3, carbsG: 0, fatG: 0, fiberG: 0, servingSizeG: 240)
    let exercise = AIActionParser.WorkoutExercise(name: "Bench", sets: 3, reps: 10, weight: 135)
    let snapshot = PersistedConversationState(
        phase: .awaitingMealItems(mealName: "breakfast"),
        lastTopic: .food,
        turnCount: 3,
        pendingRecipeItems: [recipeItem],
        pendingRecipeName: "Breakfast",
        pendingExercises: [exercise],
        savedAt: Date(timeIntervalSince1970: 1_700_000_000))

    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let data = try enc.encode(snapshot)
    let decoded = try dec.decode(PersistedConversationState.self, from: data)

    #expect(decoded.phase == .awaitingMealItems(mealName: "breakfast"))
    #expect(decoded.lastTopic == .food)
    #expect(decoded.turnCount == 3)
    #expect(decoded.pendingRecipeItems.count == 1)
    #expect(decoded.pendingRecipeItems.first?.name == "Coffee (black)")
    #expect(decoded.pendingRecipeItems.first?.servingSizeG == 240)
    #expect(decoded.pendingRecipeName == "Breakfast")
    #expect(decoded.pendingExercises.count == 1)
    #expect(decoded.pendingExercises.first?.name == "Bench")
    #expect(decoded.savedAt.timeIntervalSince1970 == 1_700_000_000)
}

@Test @MainActor func isMeaningfulReturnsFalseForEmptyIdle() {
    let snapshot = PersistedConversationState(
        phase: .idle, lastTopic: .unknown, turnCount: 0,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [], savedAt: Date())
    #expect(!snapshot.isMeaningful)
}

@Test @MainActor func isMeaningfulReturnsTrueWhenPhaseNonIdle() {
    let snapshot = PersistedConversationState(
        phase: .awaitingExercises, lastTopic: .exercise, turnCount: 1,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [], savedAt: Date())
    #expect(snapshot.isMeaningful)
}

@Test @MainActor func isMeaningfulReturnsTrueWhenPendingRecipeItemsPresent() {
    let item = QuickAddView.RecipeItem(
        name: "Chicken", portionText: "100 g",
        calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6, fiberG: 0, servingSizeG: 100)
    let snapshot = PersistedConversationState(
        phase: .idle, lastTopic: .food, turnCount: 0,
        pendingRecipeItems: [item], pendingRecipeName: "Lunch", pendingExercises: [], savedAt: Date())
    #expect(snapshot.isMeaningful)
}

// MARK: - ConversationStatePersistence save / load / expire / clear

@MainActor
private func makeTempPersistence() -> ConversationStatePersistence {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("conv_state_\(UUID().uuidString).json")
    return ConversationStatePersistence(fileURL: tmp)
}

@Test @MainActor func persistenceSaveAndLoadRoundTrip() {
    let persistence = makeTempPersistence()
    defer { persistence.clear() }
    let snapshot = PersistedConversationState(
        phase: .planningMeals(mealName: "dinner", iteration: 1),
        lastTopic: .food, turnCount: 5,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [], savedAt: Date())

    persistence.save(snapshot)
    let loaded = persistence.loadIfFresh()
    #expect(loaded != nil)
    #expect(loaded?.phase == .planningMeals(mealName: "dinner", iteration: 1))
    #expect(loaded?.turnCount == 5)
}

@Test @MainActor func persistenceLoadIfFreshReturnsNilForExpiredState() {
    let persistence = makeTempPersistence()
    defer { persistence.clear() }
    let oldSnapshot = PersistedConversationState(
        phase: .awaitingExercises, lastTopic: .exercise, turnCount: 1,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [],
        savedAt: Date(timeIntervalSinceNow: -(ConversationStatePersistence.maxAge + 1)))
    persistence.save(oldSnapshot)
    #expect(persistence.loadIfFresh() == nil)
    // Expired load should also have cleared the file.
    #expect(persistence.loadRaw() == nil)
}

@Test @MainActor func persistenceLoadReturnsNilAfterClear() {
    let persistence = makeTempPersistence()
    let snapshot = PersistedConversationState(
        phase: .awaitingExercises, lastTopic: .exercise, turnCount: 1,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [], savedAt: Date())
    persistence.save(snapshot)
    persistence.clear()
    #expect(persistence.loadIfFresh() == nil)
}

@Test @MainActor func persistenceLoadReturnsNilWhenNoFileExists() {
    let persistence = makeTempPersistence()
    #expect(persistence.loadIfFresh() == nil)
}

// MARK: - Resume banner age threshold

@Test @MainActor func shouldShowResumeBannerFalseWhenFresh() {
    let persistence = makeTempPersistence()
    let snapshot = PersistedConversationState(
        phase: .awaitingExercises, lastTopic: .exercise, turnCount: 1,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [],
        savedAt: Date(timeIntervalSinceNow: -60)) // 1 min old
    #expect(!persistence.shouldShowResumeBanner(snapshot))
}

@Test @MainActor func shouldShowResumeBannerTrueWhenAgedAndNonIdle() {
    let persistence = makeTempPersistence()
    let snapshot = PersistedConversationState(
        phase: .awaitingMealItems(mealName: "breakfast"),
        lastTopic: .food, turnCount: 1,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [],
        savedAt: Date(timeIntervalSinceNow: -(ConversationStatePersistence.resumeBannerMinAge + 1)))
    #expect(persistence.shouldShowResumeBanner(snapshot))
}

@Test @MainActor func shouldShowResumeBannerFalseWhenIdleEvenIfOld() {
    let persistence = makeTempPersistence()
    let snapshot = PersistedConversationState(
        phase: .idle, lastTopic: .unknown, turnCount: 0,
        pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [],
        savedAt: Date(timeIntervalSinceNow: -(ConversationStatePersistence.resumeBannerMinAge + 10)))
    #expect(!persistence.shouldShowResumeBanner(snapshot))
}

// MARK: - VM apply restores state
// Tests in this suite mutate ConversationState.shared; serialize to avoid
// cross-test interference and always restore the phase on exit.

@Suite(.serialized) @MainActor
struct ConversationStateVMIntegration {
    @Test func viewModelRestoresFreshSnapshotOnInit() {
        ConversationState.shared.reset()
        let persistence = makeTempPersistence()
        defer { persistence.clear(); ConversationState.shared.reset() }
        let recipeItem = QuickAddView.RecipeItem(
            name: "Dal", portionText: "1 cup",
            calories: 200, proteinG: 12, carbsG: 30, fatG: 3, fiberG: 8, servingSizeG: 200)
        let snapshot = PersistedConversationState(
            phase: .awaitingMealItems(mealName: "lunch"),
            lastTopic: .food, turnCount: 2,
            pendingRecipeItems: [recipeItem], pendingRecipeName: "Lunch", pendingExercises: [],
            savedAt: Date(timeIntervalSinceNow: -30))
        persistence.save(snapshot)

        let vm = AIChatViewModel(persistence: persistence)
        #expect(vm.pendingRecipeItems.count == 1)
        #expect(vm.pendingRecipeItems.first?.name == "Dal")
        #expect(vm.pendingRecipeName == "Lunch")
        #expect(vm.convState.phase == .awaitingMealItems(mealName: "lunch"))
    }

    @Test func viewModelSaveClearsWhenIdleAndEmpty() {
        ConversationState.shared.reset()
        let persistence = makeTempPersistence()
        defer { persistence.clear(); ConversationState.shared.reset() }
        // Pre-populate an old snapshot
        let old = PersistedConversationState(
            phase: .awaitingExercises, lastTopic: .exercise, turnCount: 1,
            pendingRecipeItems: [], pendingRecipeName: "", pendingExercises: [],
            savedAt: Date(timeIntervalSinceNow: -10))
        persistence.save(old)
        #expect(persistence.loadRaw() != nil)

        // VM with idle conversation state, empty pending arrays — save should clear the file.
        let vm = AIChatViewModel(persistence: persistence)
        vm.convState.phase = .idle
        vm.pendingRecipeItems = []
        vm.pendingRecipeName = ""
        vm.pendingExercises = []
        vm.saveConversationState()
        #expect(persistence.loadRaw() == nil)
    }
}
