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

    var isGenerating: Bool { generatingState != .idle }

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
        var confirmed: Bool = true
    }

    struct NavigationCardData {
        let destination: String
        let icon: String
        let tab: Int
    }
}
