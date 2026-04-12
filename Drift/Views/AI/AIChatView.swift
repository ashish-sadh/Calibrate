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
    @State var showingWorkout = false
    @State var workoutTemplate: WorkoutTemplate? = nil
    @State var pendingExercises: [AIActionParser.WorkoutExercise] = []
    @State var pendingMealName: String? = nil
    @State var pendingWorkoutLog = false
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
        enum Role { case user, assistant }
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
                        if case .thinking = generatingState {
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

                TextField("Ask anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline)
                    .lineLimit(1...3).focused($inputFocused)
                    .onSubmit { sendMessage() }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(inputText.isEmpty ? Color.gray.opacity(0.5) : Theme.accent)
                }
                .disabled(inputText.isEmpty || isGenerating)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 8).padding(.bottom, 4)
        }
        .sheet(isPresented: $showingFoodSearch) {
            NavigationStack {
                FoodSearchView(viewModel: FoodLogViewModel(), initialQuery: foodSearchQuery, initialServings: foodSearchServings)
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
        .sheet(isPresented: $showingRecipeBuilder) {
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 10))
                .foregroundStyle(Theme.accent).padding(.top, 4)
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
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .transition(.opacity)
    }

    // Message handling, conversation history, and intent parsing in AIChatView+MessageHandling.swift
    // Smart suggestions, page insight, and fallback responses in AIChatView+Suggestions.swift

    // MARK: - Message Bubble

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .user { Spacer() }

            if msg.role == .assistant {
                Image(systemName: "sparkles").font(.system(size: 10))
                    .foregroundStyle(Theme.accent).padding(.top, 4)
            }

            Text(msg.text)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    msg.role == .user
                        ? Theme.accent.opacity(0.18)
                        : Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .accessibilityLabel(msg.role == .user ? "You said: \(msg.text)" : "Assistant: \(msg.text)")

            if msg.role == .assistant { Spacer() }
        }
        .padding(.horizontal, 10)
    }
}
