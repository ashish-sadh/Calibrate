import SwiftUI
import PhotosUI

/// Chat-style AI assistant with chain-of-thought reasoning and smart suggestion pills.
struct AIChatView: View {
    @State private var aiService = LocalAIService.shared
    @State private var screenTracker = AIScreenTracker.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var generatingState: GeneratingState = .idle
    @State private var streamingMessageId: UUID? = nil
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
        var text: String
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
                messages.append(ChatMessage(role: .assistant, text: "This is an experimental feature. If something doesn't work, you can turn it off from the toggle on Dashboard or in More \u{2192} Settings."))
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

    /// Resolve pronouns like "it", "that", "this" by scanning recent messages for food mentions.
    /// "log it" after discussing banana → "log banana"
    private func resolvePronouns(_ text: String) -> String {
        let pronounPatterns = ["log it", "log that", "log this", "add it", "add that", "add this", "track it", "track that"]
        guard pronounPatterns.contains(where: { text.contains($0) }) else { return text }

        // Scan recent messages (newest first) for food names in our DB
        let skipWords: Set<String> = ["the", "and", "for", "you", "your", "have", "has", "had", "are", "was",
                                       "with", "about", "from", "that", "this", "been", "will", "can", "how",
                                       "what", "today", "calories", "protein", "carbs", "fat", "logged", "eaten"]

        for msg in messages.suffix(8).reversed() {
            let words = msg.text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !skipWords.contains($0) }

            for word in words {
                if let results = try? AppDatabase.shared.searchFoodsRanked(query: word),
                   let match = results.first,
                   match.name.lowercased().contains(word) {
                    var resolved = text
                    for pronoun in [" it", " that", " this"] {
                        resolved = resolved.replacingOccurrences(of: pronoun, with: " \(match.name.lowercased())")
                    }
                    return resolved
                }
            }
        }
        return text
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

        // Quick conversational responses — no LLM needed
        let greetings = ["hi", "hello", "hey", "yo", "sup"]
        if greetings.contains(lower) {
            messages.append(ChatMessage(role: .assistant, text: "Hey! What can I help you with? Try asking about your food, weight, or workouts."))
            return
        }
        let thanks = ["thanks", "thank you", "thx", "ty", "cool", "ok", "okay", "got it", "nice"]
        if thanks.contains(lower) {
            messages.append(ChatMessage(role: .assistant, text: "Anytime! Let me know if you need anything else."))
            return
        }

        // Rule engine: instant answers for exact-match patterns only
        // Broader questions go to LLM for nuanced, personalized responses
        if lower == "daily summary" || lower == "summary" || lower == "my day" {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.dailySummary()))
            return
        }
        if lower == "yesterday" || lower == "what did i eat yesterday" {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.yesterdaySummary()))
            return
        }
        if lower == "calories left" || lower == "calories left today" || lower == "how many calories left" {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.caloriesLeft()))
            return
        }
        if lower == "supplements" || lower == "did i take my supplements" || lower == "supplement status" {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.supplementStatus()))
            return
        }

        // Resolve pronouns from conversation context: "log it", "log that", "add this"
        let resolved = resolvePronouns(lower)

        // Multi-food intent: "log chicken and rice"
        if let intents = AIActionExecutor.parseMultiFoodIntent(resolved) {
            let names = intents.map(\.query).joined(separator: ", ")
            messages.append(ChatMessage(role: .assistant, text: "Opening search for \(names)..."))
            // Open search for first item
            foodSearchQuery = intents[0].query
            foodSearchServings = intents[0].servings
            showingFoodSearch = true
            return
        }

        // Single food intent: "log 2 eggs", "ate avocado"
        if let intent = AIActionExecutor.parseFoodIntent(resolved) {
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

        // Chain-of-thought with streaming: fetch data, stream LLM tokens into live message
        let screen = screenTracker.currentScreen
        let history = buildConversationHistory()

        // Create a placeholder message for streaming
        let placeholder = ChatMessage(role: .assistant, text: "")
        messages.append(placeholder)
        streamingMessageId = placeholder.id

        generatingState = .thinking(step: "Understanding your question...")
        Task {
            let response = await AIChainOfThought.execute(
                query: text, screen: screen, history: history,
                onStep: { step in
                    Task { @MainActor in
                        generatingState = .thinking(step: step)
                    }
                },
                onToken: { token in
                    Task { @MainActor in
                        // Switch from thinking to generating on first token
                        if case .thinking = generatingState {
                            generatingState = .generating
                        }
                        // Append token to the streaming message
                        if let idx = messages.firstIndex(where: { $0.id == streamingMessageId }) {
                            messages[idx].text += token
                        }
                    }
                }
            )

            // Finalize: clean the response and replace streaming message
            let finalResponse: String
            if response.isEmpty {
                finalResponse = "I took too long to respond. Try a simpler question, or check the relevant tab directly."
            } else {
                finalResponse = AIResponseCleaner.clean(response)
            }

            if let idx = messages.firstIndex(where: { $0.id == streamingMessageId }) {
                messages[idx].text = finalResponse
            }
            streamingMessageId = nil
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
