import SwiftUI

// MARK: - Message Handling (conversation history, intent parsing, send flow)

extension AIChatViewModel {

    // MARK: - Tab Metadata

    /// Map tab index to (label, SF Symbol) for confirmation cards.
    static func tabMeta(_ tab: Int) -> (String, String) {
        switch tab {
        case 0: ("Dashboard", "chart.line.uptrend.xyaxis")
        case 1: ("Weight", "scalemass")
        case 2: ("Food", "fork.knife")
        case 3: ("Exercise", "dumbbell.fill")
        case 4: ("More", "ellipsis")
        default: ("Screen", "rectangle.portrait")
        }
    }

    // MARK: - Conversation History

    func buildConversationHistory() -> String {
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
    func detectMealFromHistory() -> String? {
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
    func detectWorkoutFromHistory() -> Bool {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return false }
        let text = lastAssistant.text.lowercased()
        return text.contains("what exercises did you do") || text.contains("list them like")
    }

    /// Split food list: "rice, dal, chicken curry" → ["rice", "dal", "chicken curry"]
    func splitFoodItems(_ text: String) -> [String] {
        var parts = [text]
        for sep in [", and ", " and ", ", "] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Try to resolve a single food item string into a RecipeItem.
    func resolveRecipeItem(_ text: String) -> QuickAddView.RecipeItem? {
        let (servings, foodName, gramAmount) = AIActionExecutor.extractAmount(from: text)
        guard let match = AIActionExecutor.findFood(query: foodName, servings: servings, gramAmount: gramAmount) else { return nil }
        let f = match.food
        let portionText = gramAmount.map { "\(Int($0))g" } ?? "\(String(format: "%.1f", match.servings)) serving"
        return QuickAddView.RecipeItem(
            name: f.name, portionText: portionText,
            calories: f.calories * match.servings, proteinG: f.proteinG * match.servings,
            carbsG: f.carbsG * match.servings, fatG: f.fatG * match.servings,
            fiberG: f.fiberG * match.servings,
            servingSizeG: f.servingSize)
    }

    /// Parse freeform food text into recipe items and open the recipe builder.
    /// Used by both pending-meal flow and single-message "log breakfast 2 eggs and toast".
    func buildMealFromText(_ text: String, mealName: String) {
        let items = splitFoodItems(text)
        var recipeItems: [QuickAddView.RecipeItem] = []
        var notFound: [String] = []

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            if let recipe = resolveRecipeItem(trimmed) {
                recipeItems.append(recipe)
            } else if trimmed.lowercased().contains(" with ") {
                // "coffee with 2% milk with protein powder" → ["coffee", "2% milk", "protein powder"]
                let subItems = trimmed.components(separatedBy: " with ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for sub in subItems {
                    if let recipe = resolveRecipeItem(sub) {
                        recipeItems.append(recipe)
                    } else {
                        notFound.append(sub)
                    }
                }
            } else {
                notFound.append(trimmed)
            }
        }

        if recipeItems.isEmpty {
            foodSearchQuery = text
            showingFoodSearch = true
            messages.append(ChatMessage(role: .assistant, text: "Searching for \(text)..."))
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
    }

    func resolvePronouns(_ text: String) -> String {
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
                let results = FoodService.searchFood(query: word)
                if let match = results.first,
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
            case .uiAction(let action, let msg):
                switch action {
                case .navigate(let tab):
                    let (label, icon) = Self.tabMeta(tab)
                    let card = NavigationCardData(destination: label, icon: icon, tab: tab)
                    messages.append(ChatMessage(role: .assistant, text: msg ?? "Opening \(label)...", navigationCard: card))
                    NotificationCenter.default.post(name: .navigateToTab, object: nil, userInfo: ["tab": tab])
                case .openBarcodeScanner:
                    if let msg { messages.append(ChatMessage(role: .assistant, text: msg)) }
                    showingBarcodeScanner = true
                default:
                    if let msg { messages.append(ChatMessage(role: .assistant, text: msg)) }
                }
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
        if handleConfirmation(lower) { return }

        // --- View-state handlers (both models, need UI state) ---

        // Delete/remove food: "remove the rice", "delete last entry", "undo"
        if handleDeleteFood(lower) { return }

        // "Start smart workout" / "surprise me" — build AI session from history
        if handleSmartWorkout(lower) { return }

        // Direct template start: "start push day", "start legs", "let's do chest day"
        if handleTemplateStart(lower) { return }

        // --- Multi-turn handlers (both models — BEFORE food parsers) ---

        // Pending workout log: user listing exercises after "What exercises did you do?"
        if handlePendingWorkout(lower) { return }

        // Workout split builder: user responding during split design session
        if handlePendingWorkoutSplit(lower) { return }

        // Meal planning: user responding during iterative meal plan session
        if handlePendingMealPlan(lower) { return }

        // Meal continuation: "also add broccoli", "and some yogurt" after recipe was built
        if handleMealContinuation(lower) { return }

        // Pending meal: user listing food after "What did you have for lunch?"
        if handlePendingMeal(lower, originalText: text) { return }

        // Workout logging trigger: "log exercise", "log workout", "add exercise"
        if handleWorkoutLoggingTrigger(lower) { return }

        // --- Planning triggers ---

        // "build me a PPL split", "design a workout split" → iterative workout design
        if handleWorkoutSplitTrigger(lower) { return }

        // "plan my meals", "what should I eat today" → iterative suggestions
        if handleMealPlanningTrigger(lower) { return }

        // --- Food intent parsing (both models — instant, no LLM needed) ---

        // Meal logging: "log breakfast" → ask, "log breakfast 2 eggs and toast" → build directly
        if handleMealLogging(lower) { return }

        // Resolve pronouns from conversation context: "log it", "log that", "add this"
        let resolved = resolvePronouns(lower)

        // Multi-food intent: "log chicken and rice" → recipe builder with all items
        if handleMultiFoodIntent(resolved) { return }

        // Single food intent: "log 2 eggs", "ate avocado", "log 3 bananas"
        if handleSingleFoodIntent(resolved) { return }

        // Activity logging: "I did yoga", "went running for 30 min"
        if handleActivityLogging(lower) { return }

        // Weight intent: "I weigh 165", "weight is 75.2 kg"
        if handleWeightIntent(lower) { return }

        // Cheat meal — sets multi-turn state
        if handleCheatMeal(lower) { return }

        // Correction: "actually 3" after a food log
        if handleCorrection(lower) { return }

        // Multi-turn: AI asked "What did you eat?" and user replies with food name(s)
        if handleEatQuestion(lower, originalText: text) { return }

        // --- Unified AI pipeline (both models) ---
        handleAIPipeline(text)
    }

    // MARK: - Intent Handlers

    private func handleConfirmation(_ lower: String) -> Bool {
        guard lower == "yes" || lower == "yeah" || lower == "yep" || lower == "confirm" else { return false }
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }),
              lastAssistant.text.contains("Log") && (lastAssistant.text.contains("Say yes") || lastAssistant.text.contains("Say 'yes'")) else { return false }

        // Weight confirmation: "Log 165.0 lbs for today? Say yes to confirm."
        let weightPattern = #"Log (\d+\.?\d*) (lbs|kg)"#
        if let regex = try? NSRegularExpression(pattern: weightPattern),
           let match = regex.firstMatch(in: lastAssistant.text, range: NSRange(lastAssistant.text.startIndex..., in: lastAssistant.text)),
           let valRange = Range(match.range(at: 1), in: lastAssistant.text),
           let unitRange = Range(match.range(at: 2), in: lastAssistant.text),
           let value = Double(String(lastAssistant.text[valRange])) {
            let unit = String(lastAssistant.text[unitRange])
            if let _ = WeightServiceAPI.logWeight(value: value, unit: unit) {
                let card = WeightCardData(value: value, unit: unit, trend: nil)
                messages.append(ChatMessage(role: .assistant, text: "Logged \(String(format: "%.1f", value)) \(unit).", weightCard: card))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "Couldn't save weight — value out of range or database error."))
            }
            return true
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
            do {
                try WorkoutService.saveWorkout(&workout)
                let durText = durationSec.map { " (\($0 / 60) min)" } ?? ""
                let card = WorkoutCardData(name: name, durationMin: durationSec.map { $0 / 60 }, exerciseCount: nil)
                messages.append(ChatMessage(role: .assistant, text: "Logged \(name)\(durText) for today.", workoutCard: card))
            } catch {
                messages.append(ChatMessage(role: .assistant, text: "Couldn't save workout — \(error.localizedDescription)"))
            }
            return true
        }
        return false
    }

    private func handleDeleteFood(_ lower: String) -> Bool {
        let deleteVerbs = ["remove ", "delete ", "undo "]
        guard deleteVerbs.contains(where: { lower.hasPrefix($0) }) || lower == "undo" else { return false }
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
        guard !deleteName.isEmpty else { return false }
        messages.append(ChatMessage(role: .assistant, text: FoodService.deleteEntry(matching: deleteName)))
        return true
    }

    private func handleSmartWorkout(_ lower: String) -> Bool {
        guard lower == "start smart workout" || lower == "smart workout" || lower == "surprise me"
            || lower == "surprise me with a workout" || lower == "build me a workout" else { return false }
        if let smart = ExerciseService.buildSmartSession() {
            let exercises = smart.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
            messages.append(ChatMessage(role: .assistant, text: "Built a session based on your history:\n\(exercises.joined(separator: "\n"))"))
            workoutTemplate = smart
            showingWorkout = true
        } else {
            messages.append(ChatMessage(role: .assistant, text: ExerciseService.suggestWorkout()))
        }
        return true
    }

    private func handleTemplateStart(_ lower: String) -> Bool {
        guard lower.hasPrefix("start ") || lower.hasPrefix("let's do ") || lower.hasPrefix("lets do ") || lower.hasPrefix("begin ") else { return false }
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
            return true
        }
        if let smart = ExerciseService.buildSmartSession(muscleGroup: templateQuery) {
            let exercises = smart.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
            messages.append(ChatMessage(role: .assistant, text: "Built a \(templateQuery) session:\n\(exercises.joined(separator: "\n"))"))
            workoutTemplate = smart
            showingWorkout = true
            return true
        }
        return false
    }

    private func handlePendingWorkout(_ lower: String) -> Bool {
        guard (convState.phase == .awaitingExercises || detectWorkoutFromHistory()),
              !["yes", "no", "ok", "okay", "nevermind", "cancel", "thanks"].contains(lower),
              lower.count > 3 else { return false }
        // Detect topic switches — don't treat "calories left" as exercise list
        let topicSwitchWords: Set<String> = ["calories", "weight", "weigh", "food", "ate", "had",
                                              "sleep", "supplement", "glucose", "trend", "summary"]
        let words = Set(lower.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: topicSwitchWords) {
            convState.phase = .idle
            return false
        }
        convState.phase = .idle
        let exercises = AIActionParser.parseWorkoutExercises(lower)
        if !exercises.isEmpty {
            pendingExercises = exercises
            let templateExercises = exercises.map { e in
                var notes = "\(e.reps) reps"
                if let w = e.weight { notes += " @ \(Int(w)) \(Preferences.weightUnit.displayName)" }
                return WorkoutTemplate.TemplateExercise(name: e.name, sets: e.sets, notes: notes)
            }
            if let json = try? JSONEncoder().encode(templateExercises),
               let jsonStr = String(data: json, encoding: .utf8) {
                let summary = exercises.map { e in
                    var s = "\(e.name) \(e.sets)x\(e.reps)"
                    if let w = e.weight { s += " @ \(Int(w)) \(Preferences.weightUnit.displayName)" }
                    return s
                }.joined(separator: ", ")
                messages.append(ChatMessage(role: .assistant, text: "Workout (\(exercises.count) exercises): \(summary). Say \"done\" to start, or add more."))
                workoutTemplate = WorkoutTemplate(
                    name: "AI Workout",
                    exercisesJson: jsonStr,
                    createdAt: DateFormatters.iso8601.string(from: Date()))
            }
        } else {
            convState.phase = .awaitingExercises
            messages.append(ChatMessage(role: .assistant,
                text: "I couldn't parse that. Try: bench press 3x10 at 135, squats 3x8"))
        }
        return true
    }

    private func handleMealContinuation(_ lower: String) -> Bool {
        let continuationPrefixes = ["also add ", "also ", "and also ", "add ", "plus "]
        guard !pendingRecipeItems.isEmpty,
              let contPrefix = continuationPrefixes.first(where: { lower.hasPrefix($0) }) else { return false }
        let remainder = String(lower.dropFirst(contPrefix.count)).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return false }
        let items = splitFoodItems(remainder)
        var newItems: [QuickAddView.RecipeItem] = []
        var notFound: [String] = []
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            if let recipe = resolveRecipeItem(trimmed) {
                newItems.append(recipe)
            } else if trimmed.lowercased().contains(" with ") {
                for sub in trimmed.components(separatedBy: " with ").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
                    if let recipe = resolveRecipeItem(sub) { newItems.append(recipe) }
                    else { notFound.append(sub) }
                }
            } else { notFound.append(trimmed) }
        }
        guard !newItems.isEmpty else { return false }
        pendingRecipeItems.append(contentsOf: newItems)
        let addedNames = newItems.map { "\($0.name) (\(Int($0.calories)) cal)" }.joined(separator: ", ")
        var msg = "Added \(addedNames) to \(pendingRecipeName). \(pendingRecipeItems.count) items total."
        if !notFound.isEmpty { msg += " Couldn't find: \(notFound.joined(separator: ", "))." }
        messages.append(ChatMessage(role: .assistant, text: msg))
        showingRecipeBuilder = true
        return true
    }

    private func handlePendingMeal(_ lower: String, originalText: String) -> Bool {
        let phaseMealName: String? = if case .awaitingMealItems(let name) = convState.phase { name } else { nil }
        let resolvedMealName = phaseMealName ?? detectMealFromHistory()
        guard let mealName = resolvedMealName,
              !lower.contains("summary") && !lower.contains("calorie") && lower.count > 2
              && !["yes", "no", "ok", "okay", "sure", "nah", "nope", "yeah", "yep", "thanks", "thank you", "nevermind", "cancel"].contains(lower) else { return false }
        // Detect topic switches — don't treat "weight trend" or "how did I sleep" as food list
        let topicSwitchWords: Set<String> = ["weight", "weigh", "trend", "sleep", "workout", "exercise",
                                              "supplement", "glucose", "biomarker", "tdee", "bmr", "goal"]
        let words = Set(lower.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: topicSwitchWords) {
            convState.phase = .idle  // Clear stale phase on topic switch
            return false
        }
        var cleaned = lower
        for prefix in ["i had ", "i ate ", "i made ", "we had ", "it was ", "had "] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)); break }
        }
        buildMealFromText(cleaned, mealName: mealName)
        convState.phase = .idle  // Clear after processing, not before
        return true
    }

    private func handleWorkoutLoggingTrigger(_ lower: String) -> Bool {
        let exerciseNouns: Set<String> = ["exercise", "workout", "a workout", "my workout",
                                           "training", "exercises", "an exercise"]
        // Strip conversational prefixes: "can you log workout" → "log workout"
        var stripped = lower
        for prefix in ["can you ", "could you ", "please ", "can i ", "i want to ", "i'd like to ", "let me ", "help me "] {
            if stripped.hasPrefix(prefix) { stripped = String(stripped.dropFirst(prefix.count)); break }
        }
        if stripped.hasSuffix(" please") { stripped = String(stripped.dropLast(7)) }
        stripped = stripped.trimmingCharacters(in: .whitespaces)
        guard let verb = ["log ", "add ", "track "].first(where: { stripped.hasPrefix($0) }) else { return false }
        let remainder = String(stripped.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        guard exerciseNouns.contains(remainder) else { return false }
        convState.phase = .awaitingExercises
        messages.append(ChatMessage(role: .assistant,
            text: "What exercises did you do? List them like:\nbench press 3x10 at 135, squats 3x8"))
        return true
    }

    private func handleMealLogging(_ lower: String) -> Bool {
        let mealWords: Set<String> = ["breakfast", "lunch", "dinner", "snack"]
        // Strip conversational prefixes: "can you log lunch" → "log lunch"
        var stripped = lower
        for prefix in ["can you ", "could you ", "please ", "can i ", "i want to ", "i'd like to ", "let me ", "help me "] {
            if stripped.hasPrefix(prefix) { stripped = String(stripped.dropFirst(prefix.count)); break }
        }
        // Strip trailing "please": "log lunch please" → "log lunch"
        if stripped.hasSuffix(" please") { stripped = String(stripped.dropLast(7)) }
        stripped = stripped.trimmingCharacters(in: .whitespaces)
        guard let verb = ["log ", "ate ", "had ", "log for ", "ate for ", "had for "].first(where: { stripped.hasPrefix($0) }) else { return false }
        var remainder = String(stripped.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        if remainder.hasPrefix("for ") { remainder = String(remainder.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        guard let meal = mealWords.first(where: { remainder.hasPrefix($0) }) else { return false }
        let afterMeal = String(remainder.dropFirst(meal.count)).trimmingCharacters(in: .whitespaces)
        var foodText = afterMeal
        for prefix in ["with ", "of ", ": ", "- "] {
            if foodText.hasPrefix(prefix) { foodText = String(foodText.dropFirst(prefix.count)); break }
        }
        if foodText.isEmpty {
            convState.phase = .awaitingMealItems(mealName: meal)
            messages.append(ChatMessage(role: .assistant,
                text: "What did you have for \(meal)? List everything — I'll build a meal entry."))
        } else {
            buildMealFromText(foodText, mealName: meal)
        }
        return true
    }

    private func handleMultiFoodIntent(_ resolved: String) -> Bool {
        guard let intents = AIActionExecutor.parseMultiFoodIntent(resolved), intents.count > 1 else { return false }
        let foodText = intents.map { intent in
            var s = intent.query
            if let srv = intent.servings, srv != 1 { s = "\(String(format: "%g", srv)) \(s)" }
            if let g = intent.gramAmount { s = "\(Int(g))g \(s)" }
            return s
        }.joined(separator: " and ")
        buildMealFromText(foodText, mealName: "Meal")
        return true
    }

    private func handleSingleFoodIntent(_ resolved: String) -> Bool {
        guard let intent = AIActionExecutor.parseFoodIntent(resolved) else { return false }
        foodSearchQuery = intent.query
        foodSearchServings = intent.servings
        foodSearchMealType = intent.mealHint.flatMap { MealType(rawValue: $0) }
        if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
            let f = match.food
            let s = match.servings
            foodSearchServings = s
            let servingText = intent.gramAmount.map { "\(Int($0))g" } ?? "\(String(format: "%.1f", s)) serving"
            let card = FoodCardData(
                name: f.name, calories: Int(f.calories * s),
                proteinG: Int(f.proteinG * s), carbsG: Int(f.carbsG * s),
                fatG: Int(f.fatG * s), servingText: servingText)
            messages.append(ChatMessage(role: .assistant, text: "Opening to confirm...", foodCard: card))
        } else {
            messages.append(ChatMessage(role: .assistant, text: "Searching for \(intent.query)..."))
        }
        showingFoodSearch = true
        return true
    }

    private func handleActivityLogging(_ lower: String) -> Bool {
        let activityPrefixes = ["i did ", "i went ", "just did ", "just finished ", "did "]
        guard let prefix = activityPrefixes.first(where: { lower.hasPrefix($0) }) else { return false }
        var activity = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        for suffix in [" today", " this morning", " this evening", " just now"] {
            if activity.hasSuffix(suffix) { activity = String(activity.dropLast(suffix.count)) }
        }
        var durationMin: Int? = nil
        let durPattern = #"(?:for\s+)?(\d+)\s*(?:min(?:ute)?s?)"#
        if let durRegex = try? NSRegularExpression(pattern: durPattern),
           let durMatch = durRegex.firstMatch(in: activity, range: NSRange(activity.startIndex..., in: activity)),
           let numRange = Range(durMatch.range(at: 1), in: activity),
           let fullRange = Range(durMatch.range, in: activity) {
            durationMin = Int(String(activity[numRange]))
            activity = activity.replacingCharacters(in: fullRange, with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        guard !activity.isEmpty && activity.count > 2 else { return false }
        let name = activity.capitalized
        let durText = durationMin.map { " (\($0) min)" } ?? ""
        let card = WorkoutCardData(name: name, durationMin: durationMin, exerciseCount: nil, confirmed: false)
        messages.append(ChatMessage(role: .assistant, text: "Log \(name)\(durText) for today? Say yes to confirm.", workoutCard: card))
        return true
    }

    private func handleWeightIntent(_ lower: String) -> Bool {
        guard let weightIntent = AIActionExecutor.parseWeightIntent(lower) else { return false }
        let kg = weightIntent.unit == .kg ? weightIntent.weightValue : weightIntent.weightValue / 2.20462
        var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg, source: "manual")
        WeightServiceAPI.saveWeightEntry(&entry)
        let display = String(format: "%.1f", weightIntent.weightValue)
        let trend: String? = {
            guard let rate = WeightTrendService.shared.weeklyRate else { return nil }
            let unitRate = weightIntent.unit == .kg ? rate : rate * 2.20462
            let arrow = unitRate < -0.05 ? "↓" : unitRate > 0.05 ? "↑" : "→"
            return "\(arrow) \(String(format: "%.1f", abs(unitRate))) \(weightIntent.unit.displayName)/week"
        }()
        let card = WeightCardData(value: weightIntent.weightValue, unit: weightIntent.unit.displayName, trend: trend)
        messages.append(ChatMessage(role: .assistant, text: "Logged \(display) \(weightIntent.unit.displayName) for today.", weightCard: card))
        return true
    }

    // MARK: - Meal Planning

    private func handleMealPlanningTrigger(_ lower: String) -> Bool {
        let planPhrases = ["plan my meals", "plan meals", "meal plan", "plan my day",
                           "what should i eat today", "what should i eat", "plan my food",
                           "help me plan", "suggest meals", "what to eat today"]
        guard planPhrases.contains(where: { lower.contains($0) }) else { return false }

        let hour = Calendar.current.component(.hour, from: Date())
        let mealName = hour < 11 ? "breakfast" : hour < 15 ? "lunch" : "dinner"

        let totals = FoodService.getDailyTotals()
        let suggestions = FoodService.suggestMeal(caloriesLeft: max(0, totals.remaining))

        if totals.remaining <= 50 {
            messages.append(ChatMessage(role: .assistant,
                text: "You've hit your calorie target for today (\(totals.eaten)/\(totals.target) cal). Nice work!"))
            return true
        }

        var msg = "You have \(totals.remaining) cal remaining today"
        if let goal = WeightGoal.load(),
           let targets = goal.macroTargets(currentWeightKg: WeightTrendService.shared.latestWeightKg) {
            let protLeft = max(0, Int(targets.proteinG) - totals.proteinG)
            if protLeft > 10 { msg += " and still need \(protLeft)g protein" }
        }
        msg += ".\n\n"

        if suggestions.isEmpty {
            msg += "I don't have enough history to suggest foods yet. Try logging a few meals first, and I'll learn your preferences."
        } else {
            msg += "Here are some ideas for \(mealName):\n"
            for (i, food) in suggestions.enumerated() {
                msg += "\(i + 1). **\(food.name)** — \(Int(food.calories)) cal, \(Int(food.proteinG))g protein (\(food.servingUnit))\n"
            }
            msg += "\nSay a number to log it, \"more\" for different options, or \"done\" to finish planning."
        }

        convState.phase = .planningMeals(mealName: mealName, iteration: 0)
        messages.append(ChatMessage(role: .assistant, text: msg))
        return true
    }

    private func handlePendingMealPlan(_ lower: String) -> Bool {
        guard case .planningMeals(let mealName, let iteration) = convState.phase else { return false }

        // Exit commands
        if ["done", "stop", "cancel", "nevermind", "no thanks", "nope", "that's all", "thanks"].contains(lower) {
            convState.phase = .idle
            let totals = FoodService.getDailyTotals()
            messages.append(ChatMessage(role: .assistant,
                text: "Got it! You have \(max(0, totals.remaining)) cal remaining. Say \"plan my meals\" anytime to pick back up."))
            return true
        }

        // Detect topic switches
        let topicSwitchWords: Set<String> = ["weight", "weigh", "trend", "sleep", "workout", "exercise",
                                              "supplement", "glucose", "biomarker", "tdee", "bmr"]
        let words = Set(lower.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: topicSwitchWords) {
            convState.phase = .idle
            return false
        }

        let totals = FoodService.getDailyTotals()

        // Number selection: "1", "2", "3" → log that suggestion
        if let num = Int(lower), num >= 1 {
            let suggestions = FoodService.suggestMeal(caloriesLeft: max(0, totals.remaining))
            if num <= suggestions.count {
                let food = suggestions[num - 1]
                foodSearchQuery = food.name
                foodSearchServings = 1.0
                foodSearchMealType = MealType(rawValue: mealName)
                let card = FoodCardData(
                    name: food.name, calories: Int(food.calories),
                    proteinG: Int(food.proteinG), carbsG: Int(food.carbsG),
                    fatG: Int(food.fatG), servingText: food.servingUnit)
                messages.append(ChatMessage(role: .assistant, text: "Opening to confirm...", foodCard: card))
                showingFoodSearch = true
                // Stay in planning mode for next meal
                convState.phase = .planningMeals(mealName: mealName, iteration: iteration + 1)
                return true
            } else {
                let max = suggestions.isEmpty ? 3 : suggestions.count
                messages.append(ChatMessage(role: .assistant,
                    text: "Pick a number from 1-\(max), say \"more\" for other options, or \"done\" to finish."))
                return true
            }
        }

        // "more" / "other options" / "something else" → show different suggestions
        if lower == "more" || lower.contains("other") || lower.contains("something else") || lower.contains("different") {
            if iteration >= 3 {
                convState.phase = .idle
                messages.append(ChatMessage(role: .assistant,
                    text: "I've shown all the options I have. Try \"log [food]\" to search for something specific."))
                return true
            }
            let suggestions = FoodService.topProteinFoods(limit: 3)
            if suggestions.isEmpty {
                convState.phase = .idle
                messages.append(ChatMessage(role: .assistant,
                    text: "I'm out of suggestions. Try \"log [food]\" to search for something specific."))
                return true
            }
            let remaining = max(0, totals.remaining)
            var msg = "\(remaining) cal left. How about:\n"
            for (i, food) in suggestions.enumerated() {
                msg += "\(i + 1). **\(food.name)** — \(Int(food.calories)) cal, \(Int(food.proteinG))g protein\n"
            }
            msg += "\nSay a number to log it, \"more\" for others, or \"done\" to stop."
            convState.phase = .planningMeals(mealName: mealName, iteration: iteration + 1)
            messages.append(ChatMessage(role: .assistant, text: msg))
            return true
        }

        // Treat anything else as a food to log directly (e.g., user types "chicken breast")
        if lower.count > 2 {
            if let intent = AIActionExecutor.parseFoodIntent(lower) {
                foodSearchQuery = intent.query
                foodSearchServings = intent.servings
                foodSearchMealType = MealType(rawValue: mealName)
                if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
                    let f = match.food
                    let s = match.servings
                    let servingText = intent.gramAmount.map { "\(Int($0))g" } ?? "\(String(format: "%.1f", s)) serving"
                    let card = FoodCardData(
                        name: f.name, calories: Int(f.calories * s),
                        proteinG: Int(f.proteinG * s), carbsG: Int(f.carbsG * s),
                        fatG: Int(f.fatG * s), servingText: servingText)
                    messages.append(ChatMessage(role: .assistant, text: "Opening to confirm...", foodCard: card))
                } else {
                    messages.append(ChatMessage(role: .assistant, text: "Searching for \(intent.query)..."))
                }
                showingFoodSearch = true
                convState.phase = .planningMeals(mealName: mealName, iteration: iteration + 1)
                return true
            }
        }

        return false
    }

    // MARK: - Workout Split Builder

    private func handleWorkoutSplitTrigger(_ lower: String) -> Bool {
        let splitPhrases = ["build me a split", "build a split", "design a split", "create a split",
                            "build me a workout", "design a workout", "create a workout program",
                            "build me a ppl", "build a ppl", "ppl split", "push pull legs",
                            "upper lower split", "upper/lower split", "full body split",
                            "bro split", "workout split", "design my training"]
        guard splitPhrases.contains(where: { lower.contains($0) }) else { return false }

        // Resolve split type from user input, default to PPL
        let splitType = ExerciseService.resolveSplitType(lower) ?? "ppl"
        guard let days = ExerciseService.splitDefinitions[splitType] else { return false }

        // Show the split overview and first day's suggestions
        let splitLabel = splitType == "ppl" ? "Push/Pull/Legs" :
                         splitType == "upper/lower" ? "Upper/Lower" :
                         splitType == "full body" ? "Full Body" :
                         splitType == "bro split" ? "Bro Split" : splitType

        var msg = "Let's build a **\(splitLabel)** split (\(days.count) days).\n\n"
        msg += "**Day 1 — \(days[0].name):**\n"

        let suggestions = ExerciseService.suggestForSplitDay(splitType: splitType, dayIndex: 0)
        if suggestions.isEmpty {
            msg += "No exercises found for this day. Try a different split type."
            messages.append(ChatMessage(role: .assistant, text: msg))
            return true
        }

        for (i, ex) in suggestions.enumerated() {
            let tip = ExerciseService.formTip(for: ex.name).map { " — \($0)" } ?? ""
            msg += "\(i + 1). **\(ex.name)** (\(ex.bodyPart))\(tip)\n"
        }
        msg += "\nSay numbers to pick exercises (e.g. \"1 3 5\"), \"all\" to take them all, or \"skip\" to move to the next day."

        convState.phase = .planningWorkout(splitType: splitType, currentDay: 0, totalDays: days.count)
        messages.append(ChatMessage(role: .assistant, text: msg))
        return true
    }

    private func handlePendingWorkoutSplit(_ lower: String) -> Bool {
        guard case .planningWorkout(let splitType, let currentDay, let totalDays) = convState.phase else { return false }
        guard let days = ExerciseService.splitDefinitions[splitType] else {
            convState.phase = .idle
            return false
        }

        // Exit commands
        if ["done", "cancel", "nevermind", "stop", "no thanks"].contains(lower) {
            convState.phase = .idle
            messages.append(ChatMessage(role: .assistant,
                text: "No problem! Say \"build me a split\" anytime to start over."))
            return true
        }

        // Topic switch detection
        let topicSwitchWords: Set<String> = ["weight", "weigh", "calories", "protein", "food", "log",
                                              "sleep", "supplement", "glucose", "biomarker", "tdee", "bmr"]
        let words = Set(lower.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: topicSwitchWords) {
            convState.phase = .idle
            return false
        }

        let suggestions = ExerciseService.suggestForSplitDay(splitType: splitType, dayIndex: currentDay)

        // "all" — take all suggested exercises
        if lower == "all" || lower == "all of them" || lower == "take all" {
            let picked = suggestions.map(\.name)
            return saveDayAndAdvance(splitType: splitType, dayName: days[currentDay].name,
                                    picked: picked, currentDay: currentDay, totalDays: totalDays, days: days)
        }

        // "skip" — skip this day entirely
        if lower == "skip" || lower == "next" || lower == "next day" {
            return saveDayAndAdvance(splitType: splitType, dayName: days[currentDay].name,
                                    picked: [], currentDay: currentDay, totalDays: totalDays, days: days)
        }

        // Number selection: "1 3 5" or "1, 3, 5" or just "2"
        let numbers = lower.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .filter { $0 >= 1 && $0 <= suggestions.count }
        if !numbers.isEmpty {
            let picked = numbers.map { suggestions[$0 - 1].name }
            return saveDayAndAdvance(splitType: splitType, dayName: days[currentDay].name,
                                    picked: picked, currentDay: currentDay, totalDays: totalDays, days: days)
        }

        // Freeform exercise name — search and add
        if lower.count > 2 {
            if let resolved = ExerciseService.resolveExerciseName(lower) {
                return saveDayAndAdvance(splitType: splitType, dayName: days[currentDay].name,
                                        picked: [resolved], currentDay: currentDay, totalDays: totalDays, days: days)
            }
        }

        // Unrecognized input
        messages.append(ChatMessage(role: .assistant,
            text: "Say numbers to pick exercises (e.g. \"1 3 5\"), \"all\", \"skip\", or \"done\" to cancel."))
        return true
    }

    /// Save picked exercises for the current day and advance to the next day or finish.
    private func saveDayAndAdvance(splitType: String, dayName: String, picked: [String],
                                   currentDay: Int, totalDays: Int, days: [(name: String, parts: [String])]) -> Bool {
        // Store picked exercises as a template for this day
        if !picked.isEmpty {
            let templateName = "\(splitType.uppercased()) — \(dayName)"
            if var template = ExerciseService.buildSplitTemplate(name: templateName, exerciseNames: picked) {
                try? WorkoutService.saveTemplate(&template)
            }
        }

        let nextDay = currentDay + 1
        if nextDay >= totalDays {
            // All days done
            convState.phase = .idle
            let savedCount = (0...currentDay).filter { dayIdx in
                // Check if this day had exercises (current day uses picked, previous days already saved)
                dayIdx < currentDay || !picked.isEmpty
            }.count

            if savedCount == 0 {
                messages.append(ChatMessage(role: .assistant,
                    text: "Split cancelled — no exercises selected. Say \"build me a split\" to try again."))
            } else {
                var msg = "Your split is ready! Saved \(savedCount) template\(savedCount == 1 ? "" : "s"):\n"
                if let templates = try? WorkoutService.fetchTemplates() {
                    let splitPrefix = splitType.uppercased()
                    let splitTemplates = templates.filter { $0.name.hasPrefix(splitPrefix) }
                    for t in splitTemplates.suffix(totalDays) {
                        let count = t.exercises.count
                        msg += "• **\(t.name)** — \(count) exercise\(count == 1 ? "" : "s")\n"
                    }
                }
                msg += "\nSay \"start \(days[0].name)\" to begin your first workout!"
                messages.append(ChatMessage(role: .assistant, text: msg))
            }
            return true
        }

        // Show next day
        var msg = ""
        if !picked.isEmpty {
            msg += "Added \(picked.count) exercise\(picked.count == 1 ? "" : "s") to **\(dayName)**.\n\n"
        } else {
            msg += "Skipped \(dayName).\n\n"
        }

        msg += "**Day \(nextDay + 1) — \(days[nextDay].name):**\n"
        let nextSuggestions = ExerciseService.suggestForSplitDay(splitType: splitType, dayIndex: nextDay)
        for (i, ex) in nextSuggestions.enumerated() {
            let tip = ExerciseService.formTip(for: ex.name).map { " — \($0)" } ?? ""
            msg += "\(i + 1). **\(ex.name)** (\(ex.bodyPart))\(tip)\n"
        }
        msg += "\nPick numbers, \"all\", \"skip\", or \"done\"."

        convState.phase = .planningWorkout(splitType: splitType, currentDay: nextDay, totalDays: totalDays)
        messages.append(ChatMessage(role: .assistant, text: msg))
        return true
    }

    private func handleCheatMeal(_ lower: String) -> Bool {
        let cheatPhrases = ["cheat meal", "cheat day", "ate out", "went off plan", "off track", "binge"]
        guard cheatPhrases.contains(where: { lower.contains($0) }) else { return false }
        convState.phase = .awaitingMealItems(mealName: "cheat meal")
        messages.append(ChatMessage(role: .assistant, text: "No judgment! What did you have? I'll log it for you."))
        return true
    }

    private func handleCorrection(_ lower: String) -> Bool {
        guard lower.hasPrefix("actually") || lower.hasPrefix("make it") || lower.hasPrefix("no,") else { return false }
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }),
              (lastAssistant.text.contains("Found") || lastAssistant.text.contains("Opening")) else { return false }
        messages.append(ChatMessage(role: .assistant, text: "Got it! You can adjust the amount in the food log sheet. Tap the entry in your Food tab to edit."))
        return true
    }

    private func handleEatQuestion(_ lower: String, originalText: String) -> Bool {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }),
              (lastAssistant.text.contains("What did you eat") || lastAssistant.text.contains("what did you eat")
               || lastAssistant.text.contains("What did you order") || lastAssistant.text.contains("Describe it")),
              !lower.contains("summary") && !lower.contains("calorie") && lower.count > 2
              && !["yes", "no", "ok", "okay", "sure", "nah", "nope", "yeah", "yep", "thanks", "thank you"].contains(lower) else { return false }
        let mealName: String = if case .awaitingMealItems(let name) = convState.phase { name } else { "Meal" }
        convState.phase = .idle
        buildMealFromText(originalText, mealName: mealName)
        return true
    }

    // MARK: - AI Pipeline

    private func handleAIPipeline(_ text: String) {
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
                onStep: { [weak self] step in
                    Task { @MainActor in self?.generatingState = .thinking(step: step) }
                },
                onToken: { [weak self] token in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .thinking = self.generatingState { self.generatingState = .generating }
                        if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                            self.messages[idx].text += token
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
                case .openRecipeBuilder(let items, let mealName):
                    var resolved: [QuickAddView.RecipeItem] = []
                    for itemName in items {
                        if let recipe = resolveRecipeItem(itemName) {
                            resolved.append(recipe)
                        } else if itemName.lowercased().contains(" with ") {
                            for sub in itemName.components(separatedBy: " with ").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
                                if let recipe = resolveRecipeItem(sub) { resolved.append(recipe) }
                                else { resolved.append(QuickAddView.RecipeItem(name: sub, portionText: "1 serving", calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)) }
                            }
                        } else {
                            resolved.append(QuickAddView.RecipeItem(name: itemName, portionText: "1 serving", calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0))
                        }
                    }
                    pendingRecipeItems = resolved
                    pendingRecipeName = mealName ?? currentMealType.rawValue
                    showingRecipeBuilder = true
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
                case .openBarcodeScanner:
                    showingBarcodeScanner = true
                case .navigate(let tab):
                    let (label, icon) = Self.tabMeta(tab)
                    let card = NavigationCardData(destination: label, icon: icon, tab: tab)
                    messages.append(ChatMessage(role: .assistant, text: "Opening \(label)...", navigationCard: card))
                    NotificationCenter.default.post(name: .navigateToTab, object: nil, userInfo: ["tab": tab])
                }
            }
        }
    }
}
