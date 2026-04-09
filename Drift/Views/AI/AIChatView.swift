import SwiftUI
import PhotosUI

/// Chat-style AI assistant with chain-of-thought reasoning and smart suggestion pills.
struct AIChatView: View {
    @State private var aiService = LocalAIService.shared
    @State var screenTracker = AIScreenTracker.shared
    @State private var messages: [ChatMessage] = []
    @State var inputText = ""
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
    @State private var showingBarcodeScanner = false
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

    /// Detect meal context from conversation history.
    /// If the last assistant message was "What did you have for X?", returns the meal name.
    /// Also detects continuation after recipe building ("also add X", "and broccoli").
    private func detectMealFromHistory() -> String? {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return nil }
        let text = lastAssistant.text.lowercased()
        // "What did you have for lunch?" pattern
        let meals = ["breakfast", "lunch", "dinner", "snack"]
        for meal in meals {
            if text.contains("what did you have for \(meal)") || text.contains("building \(meal)") {
                return meal
            }
        }
        return nil
    }

    /// Detect workout logging context from history ("What exercises did you do?")
    private func detectWorkoutFromHistory() -> Bool {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return false }
        let text = lastAssistant.text.lowercased()
        return text.contains("what exercises did you do") || text.contains("list them like")
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

    // Smart suggestions, page insight, and fallback responses in AIChatView+Suggestions.swift

    // MARK: - Send Message

    func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap input length to preserve context budget
        if text.count > 300 { text = String(text.prefix(300)) }
        guard !text.isEmpty, !isGenerating else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, text: text))

        let lower = text.lowercased()

        // --- Static overrides (both models): greetings, thanks, help, emoji, rule engine ---
        if let staticResult = StaticOverrides.match(lower) {
            switch staticResult {
            case .response(let text):
                messages.append(ChatMessage(role: .assistant, text: text))
                return
            case .handler(let fn):
                messages.append(ChatMessage(role: .assistant, text: fn()))
                return
            case .uiAction(_, let msg):
                if let msg { messages.append(ChatMessage(role: .assistant, text: msg)) }
                showingBarcodeScanner = true  // Currently only barcode uses this
                return
            case .toolCall(let call):
                Task {
                    let result = await ToolRegistry.shared.execute(call)
                    if case .text(let text) = result {
                        messages.append(ChatMessage(role: .assistant, text: text))
                    }
                }
                return
            }
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

        // "yes" after confirmation → log the pending item
        if (lower == "yes" || lower == "yeah" || lower == "yep" || lower == "confirm") {
            if let lastAssistant = messages.last(where: { $0.role == .assistant }),
               lastAssistant.text.contains("Log") && (lastAssistant.text.contains("Say yes") || lastAssistant.text.contains("Say 'yes'")) {
                // Weight confirmation: "Log 165.0 lbs for today? Say yes to confirm."
                let weightPattern = #"Log (\d+\.?\d*) (lbs|kg)"#
                if let regex = try? NSRegularExpression(pattern: weightPattern),
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
                // Activity confirmation: "Log Yoga (30 min) for today? Say yes to confirm."
                let activityPattern = #"Log (.+?)(?:\s*\((\d+) min\))?\s+for today"#
                if let regex = try? NSRegularExpression(pattern: activityPattern),
                   let match = regex.firstMatch(in: lastAssistant.text, range: NSRange(lastAssistant.text.startIndex..., in: lastAssistant.text)),
                   let nameRange = Range(match.range(at: 1), in: lastAssistant.text) {
                    let name = String(lastAssistant.text[nameRange])
                    var durationSec: Int? = nil
                    if let durRange = Range(match.range(at: 2), in: lastAssistant.text),
                       let mins = Int(String(lastAssistant.text[durRange])) {
                        durationSec = mins * 60
                    }
                    var workout = Workout(name: name, date: DateFormatters.todayString,
                                           durationSeconds: durationSec,
                                           notes: nil, createdAt: DateFormatters.iso8601.string(from: Date()))
                    try? WorkoutService.saveWorkout(&workout)
                    let durText = durationSec.map { " (\($0 / 60) min)" } ?? ""
                    messages.append(ChatMessage(role: .assistant, text: "Logged \(name)\(durText) for today."))
                    return
                }
            }
        }

        // --- View-state handlers (both models, need UI state) ---

        // Delete/remove food: "remove the rice", "delete last entry", "undo"
        let deleteVerbs = ["remove ", "delete ", "undo "]
        if deleteVerbs.contains(where: { lower.hasPrefix($0) }) || lower == "undo" {
            let deleteName: String
            if lower == "undo" || lower == "delete last" || lower == "remove last" || lower == "delete last entry" {
                deleteName = "last"
            } else {
                deleteName = lower
                    .replacingOccurrences(of: "remove ", with: "")
                    .replacingOccurrences(of: "delete ", with: "")
                    .replacingOccurrences(of: "the ", with: "")
                    .replacingOccurrences(of: "my ", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if !deleteName.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: FoodService.deleteEntry(matching: deleteName)))
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

        // Direct template start: "start push day", "start legs", "let's do chest day"
        if lower.hasPrefix("start ") || lower.hasPrefix("let's do ") || lower.hasPrefix("lets do ") || lower.hasPrefix("begin ") {
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
            if let smart = ExerciseService.buildSmartSession(muscleGroup: templateQuery) {
                let exercises = smart.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
                messages.append(ChatMessage(role: .assistant, text: "Built a \(templateQuery) session:\n\(exercises.joined(separator: "\n"))"))
                workoutTemplate = smart
                showingWorkout = true
                return
            }
        }

        // --- Multi-turn handlers (both models — BEFORE food parsers) ---

        // Pending workout log: user listing exercises after "What exercises did you do?"
        // Uses state var OR history detection as fallback
        if (pendingWorkoutLog || detectWorkoutFromHistory()),
           !["yes", "no", "ok", "okay", "nevermind", "cancel", "thanks"].contains(lower),
           lower.count > 3 {
            pendingWorkoutLog = false
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
                pendingWorkoutLog = true
                messages.append(ChatMessage(role: .assistant,
                    text: "I couldn't parse that. Try: bench press 3x10 at 135, squats 3x8"))
            }
            return
        }

        // Meal continuation: "also add broccoli", "and some yogurt" after recipe was built
        let continuationPrefixes = ["also add ", "also ", "and also ", "add ", "plus "]
        if !pendingRecipeItems.isEmpty,
           let contPrefix = continuationPrefixes.first(where: { lower.hasPrefix($0) }) {
            let remainder = String(lower.dropFirst(contPrefix.count)).trimmingCharacters(in: .whitespaces)
            if !remainder.isEmpty {
                let items = splitFoodItems(remainder)
                var newItems: [QuickAddView.RecipeItem] = []
                var notFound: [String] = []
                for item in items {
                    let trimmed = item.trimmingCharacters(in: .whitespaces)
                    let (servings, foodName, gramAmount) = AIActionExecutor.extractAmount(from: trimmed)
                    if let match = AIActionExecutor.findFood(query: foodName, servings: servings, gramAmount: gramAmount) {
                        let f = match.food
                        let portionText = gramAmount.map { "\(Int($0))g" } ?? "\(String(format: "%.1f", match.servings)) serving"
                        newItems.append(QuickAddView.RecipeItem(
                            name: f.name, portionText: portionText,
                            calories: f.calories * match.servings, proteinG: f.proteinG * match.servings,
                            carbsG: f.carbsG * match.servings, fatG: f.fatG * match.servings,
                            fiberG: f.fiberG * match.servings,
                            servingSizeG: f.servingSize))
                    } else { notFound.append(trimmed) }
                }
                if !newItems.isEmpty {
                    pendingRecipeItems.append(contentsOf: newItems)
                    let addedNames = newItems.map { "\($0.name) (\(Int($0.calories)) cal)" }.joined(separator: ", ")
                    var msg = "Added \(addedNames) to \(pendingRecipeName). \(pendingRecipeItems.count) items total."
                    if !notFound.isEmpty { msg += " Couldn't find: \(notFound.joined(separator: ", "))." }
                    messages.append(ChatMessage(role: .assistant, text: msg))
                    showingRecipeBuilder = true
                    return
                }
            }
        }

        // Pending meal: user listing food after "What did you have for lunch?"
        // Uses state var OR history detection as fallback (survives navigation/state loss)
        let resolvedMealName = pendingMealName ?? detectMealFromHistory()
        if let mealName = resolvedMealName,
           !lower.contains("summary") && !lower.contains("calorie") && lower.count > 2
           && !["yes", "no", "ok", "okay", "sure", "nah", "nope", "yeah", "yep", "thanks", "thank you", "nevermind", "cancel"].contains(lower) {
            pendingMealName = nil
            // Strip conversational prefixes: "I had 100g rice" → "100g rice"
            var cleaned = lower
            for prefix in ["i had ", "i ate ", "i made ", "we had ", "it was ", "had "] {
                if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)); break }
            }
            let items = splitFoodItems(cleaned)
            var recipeItems: [QuickAddView.RecipeItem] = []
            var notFound: [String] = []

            for item in items {
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                // Parse amount per item: "100 gram of rice" → (food: "rice", gramAmount: 100)
                let (servings, foodName, gramAmount) = AIActionExecutor.extractAmount(from: trimmed)
                if let match = AIActionExecutor.findFood(query: foodName, servings: servings, gramAmount: gramAmount) {
                    let f = match.food
                    let portionText = gramAmount.map { "\(Int($0))\(gramAmount != nil ? "g" : "")" } ?? "\(String(format: "%.1f", match.servings)) serving"
                    recipeItems.append(QuickAddView.RecipeItem(
                        name: f.name, portionText: portionText,
                        calories: f.calories * match.servings, proteinG: f.proteinG * match.servings,
                        carbsG: f.carbsG * match.servings, fatG: f.fatG * match.servings,
                        fiberG: f.fiberG * match.servings,
                        servingSizeG: f.servingSize))
                } else {
                    notFound.append(trimmed)
                }
            }

            if recipeItems.isEmpty {
                foodSearchQuery = cleaned
                showingFoodSearch = true
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(cleaned)..."))
            } else {
                var msg = "Building \(mealName): \(recipeItems.map { "\($0.name) (\(Int($0.calories)) cal)" }.joined(separator: ", "))."
                if !notFound.isEmpty {
                    msg += " Couldn't find: \(notFound.joined(separator: ", ")) — add them manually."
                }
                messages.append(ChatMessage(role: .assistant, text: msg))
                pendingRecipeItems = recipeItems
                pendingRecipeName = mealName.capitalized
                showingRecipeBuilder = true
            }
            return
        }

        // Workout logging trigger: "log exercise", "log workout", "add exercise"
        let exerciseNouns: Set<String> = ["exercise", "workout", "a workout", "my workout",
                                           "training", "exercises", "an exercise"]
        if let verb = ["log ", "add ", "track "].first(where: { lower.hasPrefix($0) }) {
            let remainder = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            if exerciseNouns.contains(remainder) {
                pendingWorkoutLog = true
                messages.append(ChatMessage(role: .assistant,
                    text: "What exercises did you do? List them like:\nbench press 3x10 at 135, squats 3x8"))
                return
            }
        }

        // --- Food intent parsing (both models — instant, no LLM needed) ---

        // Meal logging: "log breakfast/lunch/dinner/snack" → ask what they ate
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

        // Multi-food intent: "log chicken and rice"
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

        // Single food intent: "log 2 eggs", "ate avocado", "log 3 bananas"
        if let intent = AIActionExecutor.parseFoodIntent(resolved) {
            foodSearchQuery = intent.query
            foodSearchServings = intent.servings
            if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
                let f = match.food
                let cal = Int(f.calories * match.servings)
                foodSearchServings = match.servings
                let gramNote = intent.gramAmount.map { " (\(Int($0))g = \(String(format: "%.1f", match.servings)) servings)" } ?? ""
                messages.append(ChatMessage(role: .assistant, text: "Found \(f.name) (\(cal) cal)\(gramNote). Opening to confirm..."))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(intent.query)..."))
            }
            showingFoodSearch = true
            return
        }

        // Activity logging: "I did yoga", "went running for 30 min"
        let activityPrefixes = ["i did ", "i went ", "just did ", "just finished ", "did "]
        if let prefix = activityPrefixes.first(where: { lower.hasPrefix($0) }) {
            var activity = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            for suffix in [" today", " this morning", " this evening", " just now"] {
                if activity.hasSuffix(suffix) { activity = String(activity.dropLast(suffix.count)) }
            }
            var durationMin: Int? = nil
            let durPattern = #"(?:for\s+)?(\d+)\s*(?:min(?:ute)?s?)"#
            if let durRegex = try? NSRegularExpression(pattern: durPattern),
               let durMatch = durRegex.firstMatch(in: activity, range: NSRange(activity.startIndex..., in: activity)),
               let numRange = Range(durMatch.range(at: 1), in: activity) {
                durationMin = Int(String(activity[numRange]))
                activity = activity.replacingCharacters(in: Range(durMatch.range, in: activity)!, with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if !activity.isEmpty && activity.count > 2 {
                let name = activity.capitalized
                let durText = durationMin.map { " (\($0) min)" } ?? ""
                messages.append(ChatMessage(role: .assistant, text: "Log \(name)\(durText) for today? Say yes to confirm."))
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

        // Cheat meal — sets multi-turn state (can't move to StaticOverrides)
        let cheatPhrases = ["cheat meal", "cheat day", "ate out", "went off plan", "off track", "binge"]
        if cheatPhrases.contains(where: { lower.contains($0) }) {
            pendingMealName = "cheat meal"
            messages.append(ChatMessage(role: .assistant, text: "No judgment! What did you have? I'll log it for you."))
            return
        }

        // Correction: "actually 3" after a food log — stateful, checks message history
        if (lower.hasPrefix("actually") || lower.hasPrefix("make it") || lower.hasPrefix("no,")) {
            if let lastAssistant = messages.last(where: { $0.role == .assistant }),
               (lastAssistant.text.contains("Found") || lastAssistant.text.contains("Opening")) {
                messages.append(ChatMessage(role: .assistant, text: "Got it! You can adjust the amount in the food log sheet. Tap the entry in your Food tab to edit."))
                return
            }
        }

        // Multi-turn: AI asked "What did you eat?" and user replies with food name
        if let lastAssistant = messages.last(where: { $0.role == .assistant }),
           (lastAssistant.text.contains("What did you eat") || lastAssistant.text.contains("what did you eat")
            || lastAssistant.text.contains("What did you order") || lastAssistant.text.contains("Describe it")),
           !lower.contains("summary") && !lower.contains("calorie") && lower.count > 2
           && !["yes", "no", "ok", "okay", "sure", "nah", "nope", "yeah", "yep", "thanks", "thank you"].contains(lower) {
            if let match = AIActionExecutor.findFood(query: lower, servings: nil) {
                messages.append(ChatMessage(role: .assistant, text: "Found \(match.food.name) (\(Int(match.food.calories)) cal). Opening to confirm..."))
                foodSearchQuery = lower
                showingFoodSearch = true
                return
            } else {
                foodSearchQuery = lower
                messages.append(ChatMessage(role: .assistant, text: "Searching for \(lower)..."))
                showingFoodSearch = true
                return
            }
        }

        // --- Unified AI pipeline (both models) ---

        if !aiService.isModelLoaded {
            if aiService.state == .ready {
                messages.append(ChatMessage(role: .assistant, text: "Preparing AI assistant..."))
                aiService.loadModel()
            } else {
                let hint = "Try \"daily summary\", \"log 2 eggs\", or \"calories\"."
                switch aiService.state {
                case .notSetUp:
                    messages.append(ChatMessage(role: .assistant, text: "AI model not downloaded yet. Tap the download button to get started. \(hint)"))
                case .downloading(let progress):
                    messages.append(ChatMessage(role: .assistant, text: "Downloading AI (\(Int(progress * 100))%)... \(hint)"))
                case .loading:
                    messages.append(ChatMessage(role: .assistant, text: "AI is loading — should be ready in a few seconds. \(hint)"))
                case .error(let msg):
                    messages.append(ChatMessage(role: .assistant, text: msg))
                case .notEnoughSpace(let msg):
                    messages.append(ChatMessage(role: .assistant, text: msg))
                case .ready:
                    messages.append(ChatMessage(role: .assistant, text: "AI model couldn't start. \(hint)"))
                }
            }
            return
        }

        let placeholder = ChatMessage(role: .assistant, text: "")
        messages.append(placeholder)
        let responseId = placeholder.id
        streamingMessageId = responseId
        generatingState = .thinking(step: "Understanding your question...")

        let screen = screenTracker.currentScreen
        let history = buildConversationHistory()
        let isLarge = aiService.isLargeModel

        Task {
            let output = await AIToolAgent.run(
                message: text, screen: screen, history: history,
                isLargeModel: isLarge,
                onStep: { step in
                    Task { @MainActor in generatingState = .thinking(step: step) }
                },
                onToken: { token in
                    Task { @MainActor in
                        if case .thinking = generatingState { generatingState = .generating }
                        if let idx = messages.firstIndex(where: { $0.id == responseId }) {
                            messages[idx].text += token
                        }
                    }
                }
            )

            // Apply agent output
            if let idx = messages.firstIndex(where: { $0.id == responseId }) {
                if output.text.isEmpty {
                    messages.remove(at: idx)
                } else {
                    messages[idx].text = output.text
                }
            }
            streamingMessageId = nil
            generatingState = .idle

            // Handle UI actions from tool results
            if let action = output.action {
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
