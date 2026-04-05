import SwiftUI
import PhotosUI

/// Chat-style AI assistant with chain-of-thought reasoning and smart suggestion pills.
struct AIChatView: View {
    @State private var aiService = LocalAIService.shared
    @State private var screenTracker = AIScreenTracker.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var generatingState: GeneratingState = .idle
    @State private var showingFoodSearch = false
    @State private var foodSearchQuery = ""
    @State private var foodSearchServings: Double? = nil
    @FocusState private var inputFocused: Bool

    enum GeneratingState: Equatable {
        case idle
        case thinking(step: String)
        case generating
    }

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        enum Role { case user, assistant }
    }

    private var isGenerating: Bool { generatingState != .idle }

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
                messages.append(ChatMessage(role: .assistant, text: pageInsight))
            }
            if !aiService.isModelLoaded && aiService.state == .ready {
                aiService.loadModel()
            }
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.6)
            switch generatingState {
            case .thinking(let step):
                Text(step).font(.caption2).foregroundStyle(.tertiary)
            case .generating:
                Text("Writing response...").font(.caption2).foregroundStyle(.tertiary)
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .transition(.opacity)
    }

    // MARK: - Conversation History

    private func buildConversationHistory() -> String {
        let recent = messages.suffix(6) // Last 3 exchanges
        var lines: [String] = []
        var charCount = 0
        for msg in recent {
            let prefix = msg.role == .user ? "User" : "Assistant"
            let line = "\(prefix): \(msg.text)"
            if charCount + line.count > 400 { break }
            lines.append(line)
            charCount += line.count
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Smart Suggestions

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
        let screen = screenTracker.currentScreen

        // Food-based suggestions
        if nutrition.calories == 0 {
            pills.append(hour < 11 ? "Log breakfast" : hour < 15 ? "Log lunch" : "Log dinner")
        } else {
            pills.append("How's my protein?")
            if hour > 17 { pills.append("What should I eat for dinner?") }
        }

        pills.append("Daily summary")

        // Screen-specific pills
        switch screen {
        case .weight, .goal:
            pills.append("Am I on track?")
        case .exercise:
            pills.append("What should I train?")
        case .bodyRhythm:
            pills.append("How'd I sleep?")
        case .glucose:
            pills.append("Any spikes today?")
        case .biomarkers:
            pills.append("Which markers are out of range?")
        case .cycle:
            pills.append("What phase am I in?")
        case .supplements:
            pills.append("Did I take everything?")
        case .bodyComposition:
            pills.append("Compare my DEXA scans")
        default:
            if nutrition.calories > 0 { pills.append("Calories left today?") }
        }

        return pills
    }

    // MARK: - Page Insight

    private var pageInsight: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning!" : hour < 17 ? "Good afternoon!" : "Good evening!"
        let screen = screenTracker.currentScreen

        switch screen {
        case .weight, .goal:
            return "\(greeting) I can help with your weight progress — just ask."
        case .food:
            let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
            return n.calories > 0
                ? "\(greeting) You've logged \(Int(n.calories)) cal so far. Need to add anything?"
                : "\(greeting) What did you have to eat?"
        case .exercise:
            return "\(greeting) Ready for a workout? Tell me what you'd like to train."
        case .bodyRhythm:
            return "\(greeting) Ask me about your sleep, HRV, or recovery."
        case .glucose:
            return "\(greeting) I can analyze your glucose patterns."
        case .biomarkers:
            return "\(greeting) Ask about your lab results or biomarker trends."
        case .cycle:
            return "\(greeting) I can help with cycle tracking insights."
        case .supplements:
            return "\(greeting) Need help with your supplement routine?"
        case .bodyComposition:
            return "\(greeting) I can compare your DEXA scans and body composition."
        default:
            return "\(greeting) How can I help you today?"
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, text: text))

        let lower = text.lowercased()

        // Rule engine: instant data queries (no LLM needed)
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
        if lower.contains("calories left") || lower.contains("how much can i eat") || lower.contains("remaining") {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.caloriesLeft()))
            return
        }
        if lower.contains("supplement") && (lower.contains("take") || lower.contains("status") || lower.contains("did i")) {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.supplementStatus()))
            return
        }

        // Multi-food intent: "log chicken and rice"
        if let intents = AIActionExecutor.parseMultiFoodIntent(lower) {
            let names = intents.map(\.query).joined(separator: ", ")
            messages.append(ChatMessage(role: .assistant, text: "Opening search for \(names)..."))
            // Open search for first item
            foodSearchQuery = intents[0].query
            foodSearchServings = intents[0].servings
            showingFoodSearch = true
            return
        }

        // Single food intent: "log 2 eggs", "ate avocado"
        if let intent = AIActionExecutor.parseFoodIntent(lower) {
            foodSearchQuery = intent.query
            foodSearchServings = intent.servings
            messages.append(ChatMessage(role: .assistant, text: "Opening \(intent.query)..."))
            showingFoodSearch = true
            return
        }

        // Weight intent: "I weigh 165", "weight is 75.2 kg"
        if let weightIntent = AIActionExecutor.parseWeightIntent(lower) {
            let kg = weightIntent.unit == .kg ? weightIntent.weightValue : weightIntent.weightValue / 2.20462
            var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg, source: "manual")
            try? AppDatabase.shared.saveWeightEntry(&entry)
            let display = String(format: "%.1f", weightIntent.weightValue)
            messages.append(ChatMessage(role: .assistant, text: "Logged \(display) \(weightIntent.unit.displayName) for today."))
            return
        }

        // Generic "log food/breakfast/lunch"
        if lower.contains("log food") || lower.contains("log breakfast") || lower.contains("log lunch") || lower.contains("log dinner") {
            messages.append(ChatMessage(role: .assistant, text: "What did you eat?"))
            return
        }

        // LLM for everything else
        if !aiService.isModelLoaded {
            if aiService.state == .ready { aiService.loadModel() }
            if !aiService.isModelLoaded {
                let hint = "Try \"daily summary\", \"log 2 eggs\", or \"calories\"."
                switch aiService.state {
                case .notSetUp:
                    messages.append(ChatMessage(role: .assistant, text: "AI model not downloaded yet. Tap the download button to get started. \(hint)"))
                case .downloading(let progress):
                    messages.append(ChatMessage(role: .assistant, text: "Downloading AI (\(Int(progress * 100))%)… \(hint)"))
                case .loading:
                    messages.append(ChatMessage(role: .assistant, text: "Loading AI model — just a moment…"))
                case .error(let msg):
                    messages.append(ChatMessage(role: .assistant, text: msg))
                case .notEnoughSpace(let msg):
                    messages.append(ChatMessage(role: .assistant, text: msg))
                case .ready:
                    messages.append(ChatMessage(role: .assistant, text: "AI model couldn't start. \(hint)"))
                }
                return
            }
        }

        // Chain-of-thought with timeout: fetch data, call LLM, clean response
        let screen = screenTracker.currentScreen
        let history = buildConversationHistory()

        generatingState = .thinking(step: "Understanding your question...")
        Task {
            // Race LLM against 30s timeout
            let response: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await AIChainOfThought.execute(
                        query: text, screen: screen, history: history
                    ) { step in
                        Task { @MainActor in
                            generatingState = .thinking(step: step)
                        }
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(30))
                    return nil // timeout sentinel
                }
                for await result in group {
                    group.cancelAll()
                    return result
                }
                return nil
            }

            let finalResponse: String
            if let response, !response.isEmpty {
                finalResponse = AIResponseCleaner.clean(response)
            } else {
                finalResponse = "I took too long to respond. Try a simpler question, or check the relevant tab directly."
            }

            messages.append(ChatMessage(role: .assistant, text: finalResponse))
            generatingState = .idle

            // Auto-execute actions from LLM response
            let parsed = AIActionParser.parse(finalResponse)
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
