import SwiftUI
import PhotosUI

/// Chat-style AI assistant with chain-of-thought reasoning and smart suggestion pills.
struct AIChatView: View {
    @State var aiService = LocalAIService.shared
    @State var screenTracker = AIScreenTracker.shared
    @State var messages: [ChatMessage] = []
    @State var inputText = ""
    @State var generatingState: GeneratingState = .idle
    @State var streamingMessageId: UUID? = nil
    @State var showingFoodSearch = false
    @State var foodSearchQuery = ""
    @State var foodSearchServings: Double? = nil
    @State var foodSearchMealType: MealType? = nil
    @State var showingWorkout = false
    @State var workoutTemplate: WorkoutTemplate? = nil
    @State var convState = ConversationState.shared
    @State var speechService = SpeechRecognitionService.shared
    @State var pendingExercises: [AIActionParser.WorkoutExercise] = []
    @State var showingRecipeBuilder = false
    @State var pendingRecipeItems: [QuickAddView.RecipeItem] = []
    @State var pendingRecipeName = ""
    @State var showingBarcodeScanner = false
    @FocusState var inputFocused: Bool

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
        let trend: String?     // e.g. "↓ 0.3 lbs this week"
    }

    struct WorkoutCardData {
        let name: String
        let durationMin: Int?
        let exerciseCount: Int?
    }

    struct NavigationCardData {
        let destination: String
        let icon: String
        let tab: Int
    }

    var isGenerating: Bool { generatingState != .idle }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        if isGenerating {
                            thinkingIndicator
                        }
                    }
                    .padding(.top, 6)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: messages.last?.text) { _, _ in
                    // Also scroll during streaming as text grows
                    if streamingMessageId != nil, let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Model loading indicator — shown when model is reloading after idle unload
            if case .loading = aiService.state {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Preparing AI assistant...")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            // Smart suggestion pills
            if !isGenerating {
                suggestionsRow
            }

            Divider().overlay(Color.white.opacity(0.06))

            // Disclaimer note
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text("Small on-device model \u{2014} responses may not be perfect. Data never leaves your phone. Thank you for testing! Next release will be faster and smarter. Turn off in More \u{2192} Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.03))

            // Input bar
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent.opacity(0.6))

                TextField(speechService.isRecording ? "Listening..." : "Ask anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline)
                    .lineLimit(1...3).focused($inputFocused)
                    .onSubmit { sendMessage() }

                if speechService.isRecording {
                    // While recording: stop button to edit, send button to send
                    Button {
                        speechService.forceStop()
                        // Text stays in inputText for editing
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }

                    Button {
                        speechService.gracefulStop()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    }
                } else {
                    // Idle: mic button + send button
                    Button {
                        speechService.toggleRecording(
                            onTranscript: { [self] text in
                                inputText = text
                            },
                            onDone: { [self] finalText in
                                inputText = finalText
                                sendMessage()
                            }
                        )
                    } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.gray.opacity(0.6))
                    }
                    .disabled(isGenerating)

                    Button { sendMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                            .foregroundStyle(inputText.isEmpty ? Color.gray.opacity(0.5) : Theme.accent)
                    }
                    .disabled(inputText.isEmpty || isGenerating)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(speechService.isRecording ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1.5)
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: speechService.isRecording)
            .padding(.horizontal, 8).padding(.bottom, 4)
        }
        .sheet(isPresented: $showingFoodSearch) {
            NavigationStack {
                FoodSearchView(viewModel: FoodLogViewModel(), initialQuery: foodSearchQuery, initialServings: foodSearchServings, initialMealType: foodSearchMealType)
            }
        }
        .sheet(isPresented: $showingWorkout) {
            if let template = workoutTemplate {
                NavigationStack {
                    ActiveWorkoutView(template: template) {
                        showingWorkout = false
                        workoutTemplate = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingBarcodeScanner) {
            BarcodeLookupView(viewModel: FoodLogViewModel())
        }
        .sheet(isPresented: $showingRecipeBuilder, onDismiss: {
            pendingRecipeItems = []
            pendingRecipeName = ""
        }) {
            QuickAddView(viewModel: FoodLogViewModel(),
                         initialItems: pendingRecipeItems,
                         initialName: pendingRecipeName)
        }
        .onAppear {
            aiService.cancelUnload()  // User is here — don't unload
            if messages.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: pageInsight))
            }
            if !aiService.isModelLoaded && aiService.state == .ready {
                aiService.loadModel()
            }
        }
        .onDisappear {
            aiService.scheduleUnload(delay: 60)  // Unload after 60s away — frees ~3GB GPU
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                TypingDotsView()
                switch generatingState {
                case .thinking(let step):
                    Text(step).font(.caption2).foregroundStyle(.tertiary)
                case .generating:
                    Text("Writing response...").font(.caption2).foregroundStyle(.tertiary)
                case .idle:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.cardBackground, in: UnevenRoundedRectangle(
                topLeadingRadius: 16, bottomLeadingRadius: 4,
                bottomTrailingRadius: 16, topTrailingRadius: 16
            ))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 10)
        .transition(.opacity)
    }

    // Message handling, conversation history, and intent parsing in AIChatView+MessageHandling.swift
    // Smart suggestions, page insight, and fallback responses in AIChatView+Suggestions.swift

    // MARK: - Typewriter Text

    /// Reveals text character-by-character for non-streamed assistant messages.
    /// Streamed messages already animate via token callbacks — this handles instant responses.
    private struct TypewriterText: View {
        let text: String
        @State private var revealed: Int = 0
        @State private var done = false

        var body: some View {
            Text(done ? text : String(text.prefix(revealed)))
                .onAppear {
                    guard !text.isEmpty, !done else { return }
                    let total = text.count
                    let charsPerTick = max(1, total / 40)
                    Task {
                        while revealed < total {
                            try? await Task.sleep(for: .milliseconds(18))
                            revealed = min(revealed + charsPerTick, total)
                        }
                        done = true
                    }
                }
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if msg.role == .user {
                Spacer(minLength: 60)
            }

            if msg.role == .assistant {
                Image(systemName: "sparkles").font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, height: 20)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .padding(.bottom, 2)
            }

            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 6) {
                if !msg.text.isEmpty {
                    let isNewInstant = msg.role == .assistant
                        && msg.id != streamingMessageId
                        && Date().timeIntervalSince(msg.createdAt) < 1.0
                    Group {
                        if isNewInstant {
                            TypewriterText(text: msg.text)
                        } else {
                            Text(msg.text)
                        }
                    }
                        .font(.subheadline)
                        .foregroundStyle(msg.role == .user ? .white : Theme.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            msg.role == .user
                                ? AnyShapeStyle(Theme.accent.opacity(0.25))
                                : AnyShapeStyle(Theme.cardBackground),
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: msg.role == .user ? 16 : 4,
                                bottomTrailingRadius: msg.role == .user ? 4 : 16,
                                topTrailingRadius: 16
                            )
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: msg.role == .user ? 16 : 4,
                                bottomTrailingRadius: msg.role == .user ? 4 : 16,
                                topTrailingRadius: 16
                            )
                            .strokeBorder(
                                msg.role == .user
                                    ? Theme.accent.opacity(0.15)
                                    : Theme.separator,
                                lineWidth: 0.5
                            )
                        )
                }

                if let card = msg.foodCard {
                    foodConfirmationCard(card)
                }
                if let card = msg.weightCard {
                    weightConfirmationCard(card)
                }
                if let card = msg.workoutCard {
                    workoutConfirmationCard(card)
                }
                if let card = msg.navigationCard {
                    navigationConfirmationCard(card)
                }
            }
            .accessibilityLabel(msg.role == .user ? "You said: \(msg.text)" : "Assistant: \(msg.text)")

            if msg.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Food Confirmation Card

    private func foodConfirmationCard(_ card: FoodCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife")
                    .font(.caption).foregroundStyle(Theme.calorieBlue)
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(card.servingText)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(card.calories)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.calorieBlue)
                    Text("cal").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.proteinG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.proteinRed)
                    Text("protein").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.carbsG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.carbsGreen)
                    Text("carbs").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.fatG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.fatYellow)
                    Text("fat").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.calorieBlue.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Weight Confirmation Card

    private func weightConfirmationCard(_ card: WeightCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", card.value)) \(card.unit)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if let trend = card.trend {
                    Text(trend)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Workout Confirmation Card

    private func workoutConfirmationCard(_ card: WorkoutCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3).foregroundStyle(Theme.accentSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.subheadline.weight(.bold))
                HStack(spacing: 8) {
                    if let mins = card.durationMin {
                        Label("\(mins) min", systemImage: "clock")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let count = card.exerciseCount {
                        Label("\(count) exercises", systemImage: "list.bullet")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accentSecondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Navigation Confirmation Card

    private func navigationConfirmationCard(_ card: NavigationCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: card.icon)
                .font(.title3).foregroundStyle(Theme.accent)
            Text(card.destination)
                .font(.subheadline.weight(.bold))
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(Theme.accent.opacity(0.6)).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }
}
