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
    @State private var showingWorkout = false
    @State private var workoutTemplate: WorkoutTemplate? = nil
    @State private var pendingExercises: [AIActionParser.WorkoutExercise] = []  // Multi-turn workout accumulation
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
        .onAppear {
            if messages.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: pageInsight))
                // Show disclaimers only once
            }
            if !aiService.isModelLoaded && aiService.state == .ready {
                aiService.loadModel()
            }
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
                .foregroundStyle(Theme.accent).padding(.top, 1)
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
            pills.append("Log a workout")
            if let templates = try? WorkoutService.fetchTemplates(), let first = templates.first {
                pills.append("Start \(first.name)")
            }
        case .bodyRhythm:
            pills.append("How'd I sleep?")
        case .glucose:
            pills.append("Any spikes today?")
        case .biomarkers:
            pills.append("Which markers are out of range?")
            // Show first out-of-range biomarker as a specific pill
            if let results = try? AppDatabase.shared.fetchLatestBiomarkerResults() {
                for r in results.prefix(10) {
                    if let def = BiomarkerKnowledgeBase.byId[r.biomarkerId],
                       def.status(for: r.normalizedValue) != .optimal {
                        pills.append("How's my \(def.name.lowercased())?")
                        break
                    }
                }
            }
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
            // Dashboard — show a quick stat if available
            let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
            if n.calories > 0 {
                return "\(greeting) You've logged \(Int(n.calories)) cal so far. Ask anything about your health data."
            }
            return "\(greeting) Say \"log 2 eggs\" to track food, or ask about your weight, sleep, or workouts."
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
            messages.append(ChatMessage(role: .assistant, text: "I can help you:\n\u{2022} Log food: \"log 2 eggs and toast\"\n\u{2022} Log workout: \"I did bench press 3x10 at 135\"\n\u{2022} Start template: \"start push day\"\n\u{2022} Check progress: \"how am I doing?\"\n\u{2022} Get insights: \"calories left\", \"daily summary\"\n\u{2022} Ask about: weight, sleep, biomarkers, glucose, supplements"))
            return
        }
        let thanks = ["thanks", "thank you", "thx", "ty", "cool", "ok", "okay", "got it", "nice"]
        if thanks.contains(lower) {
            messages.append(ChatMessage(role: .assistant, text: "Anytime! Let me know if you need anything else."))
            return
        }
        // "done" with pending workout → open it
        if (lower == "done" || lower == "start" || lower == "let's go" || lower == "ready") && !pendingExercises.isEmpty {
            if let template = workoutTemplate {
                messages.append(ChatMessage(role: .assistant, text: "Starting workout with \(pendingExercises.count) exercises!"))
                pendingExercises = []
                showingWorkout = true
                return
            }
        }

        if lower == "undo" || lower == "remove that" || lower == "delete that" || lower == "nevermind" {
            messages.append(ChatMessage(role: .assistant, text: "I can't undo actions yet. To remove a food entry, tap it in the Food tab. To delete a weight entry, long-press it."))
            return
        }

        // Correction: "actually 3" or "make it 3" after a food log
        if (lower.hasPrefix("actually") || lower.hasPrefix("make it") || lower.hasPrefix("no,")) {
            // Check if previous message was a food log confirmation
            if let lastAssistant = messages.last(where: { $0.role == .assistant }),
               (lastAssistant.text.contains("Found") || lastAssistant.text.contains("Opening")) {
                messages.append(ChatMessage(role: .assistant, text: "Got it! You can adjust the amount in the food log sheet. Tap the entry in your Food tab to edit."))
                return
            }
        }

        // Rule engine: instant answers for exact-match patterns
        if lower == "daily summary" || lower == "summary" {
            messages.append(ChatMessage(role: .assistant, text: AIRuleEngine.dailySummary()))
            return
        }
        if lower == "how's my protein" || lower == "how's my protein?" || lower == "protein status" {
            let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
            if n.proteinG > 0 {
                if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
                    let pLeft = max(0, Int(targets.proteinG - n.proteinG))
                    messages.append(ChatMessage(role: .assistant, text: "\(Int(n.proteinG))g protein today (\(Int(targets.proteinG))g target). \(pLeft > 0 ? "Still need \(pLeft)g." : "Target reached!")"))
                } else {
                    messages.append(ChatMessage(role: .assistant, text: "\(Int(n.proteinG))g protein today."))
                }
            } else {
                messages.append(ChatMessage(role: .assistant, text: "No food logged yet. Log your meals to track protein."))
            }
            return
        }
        if lower == "what did i eat today" || lower == "what did i eat" || lower == "today's food" {
            let context = AIContextBuilder.foodContext()
            messages.append(ChatMessage(role: .assistant, text: context.isEmpty ? "No food logged today yet." : context))
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

        // Instant nutrition lookup: "calories in banana", "how much protein in chicken"
        if lower.contains("calories in ") || lower.contains("protein in ") || lower.contains("carbs in ")
            || lower.contains("nutrition in ") || lower.contains("nutrition for ")
            || lower.contains("calories for ") || lower.contains("how much protein in ") {
            // Extract food name after " in " or " for "
            var foodName = ""
            for sep in [" in ", " for "] {
                if let range = lower.range(of: sep, options: .backwards) {
                    foodName = String(lower[range.upperBound...])
                    break
                }
            }
            foodName = foodName.replacingOccurrences(of: "a ", with: "").replacingOccurrences(of: "an ", with: "")
                .replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !foodName.isEmpty, let match = AIActionExecutor.findFood(query: foodName, servings: 1) {
                let f = match.food
                messages.append(ChatMessage(role: .assistant, text: "\(f.name) (per \(Int(f.servingSize))\(f.servingUnit)): \(Int(f.calories)) cal, \(Int(f.proteinG))g protein, \(Int(f.carbsG))g carbs, \(Int(f.fatG))g fat. Say \"log \(f.name.lowercased())\" to add it."))
                return
            }
            // Not found in DB — fall through to LLM for estimation
        }

        // Resolve pronouns from conversation context: "log it", "log that", "add this"
        let resolved = resolvePronouns(lower)

        // Multi-food intent: "log chicken and rice" — show matches, open for first
        if let intents = AIActionExecutor.parseMultiFoodIntent(resolved) {
            var found: [String] = []
            for intent in intents {
                if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings) {
                    found.append("\(match.food.name) (\(Int(match.food.calories * match.servings))cal)")
                }
            }
            if !found.isEmpty {
                let extra = intents.count > 1 ? " Say \"log \(intents[1].query)\" after to add the rest." : ""
                messages.append(ChatMessage(role: .assistant, text: "Found: \(found.joined(separator: ", ")). Opening first item...\(extra)"))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(intents.map(\.query).joined(separator: ", "))..."))
            }
            foodSearchQuery = intents[0].query
            foodSearchServings = intents[0].servings
            showingFoodSearch = true
            return
        }

        // Single food intent: "log 2 eggs", "ate avocado"
        // Always open search/confirmation sheet — show what we found
        if let intent = AIActionExecutor.parseFoodIntent(resolved) {
            foodSearchQuery = intent.query
            foodSearchServings = intent.servings
            // Show what we found before opening the sheet
            if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings) {
                let f = match.food
                let cal = Int(f.calories * match.servings)
                messages.append(ChatMessage(role: .assistant, text: "Found \(f.name) (\(cal) cal). Opening to confirm..."))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(intent.query)..."))
            }
            showingFoodSearch = true
            return
        }

        // Workout intent: "log exercise", "log workout", "log a workout"
        if lower.hasPrefix("log ") {
            let remainder = String(lower.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let workoutWords: Set<String> = ["exercise", "workout", "a workout", "my workout", "training"]
            if workoutWords.contains(remainder) {
                messages.append(ChatMessage(role: .assistant, text: ExerciseService.suggestWorkout()))
                return
            }
        }

        // Food question routing (LLM scores 40% on these — Swift handles better)
        let foodQuestions = ["what should i eat", "what to eat", "suggest food", "suggest meal",
                            "what can i eat", "i'm hungry", "im hungry", "feeling hungry",
                            "what should i have", "need food ideas"]
        if foodQuestions.contains(where: { lower.contains($0) }) {
            let totals = FoodService.getDailyTotals()
            var response = "\(totals.remaining > 0 ? "\(totals.remaining)" : "0") cal remaining."
            let suggestions = FoodService.suggestMeal()
            if !suggestions.isEmpty {
                response += " Try: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories))cal, \(Int($0.proteinG))P)" }.joined(separator: ", ")
            }
            messages.append(ChatMessage(role: .assistant, text: response))
            return
        }

        // Direct template start: "start push day", "start legs", "let's do chest day"
        if (lower.hasPrefix("start ") || lower.hasPrefix("let's do ") || lower.hasPrefix("lets do ") || lower.hasPrefix("begin ")) {
            let templateQuery = lower
                .replacingOccurrences(of: "start ", with: "")
                .replacingOccurrences(of: "let's do ", with: "")
                .replacingOccurrences(of: "lets do ", with: "")
                .replacingOccurrences(of: "begin ", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let templates = try? WorkoutService.fetchTemplates(),
               let matched = templates.first(where: { $0.name.lowercased().contains(templateQuery) }) {
                messages.append(ChatMessage(role: .assistant, text: "Starting \(matched.name)!"))
                workoutTemplate = matched
                showingWorkout = true
                return
            }
            // No template matched — build a smart session
            if let smart = ExerciseService.buildSmartSession(muscleGroup: templateQuery) {
                let exercises = smart.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
                messages.append(ChatMessage(role: .assistant, text: "Built a \(templateQuery) session:\n\(exercises.joined(separator: "\n"))"))
                workoutTemplate = smart
                showingWorkout = true
                return
            }
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

        // Multi-turn: if AI just asked "What did you eat?" and user replies with a food name
        if let lastAssistant = messages.last(where: { $0.role == .assistant }),
           (lastAssistant.text.contains("What did you eat") || lastAssistant.text.contains("what did you eat")
            || lastAssistant.text.contains("What did you order") || lastAssistant.text.contains("Describe it")),
           !lower.contains("summary") && !lower.contains("calorie") && lower.count > 2
           && !["yes", "no", "ok", "okay", "sure", "nah", "nope", "yeah", "yep", "thanks", "thank you"].contains(lower) {
            // Treat the reply as a food to log
            if let match = AIActionExecutor.findFood(query: lower, servings: nil) {
                messages.append(ChatMessage(role: .assistant, text: "Found \(match.food.name) (\(Int(match.food.calories)) cal). Opening to confirm..."))
                foodSearchQuery = lower
                showingFoodSearch = true
                return
            } else {
                // Try as food search anyway
                foodSearchQuery = lower
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(lower)..."))
                showingFoodSearch = true
                return
            }
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
                    messages.append(ChatMessage(role: .assistant, text: "AI is loading — should be ready in a few seconds. Meanwhile, try \"daily summary\" or \"log 2 eggs\"."))
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

            // Finalize: clean the response, strip action tags for display, check quality
            let finalResponse: String
            if response.isEmpty {
                finalResponse = fallbackResponse(for: screen)
            } else {
                let (_, cleanText) = AIActionParser.parse(response) // Strip action tags first
                let cleaned = AIResponseCleaner.clean(cleanText)
                if AIResponseCleaner.isLowQuality(cleaned) {
                    finalResponse = fallbackResponse(for: screen)
                } else if AIResponseCleaner.hasHallucinatedNumbers(cleaned, context: AIContextBuilder.baseContext()) {
                    finalResponse = fallbackResponse(for: screen)  // Numbers don't match real data
                } else {
                    finalResponse = cleaned
                }
            }

            if let idx = messages.firstIndex(where: { $0.id == streamingMessageId }) {
                messages[idx].text = finalResponse
            }
            streamingMessageId = nil
            generatingState = .idle

            // Try JSON tool call first (new path), fall back to action tags (legacy)
            if let toolCall = parseToolCallJSON(response) {
                let result = await ToolRegistry.shared.execute(toolCall)
                switch result {
                case .text(let text):
                    if let idx = messages.firstIndex(where: { $0.id == streamingMessageId }) {
                        messages[idx].text = text
                    }
                case .action(let action):
                    switch action {
                    case .openFoodSearch(let query, let servings):
                        foodSearchQuery = query
                        foodSearchServings = servings
                        showingFoodSearch = true
                    case .openWorkout(let templateName):
                        if let templates = try? WorkoutService.fetchTemplates(),
                           let matched = templates.first(where: { $0.name.lowercased().contains(templateName.lowercased()) }) {
                            workoutTemplate = matched
                            showingWorkout = true
                        }
                    case .openWeightEntry: break
                    case .navigate: break
                    }
                case .error(let msg):
                    if let idx = messages.firstIndex(where: { $0.id == streamingMessageId }) {
                        messages[idx].text = msg
                    }
                }
            } else {
            // Legacy: action tag parsing (fallback when model doesn't output JSON)
            let parsed = AIActionParser.parse(response)
            switch parsed.action {
            case .logFood(let name, _):
                foodSearchQuery = name
                showingFoodSearch = true
            case .logWeight(let value, let unit):
                let kg = unit.lowercased().hasPrefix("kg") ? value : value / 2.20462
                var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg, source: "manual")
                try? AppDatabase.shared.saveWeightEntry(&entry)
            case .startWorkout(let type):
                // Find matching template and open it
                if let type,
                   let templates = try? WorkoutService.fetchTemplates(),
                   let matched = templates.first(where: { $0.name.lowercased().contains(type.lowercased()) }) {
                    workoutTemplate = matched
                    showingWorkout = true
                } else {
                    messages.append(ChatMessage(role: .assistant, text: "Head to the Exercise tab to start your workout."))
                }
            case .createWorkout(let exercises):
                // Accumulate exercises across turns
                pendingExercises.append(contentsOf: exercises)
                let allExercises = pendingExercises
                let templateExercises = allExercises.map { e in
                    var notes = "\(e.reps) reps"
                    if let w = e.weight { notes += " @ \(Int(w)) lbs" }
                    return WorkoutTemplate.TemplateExercise(name: e.name, sets: e.sets, notes: notes)
                }
                if let json = try? JSONEncoder().encode(templateExercises),
                   let jsonStr = String(data: json, encoding: .utf8) {
                    let summary = allExercises.map { e in
                        var s = "\(e.name) \(e.sets)x\(e.reps)"
                        if let w = e.weight { s += " @ \(Int(w)) lbs" }
                        return s
                    }.joined(separator: ", ")
                    messages.append(ChatMessage(role: .assistant, text: "Workout (\(allExercises.count) exercises): \(summary). Say \"also did X\" to add more, or \"done\" to start."))

                    let template = WorkoutTemplate(
                        name: "AI Workout",
                        exercisesJson: jsonStr,
                        createdAt: DateFormatters.iso8601.string(from: Date())
                    )
                    workoutTemplate = template
                    // Don't auto-open — wait for "done" or next message
                }
            default:
                break
            }
            } // end else (legacy fallback)
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

    /// Data-aware fallback when LLM fails. Uses actual user data to suggest something useful.
    private func fallbackResponse(for screen: AIScreen) -> String {
        switch screen {
        case .food:
            let totals = FoodService.getDailyTotals()
            if totals.eaten == 0 {
                return "No food logged yet today. Say \"log [food]\" to start tracking, or \"calories left\" to see your target."
            }
            return "\(totals.remaining) cal remaining today. Say \"suggest meal\" for ideas or \"explain calories\" for the math."
        case .weight, .goal:
            let trend = WeightServiceAPI.describeTrend()
            return trend == "No weight data yet." ? "No weight data yet. Say \"I weigh [number]\" to log." : trend
        case .exercise:
            let suggestion = ExerciseService.suggestWorkout()
            return suggestion
        case .biomarkers:
            let results = BiomarkerService.getResults()
            return results
        case .glucose:
            return GlucoseService.getReadings()
        case .bodyRhythm:
            return SleepRecoveryService.getRecovery()
        case .supplements:
            return SupplementService.getStatus()
        default:
            let totals = FoodService.getDailyTotals()
            if totals.eaten > 0 {
                return "\(totals.remaining) cal remaining. Say \"calories left\", \"daily summary\", or ask about weight, workouts, sleep."
            }
            return "Say \"log [food]\" to track meals, \"I weigh [number]\" for weight, or \"what should I train\" for workout ideas."
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
