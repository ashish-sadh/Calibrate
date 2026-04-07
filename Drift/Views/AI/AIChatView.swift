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
    @State private var pendingMealName: String? = nil  // "lunch" after "What did you have for lunch?"
    @State private var pendingWorkoutLog = false  // true after "What exercises did you do?"
    @State private var showingRecipeBuilder = false
    @State private var pendingRecipeItems: [QuickAddView.RecipeItem] = []
    @State private var pendingRecipeName = ""
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
        let large = aiService.isLargeModel
        let recentCount = large ? 6 : 4   // Gemma can handle more context
        let charBudget = large ? 600 : 300
        let msgLimit = large ? 250 : 150
        let recent = messages.suffix(recentCount)
        var lines: [String] = []
        var charCount = 0
        for msg in recent {
            let prefix = msg.role == .user ? "Q" : "A"
            let truncatedText = msg.text.prefix(msgLimit)
            let line = "\(prefix): \(truncatedText)"
            if charCount + line.count > charBudget { break }
            lines.append(line)
            charCount += line.count
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    /// Resolve pronouns like "it", "that", "this" by scanning recent messages for food mentions.
    /// "log it" after discussing banana → "log banana"
    /// Split food list: "rice, dal, chicken curry" → ["rice", "dal", "chicken curry"]
    private func splitFoodItems(_ text: String) -> [String] {
        var parts = [text]
        for sep in [", and ", " and ", ", "] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

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

        // --- Universal pills (always shown, regardless of screen) ---

        // Food: time-aware meal logging or calorie check
        if nutrition.calories == 0 {
            pills.append(hour < 11 ? "Log breakfast" : hour < 15 ? "Log lunch" : "Log dinner")
        } else {
            pills.append("Calories left")
        }

        // Exercise: smart workout on all screens
        pills.append("Start smart workout")

        // Insight: cross-domain
        if hour >= 20 || (hour >= 18 && nutrition.calories > 0) {
            pills.append("Daily summary")
        } else {
            pills.append("How am I doing?")
        }

        // --- Screen-specific pills (1-2 extras for current context) ---
        switch screen {
        case .weight, .goal:
            pills.append("Am I on track?")
        case .exercise:
            pills.append("What should I train?")
            if let templates = try? WorkoutService.fetchTemplates(), let first = templates.first {
                pills.append("Start \(first.name)")
            }
        case .food:
            if nutrition.proteinG < 80 && hour > 14 {
                pills.append("How's my protein?")
            }
            if hour >= 17 && hour <= 21 {
                pills.append("What should I eat for dinner?")
            }
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
            pills.append("How's my body comp?")
        default:
            // Weekly on weekends or end of day
            let weekday = Calendar.current.component(.weekday, from: Date())
            if weekday == 1 || weekday == 7 || hour >= 20 {
                pills.append("Weekly summary")
            }
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
        // "done"/"start" with pending workout → open it
        if lower == "done" || lower == "start" || lower == "let's go" || lower == "ready" || lower == "begin" {
            if workoutTemplate != nil {
                messages.append(ChatMessage(role: .assistant, text: "Starting workout!"))
                pendingExercises = []
                showingWorkout = true
                return
            }
        }

        // "yes" after weight confirmation → actually log the weight
        if (lower == "yes" || lower == "yeah" || lower == "yep" || lower == "confirm") {
            if let lastAssistant = messages.last(where: { $0.role == .assistant }),
               lastAssistant.text.contains("Log") && lastAssistant.text.contains("Say yes") || lastAssistant.text.contains("Say 'yes'") {
                // Extract weight from the confirmation message: "Log 165.0 lbs for today?"
                let pattern = #"Log (\d+\.?\d*) (lbs|kg)"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: lastAssistant.text, range: NSRange(lastAssistant.text.startIndex..., in: lastAssistant.text)),
                   let valRange = Range(match.range(at: 1), in: lastAssistant.text),
                   let unitRange = Range(match.range(at: 2), in: lastAssistant.text),
                   let value = Double(String(lastAssistant.text[valRange])) {
                    let unit = String(lastAssistant.text[unitRange])
                    if let _ = WeightServiceAPI.logWeight(value: value, unit: unit) {
                        messages.append(ChatMessage(role: .assistant, text: "Logged \(String(format: "%.1f", value)) \(unit)."))
                        return
                    }
                }
            }
        }

        // Delete/remove food: "remove the rice", "delete last entry", "undo"
        let deleteVerbs = ["remove ", "delete ", "undo "]
        if deleteVerbs.contains(where: { lower.hasPrefix($0) }) || lower == "undo" {
            let name: String
            if lower == "undo" || lower == "delete last" || lower == "remove last" || lower == "delete last entry" {
                name = "last"
            } else {
                name = lower
                    .replacingOccurrences(of: "remove ", with: "")
                    .replacingOccurrences(of: "delete ", with: "")
                    .replacingOccurrences(of: "the ", with: "")
                    .replacingOccurrences(of: "my ", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if !name.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: FoodService.deleteEntry(matching: name)))
                return
            }
        }

        // Body comp entry: "my body fat is 18%", "body fat 18", "bmi 22.5"
        let bfPattern = #"(?:body fat|bf|body fat %|bodyfat)\s*(?:is\s+)?(\d+\.?\d*)"#
        if let bfRegex = try? NSRegularExpression(pattern: bfPattern),
           let bfMatch = bfRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(bfMatch.range(at: 1), in: lower),
           let bf = Double(String(lower[numRange])), bf > 3 && bf < 60 {
            var entry = BodyComposition(date: DateFormatters.todayString, bodyFatPct: bf,
                                         source: "manual", createdAt: DateFormatters.iso8601.string(from: Date()))
            try? AppDatabase.shared.saveBodyComposition(&entry)
            messages.append(ChatMessage(role: .assistant, text: "Logged body fat \(String(format: "%.1f", bf))%."))
            return
        }
        let bmiPattern = #"bmi\s*(?:is\s+)?(\d+\.?\d*)"#
        if let bmiRegex = try? NSRegularExpression(pattern: bmiPattern),
           let bmiMatch = bmiRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(bmiMatch.range(at: 1), in: lower),
           let bmi = Double(String(lower[numRange])), bmi > 10 && bmi < 50 {
            var entry = BodyComposition(date: DateFormatters.todayString, bmi: bmi,
                                         source: "manual", createdAt: DateFormatters.iso8601.string(from: Date()))
            try? AppDatabase.shared.saveBodyComposition(&entry)
            messages.append(ChatMessage(role: .assistant, text: "Logged BMI \(String(format: "%.1f", bmi))."))
            return
        }

        // Set weight goal: "set goal to 160", "target weight 75 kg", "I want to weigh 150"
        let goalPattern = #"(?:set goal to|target weight|i want to weigh|goal weight|my goal is)\s+(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
        if let goalRegex = try? NSRegularExpression(pattern: goalPattern),
           let goalMatch = goalRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(goalMatch.range(at: 1), in: lower),
           let target = Double(String(lower[numRange])) {
            let unit: String
            if let unitRange = Range(goalMatch.range(at: 2), in: lower) {
                unit = String(lower[unitRange]).hasPrefix("kg") ? "kg" : "lbs"
            } else {
                unit = Preferences.weightUnit.rawValue
            }
            let targetKg = unit == "kg" ? target : target / 2.20462
            if targetKg >= 20 && targetKg <= 200 {
                let currentKg = (try? AppDatabase.shared.fetchWeightEntries())?.first?.weightKg ?? targetKg
                var goal = WeightGoal.load() ?? WeightGoal(targetWeightKg: targetKg, monthsToAchieve: 6,
                    startDate: DateFormatters.todayString, startWeightKg: currentKg)
                goal.targetWeightKg = targetKg
                goal.save()
                let display = unit == "kg" ? String(format: "%.1f kg", target) : String(format: "%.0f lbs", target)
                messages.append(ChatMessage(role: .assistant, text: "Goal set to \(display)."))
                return
            }
        }

        // Quick-add raw calories: "log 500 cal", "just log 400 calories for lunch"
        let calPattern = #"(\d+)\s*(?:cal(?:ories?)?|kcal)"#
        if let regex = try? NSRegularExpression(pattern: calPattern),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(match.range(at: 1), in: lower),
           let cal = Int(String(lower[numRange])), cal >= 50 && cal <= 5000 {
            // Check for meal hint
            var meal: String? = nil
            for (suffix, m) in [("breakfast", "breakfast"), ("lunch", "lunch"), ("dinner", "dinner"), ("snack", "snack")] {
                if lower.contains(suffix) { meal = m; break }
            }
            messages.append(ChatMessage(role: .assistant, text: FoodService.quickAddCalories(cal, meal: meal)))
            return
        }

        // Copy yesterday's food: "copy yesterday", "same as yesterday"
        if lower == "copy yesterday" || lower == "same as yesterday" || lower == "repeat yesterday"
            || lower == "log same as yesterday" || lower == "yesterday's food" {
            messages.append(ChatMessage(role: .assistant, text: FoodService.copyYesterday()))
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
        // Workout count: "how many workouts this week", "workout count"
        if lower.contains("how many workout") || lower.contains("workout count") || lower.contains("how often did i train")
            || lower.contains("workouts this week") || lower.contains("how many times did i work") {
            let count = (try? WorkoutService.fetchWorkouts(limit: 7))?.filter {
                guard let d = DateFormatters.dateOnly.date(from: $0.date) else { return false }
                return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
            }.count ?? 0
            var response = "\(count) workout\(count == 1 ? "" : "s") this week."
            if let streak = try? WorkoutService.workoutStreak() {
                response += " Streak: \(streak.current) weeks (best: \(streak.longest))."
            }
            messages.append(ChatMessage(role: .assistant, text: response))
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
        // Supplement taken: "took my creatine", "took vitamin D", "had my fish oil"
        let supplementVerbs = ["took my ", "took ", "had my ", "taken my ", "take my "]
        if let verb = supplementVerbs.first(where: { lower.hasPrefix($0) }) {
            let name = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !["breakfast", "lunch", "dinner", "snack"].contains(name) {
                // Check if it matches a supplement (not food)
                if let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
                   supplements.contains(where: { $0.name.lowercased().contains(name.lowercased()) }) {
                    messages.append(ChatMessage(role: .assistant, text: SupplementService.markTaken(name: name)))
                    return
                }
            }
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

        // Meal logging: "log breakfast/lunch/dinner/snack" → ask what they ate, then build recipe
        let mealWords: Set<String> = ["breakfast", "lunch", "dinner", "snack"]
        if let verb = ["log ", "ate ", "had "].first(where: { lower.hasPrefix($0) }) {
            let remainder = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            if mealWords.contains(remainder) {
                pendingMealName = remainder
                messages.append(ChatMessage(role: .assistant,
                    text: "What did you have for \(remainder)? List everything — I'll build a meal entry."))
                return
            }
        }

        // Resolve pronouns from conversation context: "log it", "log that", "add this"
        let resolved = resolvePronouns(lower)

        // Multi-food intent: "log chicken and rice" — show matches, open for first
        if let intents = AIActionExecutor.parseMultiFoodIntent(resolved) {
            var found: [String] = []
            for intent in intents {
                if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
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

        // Single food intent: "log 2 eggs", "ate avocado", "log paneer biryani 300 gram"
        // Always open search/confirmation sheet — show what we found
        if let intent = AIActionExecutor.parseFoodIntent(resolved) {
            foodSearchQuery = intent.query
            foodSearchServings = intent.servings
            // Show what we found before opening the sheet
            if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
                let f = match.food
                let cal = Int(f.calories * match.servings)
                foodSearchServings = match.servings // Use gram-converted servings if applicable
                let gramNote = intent.gramAmount.map { " (\(Int($0))g = \(String(format: "%.1f", match.servings)) servings)" } ?? ""
                messages.append(ChatMessage(role: .assistant, text: "Found \(f.name) (\(cal) cal)\(gramNote). Opening to confirm..."))
            } else if aiService.isLargeModel && aiService.isModelLoaded {
                // Gemma 4: try LLM normalization before opening search
                let query = intent.query
                let servings = intent.servings
                messages.append(ChatMessage(role: .assistant, text: "Looking up \(query)..."))
                Task {
                    if let match = await AIActionExecutor.findFoodWithAI(query: query, servings: servings) {
                        foodSearchQuery = match.food.name
                        foodSearchServings = match.servings
                        if let idx = messages.indices.last(where: { messages[$0].role == .assistant }) {
                            messages[idx].text = "Found \(match.food.name) (\(Int(match.food.calories * match.servings)) cal). Opening to confirm..."
                        }
                    } else {
                        foodSearchQuery = query
                    }
                    showingFoodSearch = true
                }
                return
            } else {
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(intent.query)..."))
            }
            showingFoodSearch = true
            return
        }

        // Workout intent: "log exercise", "add exercise", "track workout", etc.
        let exerciseVerbs = ["log ", "add ", "track "]
        for verb in exerciseVerbs {
            if lower.hasPrefix(verb) {
                let remainder = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
                let workoutWords: Set<String> = ["exercise", "workout", "a workout", "my workout", "training",
                                                  "exercises", "an exercise"]
                if workoutWords.contains(remainder) {
                    pendingWorkoutLog = true
                    messages.append(ChatMessage(role: .assistant,
                        text: "What exercises did you do? List them like:\nbench press 3x10 at 135, squats 3x8"))
                    return
                }
            }
        }

        // Completed activity: "I did yoga today", "went running", "did 30 min cardio"
        let activityPrefixes = ["i did ", "i went ", "just did ", "just finished ", "did "]
        if let prefix = activityPrefixes.first(where: { lower.hasPrefix($0) }) {
            var activity = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            // Strip trailing "today", "this morning", etc.
            for suffix in [" today", " this morning", " this evening", " just now"] {
                if activity.hasSuffix(suffix) { activity = String(activity.dropLast(suffix.count)) }
            }
            // Parse optional duration: "30 min yoga" → 30 min, "yoga"
            var durationMin: Int? = nil
            let durPattern = #"^(\d+)\s*(?:min(?:ute)?s?)\s+"#
            if let durRegex = try? NSRegularExpression(pattern: durPattern),
               let durMatch = durRegex.firstMatch(in: activity, range: NSRange(activity.startIndex..., in: activity)),
               let numRange = Range(durMatch.range(at: 1), in: activity) {
                durationMin = Int(String(activity[numRange]))
                activity = String(activity[activity.index(activity.startIndex, offsetBy: durMatch.range.length)...]).trimmingCharacters(in: .whitespaces)
            }
            if !activity.isEmpty && activity.count > 2 {
                let name = activity.capitalized
                var workout = Workout(name: name, date: DateFormatters.todayString,
                                       durationSeconds: durationMin.map { $0 * 60 },
                                       notes: nil, createdAt: DateFormatters.iso8601.string(from: Date()))
                try? WorkoutService.saveWorkout(&workout)
                let durText = durationMin.map { " (\($0) min)" } ?? ""
                messages.append(ChatMessage(role: .assistant, text: "Logged \(name)\(durText) for today."))
                return
            }
        }

        // "Start smart workout" / "surprise me" — build AI session from history
        if lower == "start smart workout" || lower == "smart workout" || lower == "surprise me"
            || lower == "surprise me with a workout" || lower == "build me a workout" {
            if let smart = ExerciseService.buildSmartSession() {
                let exercises = smart.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
                messages.append(ChatMessage(role: .assistant, text: "Built a session based on your history:\n\(exercises.joined(separator: "\n"))"))
                workoutTemplate = smart
                showingWorkout = true
            } else {
                messages.append(ChatMessage(role: .assistant, text: ExerciseService.suggestWorkout()))
            }
            return
        }

        // Workout suggestion routing — both models use Swift (fast + reliable)
        let workoutQuestions = ["suggest me workout", "suggest a workout", "suggest workout",
                                "give me a workout", "recommend exercises", "recommend workout",
                                "plan my workout", "what workout should i do", "workout ideas",
                                "what should i train", "what to train", "what muscle should i work"]
        if workoutQuestions.contains(where: { lower.contains($0) }) {
            messages.append(ChatMessage(role: .assistant, text: ExerciseService.suggestWorkout()))
            return
        }

        // Food question routing — Swift handles better than LLM for small model
        // Large model (Gemma 4) skips this and lets the LLM use food_info tool instead
        if !aiService.isLargeModel {
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

        // Multi-turn: pending workout log → parse exercises from user's response
        if pendingWorkoutLog,
           !["yes", "no", "ok", "okay", "nevermind", "cancel", "thanks"].contains(lower),
           lower.count > 3 {
            pendingWorkoutLog = false
            // Try parsing as workout exercises via the action parser
            let exercises = AIActionParser.parseWorkoutExercises(lower)
            if !exercises.isEmpty {
                pendingExercises = exercises
                let templateExercises = exercises.map { e in
                    var notes = "\(e.reps) reps"
                    if let w = e.weight { notes += " @ \(Int(w)) lbs" }
                    return WorkoutTemplate.TemplateExercise(name: e.name, sets: e.sets, notes: notes)
                }
                if let json = try? JSONEncoder().encode(templateExercises),
                   let jsonStr = String(data: json, encoding: .utf8) {
                    let summary = exercises.map { e in
                        var s = "\(e.name) \(e.sets)x\(e.reps)"
                        if let w = e.weight { s += " @ \(Int(w)) lbs" }
                        return s
                    }.joined(separator: ", ")
                    messages.append(ChatMessage(role: .assistant, text: "Workout (\(exercises.count) exercises): \(summary). Say \"done\" to start, or add more."))
                    workoutTemplate = WorkoutTemplate(
                        name: "AI Workout",
                        exercisesJson: jsonStr,
                        createdAt: DateFormatters.iso8601.string(from: Date()))
                }
            } else {
                // Couldn't parse — suggest format
                pendingWorkoutLog = true // keep listening
                messages.append(ChatMessage(role: .assistant,
                    text: "I couldn't parse that. Try: bench press 3x10 at 135, squats 3x8"))
            }
            return
        }

        // Multi-turn: pending meal → build recipe from listed ingredients
        if let mealName = pendingMealName,
           !lower.contains("summary") && !lower.contains("calorie") && lower.count > 2
           && !["yes", "no", "ok", "okay", "sure", "nah", "nope", "yeah", "yep", "thanks", "thank you", "nevermind", "cancel"].contains(lower) {
            pendingMealName = nil
            let items = splitFoodItems(lower)
            var recipeItems: [QuickAddView.RecipeItem] = []
            var notFound: [String] = []

            for item in items {
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                if let match = AIActionExecutor.findFood(query: trimmed, servings: nil) {
                    let f = match.food
                    recipeItems.append(QuickAddView.RecipeItem(
                        name: f.name, portionText: "1 serving",
                        calories: f.calories, proteinG: f.proteinG,
                        carbsG: f.carbsG, fatG: f.fatG, fiberG: f.fiberG,
                        servingSizeG: f.servingSize))
                } else {
                    notFound.append(trimmed)
                }
            }

            if recipeItems.isEmpty {
                // Nothing found → open food search
                foodSearchQuery = lower
                showingFoodSearch = true
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(lower)..."))
            } else {
                var msg = "Building \(mealName): \(recipeItems.map { "\($0.name) (\(Int($0.calories)) cal)" }.joined(separator: ", "))."
                if !notFound.isEmpty {
                    msg += " Couldn't find: \(notFound.joined(separator: ", ")) — add them manually in the recipe."
                }
                messages.append(ChatMessage(role: .assistant, text: msg))
                pendingRecipeItems = recipeItems
                pendingRecipeName = mealName.capitalized
                showingRecipeBuilder = true
            }
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

            let responseMessageId = streamingMessageId
            if let idx = messages.firstIndex(where: { $0.id == responseMessageId }) {
                messages[idx].text = finalResponse
            }
            streamingMessageId = nil
            generatingState = .idle

            // Try JSON tool call first (new path), fall back to action tags (legacy)
            if let toolCall = parseToolCallJSON(response) {
                let result = await ToolRegistry.shared.execute(toolCall)
                switch result {
                case .text(let text):
                    if let idx = messages.firstIndex(where: { $0.id == responseMessageId }) {
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
                        } else if let smart = ExerciseService.buildSmartSession(muscleGroup: templateName) {
                            workoutTemplate = smart
                            showingWorkout = true
                        }
                    case .openWeightEntry: break
                    case .navigate: break
                    }
                case .error(let msg):
                    if let idx = messages.firstIndex(where: { $0.id == responseMessageId }) {
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
