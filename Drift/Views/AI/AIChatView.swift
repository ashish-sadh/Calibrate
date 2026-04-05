import SwiftUI
import PhotosUI

/// Chat-style AI assistant with smart suggestion pills.
struct AIChatView: View {
    var currentTab: Int = 0
    @State private var aiService = LocalAIService.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showingFoodSearch = false
    @State private var foodSearchQuery = ""
    @State private var foodSearchServings: Double? = nil
    @FocusState private var inputFocused: Bool

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        enum Role { case user, assistant }
    }

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
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6)
                                Text("Thinking...").font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                            }.padding(.horizontal, 14)
                        }
                    }
                    .padding(.top, 6)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Smart suggestion pills
            if !isGenerating {
                suggestionsRow
            }

            Divider().overlay(Color.white.opacity(0.06))

            // Input bar
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline)
                    .lineLimit(1...3).focused($inputFocused)
                    .onSubmit { sendMessage() }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title3)
                        .foregroundStyle(inputText.isEmpty ? Color.gray : Theme.accent)
                }
                .disabled(inputText.isEmpty || isGenerating)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .sheet(isPresented: $showingFoodSearch) {
            NavigationStack {
                FoodSearchView(viewModel: FoodLogViewModel(), initialQuery: foodSearchQuery, initialServings: foodSearchServings)
            }
        }
        .onAppear {
            if messages.isEmpty {
                let insight = pageInsight
                messages.append(ChatMessage(role: .assistant, text: insight))
            }
            if aiService.isModelLoaded == false && aiService.state == .ready {
                aiService.loadModel()
            }
        }
    }

    // MARK: - Smart Suggestions (contextual pills)

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(smartSuggestions, id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                        sendMessage()
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private var smartSuggestions: [String] {
        var pills: [String] = []
        let today = DateFormatters.todayString
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
        let hour = Calendar.current.component(.hour, from: Date())

        // Food-based suggestions
        if nutrition.calories == 0 {
            pills.append(hour < 11 ? "Log breakfast" : hour < 15 ? "Log lunch" : "Log dinner")
        } else {
            pills.append("How's my protein?")
            if hour > 17 { pills.append("What should I eat for dinner?") }
        }

        // Always useful
        pills.append("Daily summary")

        // Weight context
        if currentTab == 1 {
            pills.append("Am I on track?")
        }

        // Workout context
        if currentTab == 3 {
            pills.append("What should I train?")
        }

        // General
        if nutrition.calories > 0 {
            pills.append("Calories left today?")
        }

        return pills
    }

    // MARK: - Page Insight

    private var pageInsight: String {
        switch currentTab {
        case 0: return AIRuleEngine.quickInsight() ?? "How can I help you today?"
        case 1:
            if let entries = try? AppDatabase.shared.fetchWeightEntries(),
               let trend = WeightTrendCalculator.calculateTrend(entries: entries.map { ($0.date, $0.weightKg) }) {
                let u = Preferences.weightUnit
                return "You're at \(String(format: "%.1f", u.convert(fromKg: trend.currentEMA))) \(u.displayName), \(trend.weeklyRateKg < -0.01 ? "losing" : trend.weeklyRateKg > 0.01 ? "gaining" : "maintaining"). What would you like to know?"
            }
            return "How can I help with your weight tracking?"
        case 2:
            let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
            return n.calories > 0 ? "You've eaten \(Int(n.calories)) cal today. What would you like to log?" : "No food logged yet. What did you have?"
        case 3: return "Ready for a workout? Tell me what you want to train."
        default: return "How can I help?"
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, text: text))

        let lower = text.lowercased()

        // Rule engine: instant data queries
        if lower.contains("summary") || lower.contains("how am i") || lower.contains("my day") {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.dailySummary()))
            return
        }
        if lower.contains("yesterday") || lower.contains("what did i eat") {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.yesterdaySummary()))
            return
        }
        if (lower.contains("calorie") || lower.contains("protein") || lower.contains("macro")) && !lower.contains("how many") {
            let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
            messages.append(ChatMessage(role: .assistant, text: n.calories > 0
                ? "Today: \(Int(n.calories)) cal, \(Int(n.proteinG))g protein, \(Int(n.carbsG))g carbs, \(Int(n.fatG))g fat."
                : "No food logged today yet."))
            return
        }

        // Food intent: "log 2 eggs", "ate avocado"
        if let intent = AIActionExecutor.parseFoodIntent(lower) {
            foodSearchQuery = intent.query
            foodSearchServings = intent.servings
            messages.append(ChatMessage(role: .assistant, text: "Opening \(intent.query)..."))
            showingFoodSearch = true
            return
        }

        // Generic "log food/breakfast/lunch"
        if lower.contains("log food") || lower.contains("log breakfast") || lower.contains("log lunch") || lower.contains("log dinner") {
            messages.append(ChatMessage(role: .assistant, text: "What did you eat?"))
            return
        }

        // LLM for everything else
        if !aiService.isModelLoaded {
            messages.append(ChatMessage(role: .assistant, text: "AI is still setting up. Try \"daily summary\", \"log 2 eggs\", or \"calories\"."))
            return
        }

        isGenerating = true
        Task {
            let context = AIContextBuilder.buildContext(tab: currentTab)
            var response = await aiService.respond(to: text, context: context)
            if response.isEmpty { response = "I'm not sure about that. Try asking about your food, weight, or workouts." }

            messages.append(ChatMessage(role: .assistant, text: response))
            isGenerating = false

            // Auto-execute actions
            let parsed = AIActionParser.parse(response)
            if case .logFood(let name, _) = parsed.action {
                foodSearchQuery = name
                showingFoodSearch = true
            }
        }
    }

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
                        ? Theme.accent.opacity(0.15)
                        : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            if msg.role == .assistant { Spacer() }
        }
        .padding(.horizontal, 10)
    }
}
