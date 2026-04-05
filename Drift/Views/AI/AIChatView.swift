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
                        suggestionChip("Daily summary")
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    aiService.resetChat()
                    messages.removeAll()
                    messages.append(ChatMessage(role: .system, text: "I'm your health assistant. Ask me about your nutrition, weight, workouts, or say \"log food\" / \"start workout\" and I'll help."))
                    if let insight = AIRuleEngine.quickInsight() {
                        messages.append(ChatMessage(role: .assistant, text: insight))
                    }
                } label: {
                    Image(systemName: "plus.message").foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingFoodSearch) {
            NavigationStack {
                FoodSearchView(viewModel: FoodLogViewModel())
            }
        }
        .onAppear {
            if messages.isEmpty {
                messages.append(ChatMessage(role: .system, text: "I'm your health assistant. Ask me about your nutrition, weight, workouts, or say \"log food\" / \"start workout\" and I'll help."))
                // Show a quick insight on launch
                if let insight = AIRuleEngine.quickInsight() {
                    messages.append(ChatMessage(role: .assistant, text: insight))
                }
                if let next = AIRuleEngine.nextAction() {
                    messages.append(ChatMessage(role: .assistant, text: next))
                }
            }
            if aiService.state == .ready && !aiService.isModelLoaded {
                Task {
                    aiService.loadModel()
                }
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(ChatMessage(role: .user, text: text))
        inputText = ""

        // Handle rule-based queries locally (instant, no LLM needed)
        let lower = text.lowercased()
        if lower.contains("daily summary") || lower.contains("how am i doing") || lower.contains("my day") || lower.contains("today") {
            let summary = AIRuleEngine.dailySummary()
            messages.append(ChatMessage(role: .assistant, text: summary))
            return
        }
        if lower.contains("calorie") || lower.contains("how many cal") || lower.contains("macro") || lower.contains("protein") {
            let today = DateFormatters.todayString
            let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
            if nutrition.calories > 0 {
                messages.append(ChatMessage(role: .assistant, text: "Today so far: \(Int(nutrition.calories)) cal, \(Int(nutrition.proteinG))g protein, \(Int(nutrition.carbsG))g carbs, \(Int(nutrition.fatG))g fat, \(Int(nutrition.fiberG))g fiber."))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "No food logged today yet. Tap \"Log food\" to start."))
            }
            return
        }
        if lower.contains("weight") || lower.contains("how much do i weigh") {
            if let entries = try? AppDatabase.shared.fetchWeightEntries(),
               let trend = WeightTrendCalculator.calculateTrend(entries: entries.map { (date: $0.date, weightKg: $0.weightKg) }) {
                let unit = Preferences.weightUnit
                let current = String(format: "%.1f", unit.convert(fromKg: trend.currentEMA))
                let rate = String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg))
                let direction = trend.weeklyRateKg < -0.01 ? "losing" : trend.weeklyRateKg > 0.01 ? "gaining" : "maintaining"
                messages.append(ChatMessage(role: .assistant, text: "Your current weight is \(current) \(unit.displayName). You're \(direction) at \(rate) \(unit.displayName)/week."))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "No weight data yet. Log your weight in the Weight tab to start tracking."))
            }
            return
        }
        if lower.contains("yesterday") || lower.contains("what did i eat") {
            let summary = AIRuleEngine.yesterdaySummary()
            messages.append(ChatMessage(role: .assistant, text: summary))
            return
        }
        if lower.contains("log food") || lower.contains("log breakfast") || lower.contains("log lunch") || lower.contains("log dinner") || lower.contains("add food") {
            messages.append(ChatMessage(role: .assistant, text: "Opening food search for you. [LOG_FOOD: food]"))
            showingFoodSearch = true
            return
        }
        if lower.contains("start workout") || lower.contains("start a workout") || lower.contains("begin workout") {
            messages.append(ChatMessage(role: .assistant, text: "Let's get moving! Head to the Exercise tab to pick a template or start fresh."))
            return
        }

        // LLM inference
        isGenerating = true
        Task {
            let context = AIContextBuilder.buildContext()

            if aiService.state != .ready {
                // No model — use rule engine
                var response = "AI model is loading. Try asking for a \"daily summary\" in the meantime."
                if let insight = AIRuleEngine.quickInsight() {
                    response = insight
                }
                messages.append(ChatMessage(role: .assistant, text: response))
            } else {
                var response = await aiService.respond(to: text, context: context)
                if response.isEmpty { response = "I couldn't generate a response. Try again." }
                messages.append(ChatMessage(role: .assistant, text: response))
            }
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
