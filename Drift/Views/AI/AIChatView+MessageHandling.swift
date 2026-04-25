import SwiftUI
import DriftCore

// MARK: - Message Handling (conversation history, intent parsing, send flow)

extension AIChatViewModel {

    // MARK: - Smart Serving Text

    /// Format a food amount using its natural unit (piece, ml, cup, tbsp, etc.)
    /// instead of always showing "N serving". Mirrors the unit FoodSearchView shows.
    static func smartServingText(food: Food, servings: Double, gramAmount: Double?) -> String {
        if let grams = gramAmount { return "\(Int(grams))g" }
        let units = FoodUnit.smartUnits(for: food)
        guard let primary = units.first, primary.label != "serving",
              food.servingSize > 0, primary.gramsEquivalent > 0 else {
            return "\(String(format: "%g", servings)) serving"
        }
        let totalGrams = servings * food.servingSize
        let amount = totalGrams / primary.gramsEquivalent
        let formatted = (amount == amount.rounded() && amount < 100)
            ? String(Int(amount.rounded())) : String(format: "%.1f", amount)
        return "\(formatted) \(primary.label)"
    }

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
        // Gemma gets the full 400-token budget; SmolLM stays tighter at 150
        // because its attention on distant tokens is less reliable.
        let maxTokens = aiService.isLargeModel ? 400 : 150
        return ConversationHistoryBuilder.build(messages: messages, maxTokens: maxTokens)
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
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Secondary split: "one avocado two eggs" → ["one avocado", "two eggs"]
        let implicitCountWords = ["two ", "three ", "four ", "five ", "six ", "seven ", "eight ", "nine ", "ten "]
        parts = parts.flatMap { part -> [String] in
            for num in implicitCountWords {
                if let range = part.range(of: " \(num)") {
                    let before = String(part[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let after = (num + String(part[range.upperBound...])).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty && !after.isEmpty { return [before, after] }
                }
            }
            return [part]
        }
        return parts
    }

    /// Try to resolve a single food item string into a RecipeItem.
    func resolveRecipeItem(_ text: String) -> QuickAddView.RecipeItem? {
        let (servings, foodName, gramAmount) = AIActionExecutor.extractAmount(from: text)
        guard let match = AIActionExecutor.findFood(query: foodName, servings: servings, gramAmount: gramAmount) else { return nil }
        let f = match.food
        let portionText = Self.smartServingText(food: f, servings: match.servings, gramAmount: gramAmount)
        return QuickAddView.RecipeItem(
            name: f.name, portionText: portionText,
            calories: f.calories * match.servings, proteinG: f.proteinG * match.servings,
            carbsG: f.carbsG * match.servings, fatG: f.fatG * match.servings,
            fiberG: f.fiberG * match.servings,
            servingSizeG: f.servingSize * match.servings)
    }

    /// Parse freeform food text into recipe items and open the recipe builder.
    /// Streams each resolved item progressively so the user sees progress before the builder opens.
    /// Used by both pending-meal flow and single-message "log breakfast 2 eggs and toast".
    func buildMealFromText(_ text: String, mealName: String) {
        let items = splitFoodItems(text)
        messages.append(ChatMessage(role: .assistant,
            text: "Looking up \(items.count) item\(items.count == 1 ? "" : "s") for \(mealName)..."))
        let statusIdx = messages.count - 1

        Task {
            var recipeItems: [QuickAddView.RecipeItem] = []
            var notFound: [String] = []

            for item in items {
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                if let recipe = resolveRecipeItem(trimmed) {
                    recipeItems.append(recipe)
                } else if trimmed.lowercased().contains(" with ") {
                    // "coffee with 2% milk with protein powder" → ["coffee", "2% milk", "protein powder"]
                    for sub in trimmed.components(separatedBy: " with ")
                            .map({ $0.trimmingCharacters(in: .whitespaces) })
                            .filter({ !$0.isEmpty }) {
                        if let recipe = resolveRecipeItem(sub) {
                            recipeItems.append(recipe)
                        } else {
                            notFound.append(sub)
                        }
                    }
                } else {
                    notFound.append(trimmed)
                }

                // Progressive update: show each resolved item before the next lookup
                guard statusIdx < messages.count else { continue }
                let resolved = items.count - recipeItems.count - notFound.count
                if !recipeItems.isEmpty {
                    let found = recipeItems.map { "\($0.name) (\(Int($0.calories)) cal)" }.joined(separator: ", ")
                    messages[statusIdx] = ChatMessage(role: .assistant,
                        text: resolved > 0 ? "Found \(found) — looking up \(resolved) more..." : "Found \(found)")
                }
                await Task.yield()
            }

            guard statusIdx < messages.count else { return }
            if recipeItems.isEmpty {
                messages[statusIdx] = ChatMessage(role: .assistant, text: "Searching for \(text)...")
                foodSearchQuery = text
                showingFoodSearch = true
            } else {
                var msg = "Building \(mealName): \(recipeItems.map { "\($0.name) (\(Int($0.calories)) cal)" }.joined(separator: ", "))."
                if !notFound.isEmpty {
                    msg += " Couldn't find: \(notFound.joined(separator: ", ")) — add them manually."
                }
                messages[statusIdx] = ChatMessage(role: .assistant, text: msg)
                pendingRecipeItems = recipeItems
                pendingRecipeName = mealName.capitalized
                showingRecipeBuilder = true
            }
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
        if text.count > 300 { text = String(text.prefix(300)) }
        guard !text.isEmpty, !isGenerating else { return }
        inputText = ""
        // Snapshot conversation state on every send so mid-flow survives app kill.
        // Phases set inside async handlers are captured by the next send or scene-backgrounding.
        defer { saveConversationState() }

        // Advance the user-turn index so #184 freshness window (last tool
        // summary) can distinguish "this turn" from "older turns".
        convState.beginUserTurn()

        // Phase 0: Normalize input (strip filler words, voice artifacts, repeated words)
        // All subsequent phases see clean input consistently.
        let normalized = InputNormalizer.normalize(text)
        messages.append(ChatMessage(role: .user, text: normalized))

        let lower = normalized.lowercased()

        // Phase 1: Static overrides (greetings, help, rule engine)
        if dispatchStaticOverride(lower) { return }
        // Phase 2: Workout quick-start ("done", "start", "ready")
        if handleWorkoutQuickStart(lower) { return }
        // Phase 3: Confirmation ("yes" after weight/activity prompt)
        if handleConfirmation(lower) { return }
        // Phase 4: View-state handlers (delete, smart workout, template)
        if handleDeleteFood(lower) { return }
        if handleSmartWorkout(lower) { return }
        if handleTemplateStart(lower) { return }
        // Phase 4b: Ask-don't-guess clarification resolution (#226) —
        // runs before multi-turn so "1"/"first" can't be mis-parsed.
        if handleClarificationResponse(lower) { return }
        // Phase 5: Multi-turn conversation state
        if handleMultiTurnState(lower, originalText: normalized) { return }
        // Phase 6: Planning triggers (split builder, meal planning)
        if handleWorkoutSplitTrigger(lower) { return }
        if handleMealPlanningTrigger(lower) { return }
        // Phase 7: Food & activity intent parsing
        if handleFoodIntentParsing(lower, originalText: normalized) { return }
        // Phase 8: AI pipeline fallback
        handleAIPipeline(normalized)
    }

    // MARK: - Phase Handlers

    /// Phase 1: Dispatch static override results (greetings, thanks, help, emoji, rule engine).
    private func dispatchStaticOverride(_ lower: String) -> Bool {
        let phaseBefore = convState.phase
        guard let staticResult = StaticOverrides.match(lower) else { return false }
        if phaseBefore != .idle && convState.phase == .idle {
            pendingRecipeItems = []
            pendingRecipeName = ""
            pendingExercises = []
        }
        switch staticResult {
        case .response(let text):
            messages.append(ChatMessage(role: .assistant, text: text))
        case .handler(let fn):
            messages.append(ChatMessage(role: .assistant, text: fn()))
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
            case .openManualFoodEntry(let name, let calories, let proteinG, let carbsG, let fatG):
                if let msg { messages.append(ChatMessage(role: .assistant, text: msg)) }
                pendingManualFoodEntry = AIChatViewModel.ManualFoodPrefill(
                    name: name, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
                showingManualFoodEntry = true
            default:
                if let msg { messages.append(ChatMessage(role: .assistant, text: msg)) }
            }
        case .toolCall(let call):
            Task {
                let result = await ToolRegistry.shared.execute(call)
                if case .text(let text) = result {
                    messages.append(ChatMessage(role: .assistant, text: text))
                }
            }
        }
        return true
    }

    /// Phase 2: "done"/"start"/"ready" with a pending workout template → open it.
    private func handleWorkoutQuickStart(_ lower: String) -> Bool {
        guard lower == "done" || lower == "start" || lower == "let's go" || lower == "ready" || lower == "begin" else { return false }
        guard workoutTemplate != nil else { return false }
        messages.append(ChatMessage(role: .assistant, text: "Starting workout!"))
        pendingExercises = []
        showingWorkout = true
        return true
    }

    /// Phase 5: Multi-turn conversation handlers — resume pending workout, split, meal plan, or meal.
    private func handleMultiTurnState(_ lower: String, originalText: String) -> Bool {
        if handlePendingWorkout(lower) { return true }
        if handlePendingWorkoutSplit(lower) { return true }
        if handlePendingMealPlan(lower) { return true }
        if handleMealContinuation(lower) { return true }
        if handlePendingMeal(lower, originalText: originalText) { return true }
        if handleWorkoutLoggingTrigger(lower) { return true }
        return false
    }

    /// Phase 7: Food & activity intent parsing — meal logging, pronoun resolution, multi/single food, activity, weight, corrections.
    private func handleFoodIntentParsing(_ lower: String, originalText: String) -> Bool {
        if handleMealLogging(lower) { return true }
        let resolved = resolvePronouns(lower)
        if handleMultiFoodIntent(resolved) { return true }
        if handleComposedFoodIntent(resolved) { return true }
        if handleSingleFoodIntent(resolved) { return true }
        if handleActivityLogging(lower) { return true }
        if handleWeightIntent(lower) { return true }
        if handleCheatMeal(lower) { return true }
        if handleCorrection(lower) { return true }
        if handleEatQuestion(lower, originalText: originalText) { return true }
        return false
    }

    // MARK: - Intent Handlers

    private func handleConfirmation(_ lower: String) -> Bool {
        guard lower == "yes" || lower == "yeah" || lower == "yep" || lower == "confirm" || lower == "sure" else { return false }
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
                let muscles = [ExerciseDatabase.bodyPart(for: name)].filter { $0 != "Full Body" && $0 != "Other" }
                let card = WorkoutCardData(name: name, durationMin: durationSec.map { $0 / 60 }, exerciseCount: nil, muscleGroups: muscles)
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
                                              "supplement", "glucose", "biomarker", "tdee", "bmr", "goal",
                                              "protein", "carbs", "fat", "macros", "macro", "how", "what",
                                              "show", "chart", "history", "week", "yesterday", "daily"]
        let words = Set(lower.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: topicSwitchWords) {
            convState.phase = .idle  // Clear stale phase on topic switch
            return false
        }
        var cleaned = lower
        for prefix in ["can you log ", "could you log ", "please log ", "i want to log ",
                       "i had ", "i ate ", "i made ", "we had ", "it was ", "had ", "log "] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)); break }
        }
        // If user re-stated the meal type ("can you log lunch", "log lunch"),
        // re-ask rather than searching for a food named "lunch"
        let mealKeywords: Set<String> = ["breakfast", "lunch", "dinner", "snack"]
        if mealKeywords.contains(cleaned.trimmingCharacters(in: .whitespaces)) {
            messages.append(ChatMessage(role: .assistant,
                text: "What did you have for \(mealName)? List everything — I'll build a meal entry."))
            return true
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
        while let last = stripped.last, "?!.,;:".contains(last) { stripped = String(stripped.dropLast()) }
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
        // Strip trailing punctuation so "log lunch?" → "log lunch" (prevents "?" leaking as food search)
        while let last = stripped.last, "?!.,;:".contains(last) { stripped = String(stripped.dropLast()) }
        guard let verb = ["log ", "ate ", "had ", "add ", "track ", "log for ", "ate for ", "had for ", "add for "].first(where: { stripped.hasPrefix($0) }) else { return false }
        var remainder = String(stripped.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        if remainder.hasPrefix("for ") { remainder = String(remainder.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        // Strip possessive: "my lunch" → "lunch"
        if remainder.hasPrefix("my ") { remainder = String(remainder.dropFirst(3)) }
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
        buildMealFromIntents(intents, resolved: resolved)
        return true
    }

    private func handleComposedFoodIntent(_ resolved: String) -> Bool {
        guard let intents = ComposedFoodParser.parse(resolved), intents.count > 1 else { return false }
        buildMealFromIntents(intents, resolved: resolved)
        return true
    }

    private func buildMealFromIntents(_ intents: [AIActionExecutor.FoodIntent], resolved: String) {
        var mealName = "Meal"
        let lower = resolved.lowercased()
        for (suffix, meal) in [(" for breakfast", "breakfast"), (" for lunch", "lunch"),
                                (" for dinner", "dinner"), (" for snack", "snack")] {
            if lower.hasSuffix(suffix) { mealName = meal; break }
        }
        let foodText = intents.map { intent in
            var s = intent.query
            if let srv = intent.servings, srv != 1 { s = "\(String(format: "%g", srv)) \(s)" }
            if let g = intent.gramAmount { s = "\(Int(g))g \(s)" }
            return s
        }.joined(separator: " and ")
        buildMealFromText(foodText, mealName: mealName)
    }

    private func handleSingleFoodIntent(_ resolved: String) -> Bool {
        guard let intent = AIActionExecutor.parseFoodIntent(resolved) else { return false }
        foodSearchQuery = intent.query
        foodSearchServings = intent.servings
        let detectedMeal = intent.mealHint.flatMap { MealType(rawValue: $0) } ?? MealType.fromHour()
        foodSearchMealType = detectedMeal
        if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
            let f = match.food
            let s = match.servings
            foodSearchServings = s
            let servingText = Self.smartServingText(food: f, servings: s, gramAmount: intent.gramAmount)
            let card = FoodCardData(
                name: f.name, calories: Int(f.calories * s),
                proteinG: Int(f.proteinG * s), carbsG: Int(f.carbsG * s),
                fatG: Int(f.fatG * s), servingText: servingText,
                mealType: detectedMeal)
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
        // Skip structured workout exercises (e.g. "bench press 3x10 at 135") —
        // route to AI pipeline where log_activity properly handles sets/reps/weight.
        if StaticOverrides.containsWorkoutSetPattern(activity) { return false }
        let name = activity.capitalized
        let durText = durationMin.map { " (\($0) min)" } ?? ""
        let muscles = [ExerciseDatabase.bodyPart(for: name)].filter { $0 != "Full Body" && $0 != "Other" }
        let card = WorkoutCardData(name: name, durationMin: durationMin, exerciseCount: nil, muscleGroups: muscles, confirmed: false)
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

        // Treat anything else as a food to add — opens FoodSearch for confirmation (e.g., user types "chicken breast")
        if lower.count > 2 {
            if let intent = AIActionExecutor.parseFoodIntent(lower) {
                foodSearchQuery = intent.query
                foodSearchServings = intent.servings
                foodSearchMealType = MealType(rawValue: mealName)
                if let match = AIActionExecutor.findFood(query: intent.query, servings: intent.servings, gramAmount: intent.gramAmount) {
                    let f = match.food
                    let s = match.servings
                    let servingText = Self.smartServingText(food: f, servings: s, gramAmount: intent.gramAmount)
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

        // Unrecognized input — exit planning mode so the message falls through to the AI pipeline
        convState.phase = .idle
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

    /// Phase 4b: When the assistant has offered 2-3 options ("Did you mean:
    /// 1. Log chicken as food / 2. Look up calories in chicken"), parse the
    /// user's reply against them. Numeric ("1"/"2"), ordinal ("first"),
    /// keyword ("log it"/"calories"), or literal label match resolves to an
    /// option. Cancel phrases reset. Unrecognized input clears the phase
    /// and falls through so the user isn't stuck. #226.
    func handleClarificationResponse(_ lower: String) -> Bool {
        guard case .awaitingClarification(let options) = convState.phase else { return false }
        let cancel: Set<String> = ["nevermind", "never mind", "cancel", "stop",
                                   "neither", "none", "skip", "forget it"]
        if cancel.contains(lower) {
            convState.cancelPending()
            messages.append(ChatMessage(role: .assistant,
                text: "No problem — ask again anytime."))
            return true
        }
        guard let picked = Self.resolveClarificationPick(lower, options: options) else {
            // Unrecognized — drop the phase so the next turn re-classifies
            // naturally. Prevents a stuck "Did you mean" loop.
            convState.phase = .idle
            return false
        }
        convState.phase = .idle
        executePickedClarification(picked)
        return true
    }

    /// Internal for tests — the resolution logic is deterministic and
    /// worth exercising without the async tool-execution roundtrip.
    static func resolveClarificationPick(
        _ lower: String, options: [ClarificationOption]
    ) -> ClarificationOption? {
        // Numeric: "1", "2", "3" — primary chip UX.
        if let idx = Int(lower), let match = options.first(where: { $0.id == idx }) {
            return match
        }
        // Ordinal words.
        let ordinals: [String: Int] = [
            "first": 1, "1st": 1, "one": 1,
            "second": 2, "2nd": 2, "two": 2,
            "third": 3, "3rd": 3, "three": 3
        ]
        if let idx = ordinals[lower], let match = options.first(where: { $0.id == idx }) {
            return match
        }
        // Literal label match (case-insensitive) — happens when the user
        // taps a chip; the label is sent as a new user message.
        if let match = options.first(where: { $0.label.lowercased() == lower }) {
            return match
        }
        // Keyword containment — "log it"/"log chicken"/"calories"/"check"
        // map to the option whose label contains the same verb/topic.
        if lower.contains("log") || lower.contains("add") || lower.contains("track") {
            if let match = options.first(where: { $0.tool == "log_food" || $0.tool == "log_activity" || $0.tool == "mark_supplement" || $0.tool == "log_weight" }) {
                return match
            }
        }
        if lower.contains("calor") || lower.contains("info") || lower.contains("nutrition")
            || lower.contains("check") || lower.contains("look") {
            if let match = options.first(where: { $0.tool == "food_info" || $0.tool == "supplements" }) {
                return match
            }
        }
        return nil
    }

    private func executePickedClarification(_ option: ClarificationOption) {
        Task {
            let call = ToolCall(tool: option.tool, params: ToolCallParams(values: option.params))
            let result = await ToolRegistry.shared.execute(call)
            switch result {
            case .text(let text):
                messages.append(ChatMessage(role: .assistant, text: text))
            case .action(let action):
                dispatchToolAction(action)
            case .error(let msg):
                messages.append(ChatMessage(role: .assistant,
                    text: "Couldn't run that — \(msg.lowercased())."))
            }
        }
    }

    /// Map a UI-action tool result to the VM's side-effectful state. Subset
    /// of handleAIPipeline's action dispatch — kept local so the
    /// clarification execution doesn't pull the full pipeline plumbing.
    private func dispatchToolAction(_ action: ToolAction) {
        switch action {
        case .openFoodSearch(let query, let servings):
            foodSearchQuery = query
            foodSearchServings = servings
            showingFoodSearch = true
        case .navigate(let tab):
            let (label, icon) = Self.tabMeta(tab)
            let card = NavigationCardData(destination: label, icon: icon, tab: tab)
            messages.append(ChatMessage(role: .assistant,
                text: "Opening \(label)...", navigationCard: card))
            NotificationCenter.default.post(name: .navigateToTab,
                object: nil, userInfo: ["tab": tab])
        case .openBarcodeScanner:
            showingBarcodeScanner = true
        case .openManualFoodEntry(let name, let calories, let proteinG, let carbsG, let fatG):
            pendingManualFoodEntry = AIChatViewModel.ManualFoodPrefill(
                name: name, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
            showingManualFoodEntry = true
        case .openWeightEntry, .openRecipeBuilder, .openWorkout:
            // Options we don't currently emit from clarification picks —
            // fall through silently.
            break
        }
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
        // Clear any stale pending intent — if we reached the AI pipeline, the user moved on
        convState.pendingIntent = nil

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

        generationEpoch += 1
        let myEpoch = generationEpoch

        let screen = screenTracker.currentScreen
        let history = buildConversationHistory()
        let isLarge = aiService.isLargeModel

        Task {
            defer {
                // Bump epoch first — any onStep Tasks queued before this point will see a
                // mismatched epoch and skip updating generatingState back to .thinking.
                if generationEpoch == myEpoch { generationEpoch += 1 }
                streamingMessageId = nil
                generatingState = .idle
            }

            let output = await AIToolAgent.run(
                message: text, screen: screen, history: history,
                isLargeModel: isLarge,
                onStep: { [weak self] step in
                    let epoch = myEpoch
                    Task { @MainActor in
                        guard let self, self.generationEpoch == epoch else { return }
                        self.generatingState = .thinking(step: step)
                    }
                },
                onToken: { [weak self] token in
                    let epoch = myEpoch
                    Task { @MainActor in
                        guard let self, self.generationEpoch == epoch else { return }
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
                    messages[idx].clarificationOptions = output.clarificationOptions
                    attachToolCards(to: &messages[idx], toolsCalled: output.toolsCalled)
                }
            }
            // Ask-don't-guess: enter the waiting phase so the next turn is
            // resolved against the options rather than re-classified. #226.
            if let options = output.clarificationOptions {
                convState.phase = .awaitingClarification(options: options)
            }

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
                case .openManualFoodEntry(let name, let calories, let proteinG, let carbsG, let fatG):
                    pendingManualFoodEntry = AIChatViewModel.ManualFoodPrefill(
                        name: name, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
                    showingManualFoodEntry = true
                }
            }
        }
    }

    // MARK: - Tool Card Attachment

    /// After LLM tool execution, attach structured cards based on which tools ran.
    private func attachToolCards(to message: inout ChatMessage, toolsCalled: [String]) {
        let tools = Set(toolsCalled)

        // Nutrition lookup card — food_info resolved a specific food
        if tools.contains("food_info"), let food = AIDataCache.shared.lastFoodLookupFood {
            AIDataCache.shared.lastFoodLookupFood = nil
            let s = food.servingSize
            message.nutritionCard = NutritionLookupCardData(
                name: food.name,
                calories100g: Int(food.calories / s * 100),
                proteinG100g: Int(food.proteinG / s * 100),
                carbsG100g: Int(food.carbsG / s * 100),
                fatG100g: Int(food.fatG / s * 100),
                servingSize: Int(s),
                servingUnit: food.servingUnit,
                servingCalories: Int(food.calories),
                servingProteinG: Int(food.proteinG),
                servingCarbsG: Int(food.carbsG),
                servingFatG: Int(food.fatG)
            )
        }

        // Supplement card — for status, mark, or add
        if !tools.isDisjoint(with: ["supplements", "mark_supplement", "add_supplement"]) {
            let today = DateFormatters.todayString
            let supplements = (try? AppDatabase.shared.fetchActiveSupplements()) ?? []
            let logs = (try? AppDatabase.shared.fetchSupplementLogs(for: today)) ?? []
            let takenIds = Set(logs.filter(\.taken).compactMap(\.supplementId))
            let remaining = supplements.filter { !takenIds.contains($0.id ?? 0) }.map(\.name)

            let action: String? = tools.contains("mark_supplement") || tools.contains("add_supplement")
                ? message.text.components(separatedBy: "\n").first
                : nil

            message.supplementCard = SupplementCardData(
                taken: takenIds.count,
                total: supplements.count,
                remaining: remaining,
                action: action
            )
        }

        // Sleep & recovery card
        if tools.contains("sleep_recovery") {
            if let data = AIDataCache.shared.sleep {
                let readiness: String? = {
                    if data.recoveryScore >= 70 { return "Good to train" }
                    if data.recoveryScore >= 40 { return "Moderate" }
                    if data.recoveryScore > 0 { return "Low recovery" }
                    return nil
                }()
                message.sleepCard = SleepCardData(
                    sleepHours: data.sleepHours > 0 ? data.sleepHours : nil,
                    remHours: data.sleepDetail?.remHours,
                    deepHours: data.sleepDetail?.deepHours,
                    recoveryScore: data.recoveryScore > 0 ? data.recoveryScore : nil,
                    hrvMs: data.hrvMs > 0 ? Int(data.hrvMs) : nil,
                    restingHR: data.restingHR > 0 ? Int(data.restingHR) : nil,
                    readiness: readiness
                )
            }
        }

        // Glucose card
        if tools.contains("glucose") {
            let today = DateFormatters.todayString
            if let readings = try? AppDatabase.shared.fetchGlucoseReadings(from: today, to: today),
               !readings.isEmpty {
                let values = readings.map(\.glucoseMgdl)
                let avg = values.reduce(0, +) / Double(values.count)
                let inZone = values.filter { $0 >= 70 && $0 <= 140 }.count
                let spikes = values.filter { $0 > 140 }
                message.glucoseCard = GlucoseCardData(
                    avgMgdl: Int(avg),
                    minMgdl: Int(values.min() ?? 0),
                    maxMgdl: Int(values.max() ?? 0),
                    inZonePct: Int(Double(inZone) / Double(values.count) * 100),
                    readingCount: readings.count,
                    spikeCount: spikes.count,
                    peakMgdl: spikes.isEmpty ? nil : Int(spikes.max() ?? 0)
                )
            }
        }

        // Biomarker card
        if tools.contains("biomarkers") {
            if let results = try? AppDatabase.shared.fetchLatestBiomarkerResults(),
               !results.isEmpty {
                var outOfRange: [BiomarkerCardData.OutOfRangeMarker] = []
                var optimal = 0
                for r in results {
                    if let def = BiomarkerKnowledgeBase.byId[r.biomarkerId] {
                        let status = def.status(for: r.normalizedValue)
                        if status != .optimal {
                            outOfRange.append(.init(
                                name: def.name,
                                value: "\(String(format: "%.1f", r.normalizedValue)) \(def.unit)",
                                status: "\(status)"
                            ))
                        } else {
                            optimal += 1
                        }
                    }
                }
                message.biomarkerCard = BiomarkerCardData(
                    totalCount: results.count,
                    optimalCount: optimal,
                    outOfRange: outOfRange
                )
            }
        }
    }
}
