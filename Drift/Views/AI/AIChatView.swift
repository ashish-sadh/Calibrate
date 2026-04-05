import SwiftUI

struct AIChatView: View {
    @State private var aiService = LocalAIService.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showingFoodSearch = false
    @State private var showingWorkoutStart = false
    @State private var actionFoodName = ""
    @State private var actionWorkoutType: String?
    @FocusState private var inputFocused: Bool

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        let timestamp = Date()

        enum Role { case user, assistant, system }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Thinking...").font(.caption).foregroundStyle(.tertiary)
                            }
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }


            }

            // Quick suggestion chips
            if !isGenerating && messages.count <= 3 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        suggestionChip("How am I doing today?")
                        suggestionChip("Log breakfast")
                        suggestionChip("Start a workout")
                        suggestionChip("What should I eat?")
                        suggestionChip("Weekly summary")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Ask about your health...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }

                if isGenerating {
                    Button { aiService.stop() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.surplus)
                    }
                } else {
                    Button { sendMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(inputText.isEmpty ? Color.gray : Theme.accent)
                    }
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
        }
        .background(Theme.background)
        .navigationTitle("Drift AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingFoodSearch) {
            NavigationStack {
                FoodSearchView(viewModel: FoodLogViewModel())
            }
        }
        .onAppear {
            if messages.isEmpty {
                messages.append(ChatMessage(role: .system, text: "I'm your health assistant. Ask me about your nutrition, weight, workouts, or say \"log food\" / \"start workout\" and I'll help."))
            }
            if aiService.state == .ready && !aiService.isModelDownloaded {
                // Model was deleted
            } else if aiService.state == .ready {
                aiService.loadModel()
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(ChatMessage(role: .user, text: text))
        inputText = ""
        isGenerating = true

        Task {
            let context = AIContextBuilder.buildContext()

            var response = await aiService.respond(to: text, context: context)
            if response.isEmpty { response = "I couldn't generate a response. Try again." }

            messages.append(ChatMessage(role: .assistant, text: response))
            isGenerating = false
        }
    }

    // MARK: - Message Bubble

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.cardBackgroundElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch message.role {
            case .user:
                Spacer()
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.primary)

            case .assistant:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 4)
                        let parsed = AIActionParser.parse(message.text)
                        Text(parsed.cleanText.isEmpty ? message.text : parsed.cleanText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    // Action buttons
                    let action = AIActionParser.parse(message.text).action
                    switch action {
                    case .logFood(let name, _):
                        Button {
                            // Pre-fill food search with the name
                            actionFoodName = name
                            showingFoodSearch = true
                        } label: {
                            Label("Log \(name)", systemImage: "plus.circle")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered).tint(Theme.accent)
                    case .startWorkout(let type):
                        Button {
                            actionWorkoutType = type
                            showingWorkoutStart = true
                        } label: {
                            Label("Start \(type ?? "Workout")", systemImage: "figure.run")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered).tint(Theme.deficit)
                    default:
                        EmptyView()
                    }
                }
                Spacer()

            case .system:
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.accent.opacity(0.6))
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
    }
}
