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
                .onChange(of: messages.last?.text) { _, _ in
                    // Also scroll during streaming as text grows
                    if streamingMessageId != nil, let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
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
                // Show experimental warning only once
                if !UserDefaults.standard.bool(forKey: "drift_ai_warned") {
                    messages.append(ChatMessage(role: .assistant, text: "This is an experimental feature. Turn it off from the toggle on Dashboard or More \u{2192} Settings."))
                    UserDefaults.standard.set(true, forKey: "drift_ai_warned")
                }
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
        // Compact format: Q/A instead of User/Assistant (saves tokens)
        let recent = messages.suffix(4) // Last 2 exchanges — keep tight for small models
        var lines: [String] = []
        var charCount = 0
        for msg in recent {
            let prefix = msg.role == .user ? "Q" : "A"
            let truncatedText = msg.text.prefix(150) // Truncate long messages
            let line = "\(prefix): \(truncatedText)"
            if charCount + line.count > 300 { break } // Tighter budget
            lines.append(line)
            charCount += line.count
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n")
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

        for msg in messages.suffix(4).reversed() {
            let words = msg.text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !skipWords.contains($0) }

            for word in words.prefix(5) { // Limit DB queries
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

        // Food-based suggestions — time and context aware
        if nutrition.calories == 0 {
            pills.append(hour < 11 ? "Log breakfast" : hour < 15 ? "Log lunch" : "Log dinner")
        } else {
            pills.append("Calories left")
            if nutrition.proteinG < 80 && hour > 14 {
                pills.append("How's my protein?")
            }
            if hour >= 17 && hour <= 21 {
                pills.append("What should I eat for dinner?")
            }
        }

        if hour >= 20 || (hour >= 18 && nutrition.calories > 0) {
            pills.append("Daily summary")
        }

        // Weekly on weekends or end of day
        let weekday = Calendar.current.component(.weekday, from: Date())
        if weekday == 1 || weekday == 7 || hour >= 20 {
            pills.append("Weekly summary")
        }

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
            if let entries = try? AppDatabase.shared.fetchWeightEntries(), !entries.isEmpty {
                return "\(greeting) I can help with your weight progress — ask about your trend, goal, or pace."
            }
            return "\(greeting) Log your weight using the + button to start tracking your progress."
        case .food:
            let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
            return n.calories > 0
                ? "\(greeting) You've logged \(Int(n.calories)) cal so far. Need to add anything?"
                : "\(greeting) What did you have to eat? Say something like \"log 2 eggs and toast\"."
        case .exercise:
            return "\(greeting) Ask what to train, or say \"start push day\" to begin a workout."
        case .bodyRhythm:
            return "\(greeting) Ask about your sleep, HRV, recovery, or energy levels."
        case .glucose:
            let hasGlucose = (try? AppDatabase.shared.fetchGlucoseReadings(from: DateFormatters.todayString, to: DateFormatters.todayString))?.isEmpty == false
            return hasGlucose
                ? "\(greeting) Ask about your glucose patterns, spikes, or fasting windows."
                : "\(greeting) Import glucose data from a CGM CSV to start analyzing your patterns."
        case .biomarkers:
            let hasLabs = (try? AppDatabase.shared.fetchLatestBiomarkerResults())?.isEmpty == false
            return hasLabs
                ? "\(greeting) Ask about your lab results — which markers are out of range?"
                : "\(greeting) Upload a lab report PDF to see your biomarker trends."
        case .cycle:
            return "\(greeting) Ask about your cycle phase, period timing, or cycle length trends."
        case .supplements:
            return "\(greeting) Ask about your supplement status or what you still need to take."
        case .bodyComposition:
            return "\(greeting) Ask about your body fat, lean mass, or compare DEXA scans."
        default:
            return "\(greeting) How can I help you today?"
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap input length to preserve context budget
        if text.count > 300 { text = String(text.prefix(300)) }
        guard !text.isEmpty, !isGenerating else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, text: text))

        let lower = text.lowercased()

        // Emoji-only messages — just acknowledge
        if lower.unicodeScalars.allSatisfy({ $0.properties.isEmoji || $0.properties.isEmojiPresentation || $0 == " " }) && !lower.isEmpty && lower.count <= 4 {
            messages.append(ChatMessage(role: .assistant, text: "What can I help you with?"))
            return
        }

        // Quick conversational responses — no LLM needed
        let greetings = ["hi", "hello", "hey", "yo", "sup"]
        if greetings.contains(lower) {
            messages.append(ChatMessage(role: .assistant, text: "Hey! Ask about your food, weight, workouts, or say \"log 2 eggs\" to quickly log meals."))
            return
        }
        if lower == "help" || lower == "what can you do" || lower == "what can you do?" {
            messages.append(ChatMessage(role: .assistant, text: "I can help you:\n\u{2022} Log food: \"log 2 eggs and toast\"\n\u{2022} Check progress: \"how am I doing?\"\n\u{2022} Get insights: \"calories left\", \"daily summary\"\n\u{2022} Ask about: weight, workouts, sleep, biomarkers, glucose, supplements"))
            return
        }
        let thanks = ["thanks", "thank you", "thx", "ty", "cool", "ok", "okay", "got it", "nice"]
        if thanks.contains(lower) {
            messages.append(ChatMessage(role: .assistant, text: "Anytime! Let me know if you need anything else."))
            return
        }
        if lower == "undo" || lower == "remove that" || lower == "delete that" || lower == "nevermind" {
            messages.append(ChatMessage(role: .assistant, text: "I can't undo actions yet. To remove a food entry, tap it in the Food tab. To delete a weight entry, swipe it in the Weight tab."))
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
        if lower == "this week" || lower == "weekly summary" || lower == "how was my week" {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.weeklySummary()))
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

        // Multi-food intent: "log chicken and rice" — log known foods directly
        if let intents = AIActionExecutor.parseMultiFoodIntent(resolved) {
            var logged: [String] = []
            var notFound: [AIActionExecutor.FoodIntent] = []
            let vm = FoodLogViewModel()
            let meal = currentMealType

            for intent in intents {
                if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings) {
                    let f = match.food
                    let s = match.servings
                    vm.quickAdd(name: f.name, calories: f.calories * s, proteinG: f.proteinG * s,
                                carbsG: f.carbsG * s, fatG: f.fatG * s, fiberG: f.fiberG * s, mealType: meal)
                    logged.append("\(f.name) (\(Int(f.calories * s))cal)")
                } else {
                    notFound.append(intent)
                }
            }

            if !logged.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: "Logged: \(logged.joined(separator: ", "))."))
            }
            if let first = notFound.first {
                messages.append(ChatMessage(role: .assistant, text: "Couldn't find \(notFound.map(\.query).joined(separator: ", ")) — opening search..."))
                foodSearchQuery = first.query
                foodSearchServings = first.servings
                showingFoodSearch = true
            }
            return
        }

        // Single food intent: "log 2 eggs", "ate avocado"
        // Try direct logging if exact DB match found
        if let intent = AIActionExecutor.parseFoodIntent(resolved) {
            if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings) {
                let f = match.food
                let servings = match.servings
                let cal = f.calories * servings
                let p = f.proteinG * servings
                let vm = FoodLogViewModel()
                vm.quickAdd(name: f.name, calories: cal, proteinG: p,
                            carbsG: f.carbsG * servings, fatG: f.fatG * servings,
                            fiberG: f.fiberG * servings, mealType: currentMealType)
                messages.append(ChatMessage(role: .assistant, text: "Logged \(f.name)\(servings != 1 ? " x\(Int(servings))" : "") (\(Int(cal)) cal, \(Int(p))g protein)."))
                return
            }
            // No exact match — open search
            foodSearchQuery = intent.query
            foodSearchServings = intent.servings
            messages.append(ChatMessage(role: .assistant, text: "Searching for \(intent.query)..."))
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

            // Finalize: clean the response, check quality, replace streaming message
            let finalResponse: String
            if response.isEmpty {
                finalResponse = fallbackResponse(for: screen)
            } else {
                let cleaned = AIResponseCleaner.clean(response)
                finalResponse = AIResponseCleaner.isLowQuality(cleaned) ? fallbackResponse(for: screen) : cleaned
            }

            if let idx = messages.firstIndex(where: { $0.id == streamingMessageId }) {
                messages[idx].text = finalResponse
            }
            streamingMessageId = nil
            generatingState = .idle

            // Auto-execute actions from LLM response
            let parsed = AIActionParser.parse(finalResponse)
            switch parsed.action {
            case .logFood(let name, _):
                foodSearchQuery = name
                showingFoodSearch = true
            case .logWeight(let value, let unit):
                let kg = unit.lowercased().hasPrefix("kg") ? value : value / 2.20462
                var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg, source: "manual")
                try? AppDatabase.shared.saveWeightEntry(&entry)
            default:
                break
            }
        }
    }

    // MARK: - Message Bubble

    /// Determine meal type based on time of day.
    private var currentMealType: MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<11: return .breakfast
        case ..<15: return .lunch
        case ..<21: return .dinner
        default: return .snack
        }
    }

    /// Screen-aware fallback when LLM fails or produces low-quality output.
    private func fallbackResponse(for screen: AIScreen) -> String {
        switch screen {
        case .food: return "I couldn't answer that. Try asking \"calories left\" or \"what should I eat for dinner?\""
        case .weight, .goal: return "I couldn't answer that. Try \"am I on track?\" or \"how much have I lost?\""
        case .exercise: return "I couldn't answer that. Try \"what should I train?\" or \"how many workouts this week?\""
        case .biomarkers: return "I couldn't answer that. Try \"which markers are out of range?\" or \"how's my cholesterol?\""
        case .glucose: return "I couldn't answer that. Try \"any spikes today?\" or \"what's my average glucose?\""
        case .bodyRhythm: return "I couldn't answer that. Try \"how did I sleep?\" or \"what's my recovery score?\""
        default: return "I couldn't answer that. Try asking about your food, weight, workouts, or health data."
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
