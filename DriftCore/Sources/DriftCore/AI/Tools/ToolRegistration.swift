import Foundation
import DriftCore

/// Registers all service tools in the ToolRegistry.
/// Called once at app startup.
@MainActor
public enum ToolRegistration {

    public static func registerAll() {
        let r = ToolRegistry.shared

        // MARK: - Food Tools (3 — consolidated from 7)
        // Small models need FEWER, MORE DISTINCT tools

        r.register(ToolSchema(
            id: "food.log_food", name: "log_food", service: "food",
            description: "User wants to LOG/ADD food they ate. Use this when they say 'I had', 'ate', 'log', 'add'.",
            parameters: [ToolParam("name", "string", "Food name"),
                         ToolParam("amount", "number", "How many servings or grams (e.g. '200g', '2')", required: false),
                         ToolParam("calories", "number", "Custom calories if specified", required: false),
                         ToolParam("protein", "number", "Custom protein grams", required: false),
                         ToolParam("carbs", "number", "Custom carbs grams", required: false),
                         ToolParam("fat", "number", "Custom fat grams", required: false)],
            preHook: { params in
                guard let rawName = params.string("name")?.trimmingCharacters(in: .whitespaces),
                      !rawName.isEmpty else {
                    // Empty name — likely "log lunch" without food specified
                    let meal = params.string("meal") ?? "food"
                    return .invalid(reason: "What did you have for \(meal)?")
                }

                // Meal words aren't foods — ask follow-up instead of searching
                let mealWords: Set<String> = ["breakfast", "lunch", "dinner", "snack", "meal", "food", "brunch"]
                let lowerName = rawName.lowercased()
                if mealWords.contains(lowerName) {
                    return .invalid(reason: "What did you have for \(lowerName)?")
                }

                // Conversational phrases aren't food names — reject gracefully
                let conversationalVerbs = ["love", "hate", "prefer", "enjoy", "like", "want", "need", "miss"]
                if conversationalVerbs.contains(where: { lowerName.contains(" \($0) ") || lowerName.contains(" \($0)s ") || lowerName.hasPrefix("\($0) ") }),
                   mealWords.contains(where: { lowerName.contains($0) }) {
                    let meal = mealWords.first(where: { lowerName.contains($0) }) ?? "food"
                    return .invalid(reason: "What did you have for \(meal)?")
                }

                var name = rawName
                var gramAmount: Double? = nil
                var servings = params.double("amount")

                // --- Route 1: Has custom calories → open prefilled manual entry for review ---
                if let cal = params.double("calories"), cal > 0 {
                    // Validate range
                    guard cal <= 10000 else { return .invalid(reason: "That's over 10,000 calories — did you mean something else?") }
                    let p = params.double("protein") ?? 0
                    let c = params.double("carbs") ?? 0
                    let f = params.double("fat") ?? 0
                    guard p >= 0, c >= 0, f >= 0 else { return .invalid(reason: "Macros can't be negative.") }
                    // Open ManualFoodEntrySheet prefilled — user reviews before logging
                    return .route(.action(.openManualFoodEntry(name: name, calories: Int(cal), proteinG: p, carbsG: c, fatG: f)))
                }

                // Parse gram amounts: "paneer biryani 200g" or amount="200g"
                if let amtStr = params.string("amount") {
                    let gramPattern = #"^(\d+\.?\d*)\s*g(?:ram)?s?$"#
                    if let regex = try? NSRegularExpression(pattern: gramPattern, options: .caseInsensitive),
                       let match = regex.firstMatch(in: amtStr, range: NSRange(amtStr.startIndex..., in: amtStr)),
                       let numRange = Range(match.range(at: 1), in: amtStr),
                       let grams = Double(String(amtStr[numRange])) {
                        gramAmount = grams
                        servings = nil
                    }
                }

                // Parse "200g" embedded in name
                let nameGramPattern = #"\s+(\d+\.?\d*)\s*g(?:ram)?s?\s*$"#
                if gramAmount == nil,
                   let regex = try? NSRegularExpression(pattern: nameGramPattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let numRange = Range(match.range(at: 1), in: name),
                   let matchRange = Range(match.range, in: name),
                   let grams = Double(String(name[numRange])) {
                    gramAmount = grams
                    name = String(name[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }

                // --- Route 2: Multi-item → recipe builder (AI names, no DB substitution) ---
                let items = name.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if items.count > 1 {
                    let firstName = items[0]
                    var enriched: [String: String] = ["name": firstName]
                    if let s = servings { enriched["amount"] = "\(s)" }
                    enriched["remaining_items"] = items.dropFirst().joined(separator: ", ")
                    return .transform(ToolCallParams(values: enriched))
                }

                // --- Route 3: Pass through → openFoodSearch so user confirms the food ---
                var enriched: [String: String] = ["name": name]
                if let s = servings { enriched["amount"] = "\(s)" }
                return .transform(ToolCallParams(values: enriched))
            },
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing food name") }
                // Custom macros handled by preHook (.route) — won't reach here
                // Multi-item: open recipe builder with all items
                if let remaining = params.string("remaining_items"), !remaining.isEmpty {
                    let allItems = [name] + remaining.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let meal = params.string("meal")
                    return .action(.openRecipeBuilder(items: allItems, mealName: meal))
                }
                return .action(.openFoodSearch(query: name, servings: params.double("amount")))
            }
        ))

        r.register(ToolSchema(
            id: "food.food_info", name: "food_info", service: "food",
            description: "User asks ABOUT food: calories, protein, nutrition, 'what should I eat', diet questions. NOT for logging.",
            parameters: [ToolParam("query", "string", "What they asked about", required: false)],
            handler: { params in
                let query = (params.string("query") ?? "").lowercased()

                // Classify intent up front so it gates BOTH the food-lookup branch and
                // the macro-intake branches below. A macro-INTAKE question ("what's my
                // protein today", "carbs today", bare "protein") asks about the user's
                // logged totals; a food LOOKUP ("protein in chicken") or a SUGGESTION
                // ("suggest a high protein dinner") must NOT resolve to the user's totals.
                // Without this, "protein in chicken" fuzzy-matched to a macro total and
                // "suggest high protein" returned "Protein: 41g". #macro-intake
                let macroWords = ["protein", "carbs", "carb", "fat", "fiber", "fibre",
                                  "calories", "calorie", "cals", "macros"]
                let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
                let isLookupPhrase = query.contains(" in ") || query.contains(" for ")
                let isSuggestPhrase = query.contains("suggest") || query.contains("what should") ||
                    query.contains("what to eat") || query.contains("recommend") || query.contains("recipe")
                // Personal/diary signals — the user asking about THEIR macros. Includes
                // goal/target/progress words because the cloud model rewrites "what's my
                // protein today" → "protein goal" (it reads "my … today" as a goal check),
                // and the macro-intake branch answers exactly that ("Protein: 41g / 128g
                // goal — 32% to go"). Without "goal"/"target" here, "protein goal" fuzzy-
                // matched a food ("Soy Protein Isolate", "…Pferde - Goal"). #macro-intake
                let hasPersonalSignal = ["my ", "today", "have i", "i've", "i ate", "eaten",
                                         "so far", "yesterday", "this week", "intake",
                                         "tracked", "logged", " left", " remaining",
                                         "goal", "target", "progress", "limit", "hitting",
                                         "on track", "how much", "how many", "how am i"]
                    .contains { query.contains($0) }
                let isMacroIntake = !isLookupPhrase && !isSuggestPhrase &&
                    (macroWords.contains(trimmedQuery) ||
                     (macroWords.contains { query.contains($0) } && hasPersonalSignal))
                // #1032: "what did I eat" / "what's in my diary" / "list my meals" want the
                // MEAL LIST, not a food lookup or the "how am I doing" totals summary.
                let isDiaryListing = query.contains("what did i eat") || query.contains("what have i eaten") ||
                    query.contains("what did i log") || query.contains("what have i logged") ||
                    query.contains("list my meal") || query.contains("show my meal") ||
                    query.contains("what's in my") || query.contains("what is in my")

                // Nutrition lookup for specific food: "calories in banana", "estimate calories for samosa"
                if !query.isEmpty {
                    // Strip common prefixes to extract just the food name
                    var foodName = query
                    let prefixes = ["calories in ", "calories for ", "estimate calories for ", "estimate calories in ",
                                     "how many calories in ", "how many calories does ", "nutrition for ",
                                     "macros in ", "macros for ", "protein in ", "how much protein in "]
                    for prefix in prefixes {
                        if foodName.hasPrefix(prefix) { foodName = String(foodName.dropFirst(prefix.count)); break }
                    }
                    // Strip trailing "have/has/contain" and leading articles
                    for suffix in [" have", " has", " contain"] {
                        if foodName.hasSuffix(suffix) { foodName = String(foodName.dropLast(suffix.count)) }
                    }
                    for prefix in ["a ", "an ", "one "] {
                        if foodName.hasPrefix(prefix) { foodName = String(foodName.dropFirst(prefix.count)) }
                    }
                    foodName = foodName.trimmingCharacters(in: .whitespaces)

                    // Diary/tracking queries ("calories left", "how many calories left") should fall
                    // through to the summary logic below — not trigger a food lookup.
                    // Guard: skip lookup if foodName still contains question/diary phrases after stripping.
                    let isDiaryQuery = foodName.hasSuffix(" left") || foodName.hasSuffix(" remaining") ||
                        (foodName.hasPrefix("how many") && !foodName.contains(" in ") && !foodName.contains(" for ")) ||
                        (foodName.hasPrefix("how much") && !foodName.contains(" in ") && !foodName.contains(" for ")) ||
                        foodName.contains("how am i") || foodName.contains("on track") || foodName.contains("so far")
                    // Summary/period queries ("weekly summary", "daily summary", "today",
                    // "yesterday") from suggestion chips were being fuzzy-matched to foods
                    // like "Mix secos y arandanos - Weekly!" by the online fallback. Route
                    // these straight to the period-summary branch below. #249.
                    let isSummaryQuery = foodName.contains("summary") ||
                        foodName == "today" || foodName == "yesterday" ||
                        foodName == "weekly" || foodName == "this week" ||
                        foodName == "daily"

                    if !isDiaryQuery && !isSummaryQuery && !isMacroIntake && !isDiaryListing {
                        if !foodName.isEmpty, let result = FoodService.getNutrition(name: foodName) {
                            AIDataCache.shared.lastFoodLookupFood = result.food
                            return .text("\(result.perServing) Say 'log \(result.food.name.lowercased())' to add it.")
                        }
                        // Also try the raw query as food name
                        if let result = FoodService.getNutrition(name: query) {
                            AIDataCache.shared.lastFoodLookupFood = result.food
                            return .text("\(result.perServing) Say 'log \(result.food.name.lowercased())' to add it.")
                        }
                        // Try USDA/OpenFoodFacts if enabled and not found locally (5s timeout)
                        let lookupQuery = foodName.isEmpty ? query : foodName
                        let onlineResults = await IntentClassifier.withTimeout(seconds: 5) {
                            await FoodService.searchWithFallback(query: lookupQuery, localThreshold: 1)
                        } ?? []
                        if let best = onlineResults.first {
                            let desc = "\(best.name) (per \(Int(best.servingSize))\(best.servingUnit)): \(Int(best.calories)) cal, \(Int(best.proteinG))g protein, \(Int(best.carbsG))g carbs, \(Int(best.fatG))g fat"
                            return .text("\(desc) Say 'log \(best.name.lowercased())' to add it.")
                        }
                    }
                }

                // #1032: meal-by-meal listing for "what did I eat" phrasings (the data already
                // lives in foodContext; here we return it as the answer instead of totals).
                if isDiaryListing {
                    let isYesterday = query.contains("yesterday")
                    let dateStr = isYesterday
                        ? DateFormatters.dateOnly.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
                        : DateFormatters.todayString
                    if let listing = FoodService.diaryListing(for: dateStr) {
                        return .text(listing)
                    }
                    return .text("Nothing logged \(isYesterday ? "yesterday" : "today") yet.")
                }

                let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
                let goal = WeightGoal.load()
                let targets = goal?.macroTargets(currentWeightKg: WeightTrendService.shared.trendWeight)

                // Macro-specific focus: "how is my protein", "carbs today", "fat intake",
                // "am I hitting my protein goal". Gated on isMacroIntake so a suggestion
                // ("suggest a high protein dinner") or an unresolved lookup ("protein in X")
                // falls through to the suggest/summary branches instead of reporting totals.
                if isMacroIntake && query.contains("protein") {
                    guard n.proteinG > 0 else { return .text("No food logged yet. Log meals to track protein.") }
                    // Prefer explicit user-set proteinGoal (#441); fall back to macro-breakdown target
                    let proteinTarget = goal?.proteinGoal ?? targets.map { $0.proteinG }
                    if let target = proteinTarget {
                        var response = FoodService.macroProgressLine(
                            label: "Protein", currentG: Int(n.proteinG), targetG: Int(target))
                        let left = max(0, Int(target - n.proteinG))
                        let topP = FoodService.topProteinFoods(limit: 3)
                        if left > 20 && !topP.isEmpty {
                            response += " Try: " + topP.map { "\($0.name) (\(Int($0.proteinG))P)" }.joined(separator: ", ")
                        }
                        return .text(response)
                    }
                    return .text("\(Int(n.proteinG))g protein today.")
                }
                if query.contains("calori") && (query.contains("goal") || query.contains("target") || query.contains("hitting") || query.contains("on track")) {
                    // Explicit calorie goal check: "am I hitting my calorie goal?" (#441)
                    let calTarget = goal?.calorieGoal ?? targets.map { $0.calorieTarget }
                    if let target = calTarget {
                        return .text(FoodService.macroProgressLine(
                            label: "Calories", currentG: Int(n.calories), targetG: Int(target), unit: " cal"))
                    }
                }
                // "Calories left today" / "calories remaining" — direct clean answer
                if query.contains("calori") && (query.contains("left") || query.contains("remain")) {
                    return .text(FoodService.getCaloriesLeft())
                }
                if isMacroIntake && query.contains("carb") {
                    if let t = targets {
                        return .text(FoodService.macroProgressLine(
                            label: "Carbs", currentG: Int(n.carbsG), targetG: Int(t.carbsG)))
                    }
                    return .text("\(Int(n.carbsG))g carbs today.")
                }
                if isMacroIntake && query.contains("fat") && !query.contains("body fat") {
                    if let t = targets {
                        return .text(FoodService.macroProgressLine(
                            label: "Fat", currentG: Int(n.fatG), targetG: Int(t.fatG)))
                    }
                    return .text("\(Int(n.fatG))g fat today.")
                }

                // Sugar / fiber query
                if isMacroIntake && (query.contains("sugar") || query.contains("fiber")) {
                    let macro = query.contains("sugar") ? "carbs" : "fiber"
                    let value = query.contains("sugar") ? n.carbsG : n.fiberG
                    var response = "\(Int(value))g \(macro) today."
                    if let t = targets {
                        let target = query.contains("sugar") ? t.carbsG : 25.0 // 25g fiber default
                        response += " Target: \(Int(target))g."
                    }
                    if query.contains("sugar") { response += " (Drift tracks total carbs — sugar isn't tracked separately.)" }
                    return .text(response)
                }

                // Yesterday summary
                if query.contains("yesterday") {
                    return .text(AIRuleEngine.yesterdaySummary())
                }
                // Historical weekday queries: "calories last tuesday", "what did I eat on monday"
                if let historicalDate = AIRuleEngine.weekdayDateString(from: query) {
                    return .text(AIRuleEngine.historicalDaySummary(dateStr: historicalDate))
                }
                // Weekly summary
                if query.contains("weekly") || query.contains("week") {
                    return .text(AIRuleEngine.weeklySummary())
                }
                // Meal suggestions
                if query.contains("suggest") || query.contains("what should") || query.contains("what to eat") {
                    let totals = FoodService.getDailyTotals()
                    let targets = goal?.macroTargets(currentWeightKg: WeightTrendService.shared.trendWeight)
                    let protLeft = targets.map { max(0, Int($0.proteinG) - totals.proteinG) }
                    let suggestions = FoodService.suggestMeal(caloriesLeft: totals.remaining, proteinNeeded: protLeft)
                    var lines = ["\(totals.remaining) cal remaining. \(protLeft.map { "Need \($0)g more protein." } ?? "")"]
                    if !suggestions.isEmpty {
                        lines.append("Suggestions: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories)) cal, \(Int($0.proteinG))g protein)" }.joined(separator: ", "))
                    }
                    return .text(lines.joined(separator: "\n"))
                }

                // Diet/fitness advice: "how to lose fat", "reduce fat", "what's a good diet"
                let dietKeywords = ["reduce fat", "lose fat", "burn fat", "cut fat", "how to lose",
                                     "gain muscle", "bulk", "what's a good diet", "diet tips", "diet advice"]
                if dietKeywords.contains(where: { query.contains($0) }) {
                    if let t = targets {
                        let calsLeft = max(0, Int(t.calorieTarget - n.calories))
                        let protLeft = max(0, Int(t.proteinG - n.proteinG))
                        return .text("Focus on protein (\(protLeft)g left today), stay in calorie budget (\(calsLeft) cal left). High-protein foods: chicken, eggs, greek yogurt, paneer, dal.")
                    }
                    return .text("Key tips: prioritize protein, eat in a calorie deficit for fat loss (or surplus for muscle gain). Track your meals to stay on target.")
                }

                // Multi-item total macros: "total macros for dal, rice, and roti", "X, Y, Z total calories"
                // Detects: comma-separated foods + "total"/"combined"/"together" + macro keyword
                let hasMultiItemSignal = query.contains(",") &&
                    (query.contains("total") || query.contains("combined") || query.contains("together")) &&
                    (query.contains("macros") || query.contains("calori") || query.contains("protein") || query.contains("carb") || query.contains("fat"))
                if hasMultiItemSignal {
                    var foodPart = query
                    for pfx in ["what are the total macros for ", "total macros for ", "total calories for ",
                                 "total calories in ", "how many calories in ", "combined macros for ",
                                 "macros for ", "total protein in "] {
                        if foodPart.hasPrefix(pfx) { foodPart = String(foodPart.dropFirst(pfx.count)); break }
                    }
                    for sfx in [" combined", " total", " together", " all together", " in total", "?"] {
                        while foodPart.hasSuffix(sfx) {
                            foodPart = foodPart.dropLast(sfx.count).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    var items = [foodPart]
                    for sep in [", and ", ", & ", " and ", ", "] {
                        items = items.flatMap { $0.components(separatedBy: sep) }
                    }
                    items = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if items.count > 1 {
                        var totCal = 0, totP = 0, totC = 0, totF = 0
                        var found: [String] = [], notFound: [String] = []
                        for item in items {
                            if let r = FoodService.getNutrition(name: item) {
                                totCal += Int(r.food.calories); totP += Int(r.food.proteinG)
                                totC += Int(r.food.carbsG); totF += Int(r.food.fatG)
                                found.append(r.food.name)
                            } else {
                                notFound.append(item)
                            }
                        }
                        if found.count > 1 {
                            var resp = "Total (\(found.joined(separator: " + "))): \(totCal) cal, \(totP)g protein, \(totC)g carbs, \(totF)g fat."
                            if !notFound.isEmpty { resp += " (Not found: \(notFound.joined(separator: ", ")))" }
                            return .text(resp)
                        }
                    }
                }

                // General food info: calories, macros, meal count, suggestions, context
                let today = DateFormatters.todayString
                let totals = FoodService.getDailyTotals()
                var lines: [String] = []
                let pctEaten = totals.target > 0 ? Int(Double(totals.eaten) / Double(totals.target) * 100) : 0
                lines.append("Calories: \(totals.eaten) eaten of \(totals.target) target (\(totals.remaining > 0 ? "\(totals.remaining) remaining" : "\(abs(totals.remaining)) over")).")
                // Meal count + last meal time
                if let entries = try? AppDatabase.shared.fetchFoodEntries(for: today), !entries.isEmpty {
                    lines.append("Meals today: \(entries.count) items logged.")
                    if let last = entries.first { // sorted DESC, first = most recent
                        lines.append("Last logged: \(last.foodName).")
                    }
                }
                // Progress indicator for LLM context
                if pctEaten < 30 { lines.append("Status: early in the day, plenty of budget left.") }
                else if pctEaten >= 80 && pctEaten <= 105 { lines.append("Status: close to target, on track.") }
                else if pctEaten > 105 { lines.append("Status: over target by \(abs(totals.remaining)) cal.") }

                if let t = targets {
                    let pLeft = max(0, Int(t.proteinG) - totals.proteinG)
                    let cLeft = max(0, Int(t.carbsG) - totals.carbsG)
                    let fLeft = max(0, Int(t.fatG) - totals.fatG)
                    lines.append("Macros: \(totals.proteinG)P/\(totals.carbsG)C/\(totals.fatG)F. Need: \(pLeft)P \(cLeft)C \(fLeft)F more.")
                }

                let suggestions = FoodService.suggestMeal()
                if !suggestions.isEmpty {
                    lines.append("Try: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories))cal, \(Int($0.proteinG))P)" }.joined(separator: ", "))
                }

                if totals.proteinG < 50 {
                    let topP = FoodService.topProteinFoods(limit: 3)
                    if !topP.isEmpty {
                        lines.append("High protein: " + topP.map { "\($0.name) (\(Int($0.proteinG))P)" }.joined(separator: ", "))
                    }
                }

                // Include supplement + workout status for broad status queries
                if query.contains("how") || query.contains("doing") || query.contains("summary") || query.contains("status") {
                    let today = DateFormatters.todayString
                    if let supps = try? AppDatabase.shared.fetchActiveSupplements(), !supps.isEmpty,
                       let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) {
                        let taken = logs.filter(\.taken).count
                        lines.append("Supplements: \(taken)/\(supps.count) taken.")
                    }
                    if let workouts = try? WorkoutService.fetchWorkouts(limit: 10) {
                        let todayWorkouts = workouts.filter { $0.date == today }
                        if !todayWorkouts.isEmpty {
                            lines.append("Workout: \(todayWorkouts.map(\.name).joined(separator: ", "))")
                        }
                    }
                }

                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "food.copy_yesterday", name: "copy_yesterday", service: "food",
            description: "User wants to COPY or REPEAT yesterday's food. Use when they say 'same as yesterday', 'copy yesterday'.",
            parameters: [],
            handler: { _ in .text(FoodService.previewYesterday()) }
        ))

        r.register(ToolSchema(
            id: "food.delete_food", name: "delete_food", service: "food",
            description: "User wants to REMOVE or DELETE a food entry. Use when they say 'remove', 'delete', 'undo food'. Prefer entry_id when a recent-entries window row matches; falls back to name/ordinal.",
            parameters: [
                ToolParam("entry_id", "number", "Stable id of a recently-logged entry (from <recent_entries> context)", required: false),
                ToolParam("name", "string", "Food name to remove, 'last' for most recent, or an ordinal like 'first'/'second to last'", required: false)
            ],
            handler: { params in .text(DeleteFoodHandler.run(params: params)) }
        ))

        r.register(ToolSchema(
            id: "food.edit_meal", name: "edit_meal", service: "food",
            description: "User wants to MODIFY a food entry inside a specific meal — e.g. 'remove rice from lunch', 'change chicken to 2 servings', 'update oatmeal to 200g', 'replace rice with quinoa in lunch', 'edit the 500 cal one'. Accepts entry_id from <recent_entries> context for precise multi-turn references; falls back to name match.",
            parameters: [
                ToolParam("entry_id", "number", "Stable id of a recently-logged entry (from <recent_entries> context)", required: false),
                ToolParam("meal_period", "string", "Which meal: breakfast | lunch | dinner | snack", required: false),
                ToolParam("action", "string", "remove | update_quantity | replace"),
                ToolParam("target_food", "string", "Name of the food to edit (or an ordinal). Optional when entry_id is given.", required: false),
                ToolParam("new_value", "string", "For update_quantity: new quantity ('2', '1.5', '200g'). For replace: the replacement food name.", required: false)
            ],
            handler: { params in .text(EditMealHandler.run(params: params)) }
        ))

        r.register(ToolSchema(
            id: "food.explain_calories", name: "explain_calories", service: "food",
            description: "User asks HOW calories are calculated, what TDEE means, or why their target is a certain number.",
            parameters: [],
            handler: { _ in .text(FoodService.explainCalories()) }
        ))

        // MARK: - Hydration Tools

        r.register(ToolSchema(
            id: "hydration.log_water", name: "log_water", service: "hydration",
            description: "User wants to LOG water or fluid intake. Use when they say 'drank', 'had water', 'drinking', 'gulped', or mention a quantity of water/juice/tea.",
            parameters: [
                ToolParam("amount", "number", "Quantity of fluid"),
                ToolParam("unit", "string", "ml, l, oz, cups, glass, bottle — default ml", required: false)
            ],
            validate: { params in
                guard let amount = params.double("amount"), amount > 0 else { return "Missing amount" }
                let unit = params.string("unit") ?? "ml"
                guard let ml = HydrationService.parseMl(amount: amount, unit: unit) else {
                    return "Unknown unit '\(unit)'. Use ml, l, oz, cups, glass, or bottle."
                }
                if ml < 10 || ml > 5000 { return "Amount \(Int(ml))ml is outside valid range (10–5000ml)" }
                return nil
            },
            handler: { params in
                guard let amount = params.double("amount") else { return .error("Missing amount") }
                let unit = params.string("unit") ?? "ml"
                guard let ml = HydrationService.parseMl(amount: amount, unit: unit) else {
                    return .error("Unknown unit '\(unit)'")
                }
                do {
                    let totalMl = try HydrationService.logWater(amountMl: ml)
                    let goal = Preferences.waterGoalMl
                    let pct = Int((totalMl / goal * 100).rounded())
                    let logged = ml >= 1000
                        ? String(format: "%.1fL", ml / 1000)
                        : "\(Int(ml))ml"
                    let total = totalMl >= 1000
                        ? String(format: "%.1fL", totalMl / 1000)
                        : "\(Int(totalMl))ml"
                    return .text("Logged \(logged). Today: \(total)/\(Int(goal))ml (\(pct)%).")
                } catch {
                    return .error("Couldn't save water entry.")
                }
            }
        ))

        // MARK: - Weight Tools (2 — consolidated from 4)

        r.register(ToolSchema(
            id: "weight.log_weight", name: "log_weight", service: "weight",
            description: "User wants to LOG their body weight. Use when they say 'I weigh', 'my weight is', 'scale says'.",
            parameters: [ToolParam("value", "number", "Weight number"), ToolParam("unit", "string", "kg or lbs", required: false)],
            needsConfirmation: true,
            validate: { params in
                guard let value = params.double("value") else { return "Missing weight value" }
                let unit = params.string("unit") ?? "lbs"
                let kg = unit.lowercased().hasPrefix("kg") ? value : value / 2.20462
                if kg < 20 || kg > 300 { return "Weight \(value) \(unit) is outside valid range" }
                return nil
            },
            handler: { params in
                guard let value = params.double("value") else { return .error("Missing weight value") }
                let unit = params.string("unit") ?? "lbs"
                // Show confirmation first — Swift pre-parser handles actual logging
                return .text("Log \(String(format: "%.1f", value)) \(unit) for today? Say 'yes' to confirm.")
            }
        ))

        r.register(ToolSchema(
            id: "weight.weight_info", name: "weight_info", service: "weight",
            description: "User asks ABOUT their weight: trend, progress, goal, body fat, BMI. NOT for logging.",
            parameters: [ToolParam("query", "string", "What they asked about weight", required: false)],
            handler: { params in
                let query = (params.string("query") ?? "").lowercased()
                var lines: [String] = []
                let unit = Preferences.weightUnit
                let currentKg = WeightTrendService.shared.latestWeightKg

                // Current weight + trend
                lines.append(WeightServiceAPI.describeTrend())

                // Goal progress
                if let goal = WeightGoal.load(), let cw = currentKg {
                    let remaining = abs(goal.remainingKg(currentWeightKg: cw))
                    let direction = goal.isLosing(currentWeightKg: cw) ? "lose" : "gain"
                    let progress = goal.progress(currentWeightKg: cw)
                    lines.append("Goal: \(direction) \(String(format: "%.1f", unit.convert(fromKg: remaining))) \(unit.displayName) to reach \(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))). \(Int(progress * 100))% done.")
                }

                // Weight changes
                if let changes = WeightTrendService.shared.weightChanges {
                    if let d7 = changes.sevenDay {
                        lines.append("This week: \(String(format: "%+.1f", unit.convert(fromKg: d7))) \(unit.displayName)")
                    }
                    if let d90 = changes.ninetyDay {
                        lines.append("90-day: \(String(format: "%+.1f", unit.convert(fromKg: d90))) \(unit.displayName)")
                    }
                }

                // TDEE if asked
                if query.contains("tdee") || query.contains("bmr") || query.contains("burn") {
                    let est = TDEEEstimator.shared.cachedOrSync()
                    lines.append("TDEE: \(Int(est.tdee)) cal/day (\(est.source.rawValue)).")
                    if let goal = WeightGoal.load(), let cw = currentKg {
                        let target = goal.resolvedCalorieTarget(currentWeightKg: cw) ?? est.tdee
                        lines.append("Calorie target: \(Int(target)) cal/day.")
                    }
                }

                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "weight.set_goal", name: "set_goal", service: "weight",
            description: "User wants to SET or UPDATE a goal. Handles weight ('set goal to 75kg'), calorie ('set calorie goal to 2000'), or protein ('set protein target to 150g') goals.",
            parameters: [
                ToolParam("target", "number", "Target value (weight kg/lbs, calories kcal, or protein grams)"),
                ToolParam("goal_type", "string", "weight | calorie | protein (default: weight)", required: false),
                ToolParam("unit", "string", "kg or lbs for weight goals", required: false)
            ],
            handler: { params in
                guard let target = params.double("target") else { return .error("Missing target value") }
                let goalType = params.string("goal_type")?.lowercased() ?? "weight"

                switch goalType {
                case "calorie":
                    guard target >= 1200 && target <= 5000 else {
                        return .error("Calorie goal \(Int(target)) is outside valid range (1200–5000). 1200 is the floor — anything lower isn't safe to recommend.")
                    }
                    let currentKg = WeightTrendService.shared.latestWeightKg ?? 70
                    var goal = WeightGoal.load() ?? WeightGoal(targetWeightKg: currentKg, monthsToAchieve: 6,
                        startDate: DateFormatters.todayString, startWeightKg: currentKg)
                    goal.calorieTargetOverride = target
                    goal.save()
                    return .text("Calorie goal set to \(Int(target)) kcal/day.")

                case "protein":
                    guard target >= 20 && target <= 400 else {
                        return .error("Protein goal \(Int(target))g is outside valid range (20–400g).")
                    }
                    let currentKg = WeightTrendService.shared.latestWeightKg ?? 70
                    var goal = WeightGoal.load() ?? WeightGoal(targetWeightKg: currentKg, monthsToAchieve: 6,
                        startDate: DateFormatters.todayString, startWeightKg: currentKg)
                    goal.proteinGoal = target
                    goal.save()
                    return .text("Protein goal set to \(Int(target))g/day.")

                default: // "weight"
                    let unit = params.string("unit") ?? Preferences.weightUnit.rawValue
                    let targetKg = unit.lowercased().hasPrefix("kg") ? target : target / 2.20462
                    if targetKg < 20 || targetKg > 200 { return .error("Target \(target) \(unit) is outside valid range.") }
                    let currentKg = WeightTrendService.shared.latestWeightKg ?? targetKg
                    var goal = WeightGoal.load() ?? WeightGoal(targetWeightKg: targetKg, monthsToAchieve: 6,
                        startDate: DateFormatters.todayString, startWeightKg: currentKg)
                    goal.targetWeightKg = targetKg
                    goal.save()
                    let display = unit.lowercased().hasPrefix("kg") ? String(format: "%.1f kg", target) : String(format: "%.0f lbs", target)
                    return .text("Goal set to \(display).")
                }
            }
        ))

        // MARK: - Exercise Tools (2 — consolidated from 4)

        r.register(ToolSchema(
            id: "exercise.start_workout", name: "start_workout", service: "exercise",
            description: "User wants to START or BEGIN a workout. Use when they say 'start', 'begin', 'let's do', or name a body part.",
            parameters: [ToolParam("name", "string", "Template name or muscle group like 'chest', 'legs', 'push day'")],
            handler: { params in
                guard let name = params.string("name") else { return .text(ExerciseService.suggestWorkout()) }
                // Try template first
                if let _ = ExerciseService.startTemplate(name: name) {
                    return .action(.openWorkout(templateName: name))
                }
                // Build smart session for muscle group — open directly
                if let _ = ExerciseService.buildSmartSession(muscleGroup: name) {
                    return .action(.openWorkout(templateName: name))
                }
                return .text("No template for '\(name)'. Try 'chest', 'legs', 'back', or 'push day'.")
            }
        ))

        r.register(ToolSchema(
            id: "exercise.exercise_info", name: "exercise_info", service: "exercise",
            description: "User asks ABOUT workouts: what to train, progress, history, recovery. NOT for starting a workout.",
            parameters: [ToolParam("exercise", "string", "Specific exercise name if asking about progress", required: false),
                         ToolParam("query", "string", "What they asked about workouts", required: false)],
            handler: { params in
                if let exercise = params.string("exercise") {
                    let wu = Preferences.weightUnit
                    var lines: [String] = []
                    // Progressive overload
                    if let info = ExerciseService.getProgressiveOverload(exercise: exercise) {
                        lines.append(info.trend)
                        // Session history for context
                        if info.sessions.count >= 2 {
                            let sessionWeights = info.sessions.map { "\(Int(wu.convertFromLbs($0)))" }.joined(separator: " → ")
                            lines.append("Recent 1RM trend (\(wu.displayName)): \(sessionWeights)")
                        }
                    }
                    // Last session data
                    if let w = (try? WorkoutService.lastWeight(for: exercise)) ?? nil {
                        lines.append("Last weight: \(Int(wu.convertFromLbs(w))) \(wu.displayName)")
                    }
                    return .text(lines.isEmpty ? "No data for '\(exercise)' yet." : lines.joined(separator: "\n"))
                }
                // Workout count query: "how many workouts this week"
                let query = (params.string("query") ?? "").lowercased()
                if query.contains("how many") || query.contains("count") || query.contains("how often") {
                    let weekWorkouts = (try? WorkoutService.fetchWorkouts(limit: 7))?.filter {
                        guard let d = DateFormatters.dateOnly.date(from: $0.date) else { return false }
                        return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
                    }.count ?? 0
                    var response = "\(weekWorkouts) workout\(weekWorkouts == 1 ? "" : "s") this week."
                    if let streak = try? WorkoutService.workoutStreak() {
                        response += " Streak: \(streak.current) weeks (best: \(streak.longest))."
                    }
                    return .text(response)
                }
                // General workout info: suggestion + history + streak
                var lines: [String] = [ExerciseService.suggestWorkout()]
                // Recent workouts from HealthKit
                if let hk = DriftPlatform.health, let recent = try? await hk.fetchRecentWorkouts(days: 7), !recent.isEmpty {
                    lines.append("Recent workouts:")
                    for w in recent.prefix(5) {
                        let dur = Int(w.duration / 60)
                        let cal = Int(w.calories)
                        let day = DateFormatters.shortDisplay.string(from: w.date)
                        lines.append("  \(day): \(w.type) — \(dur) min, \(cal) cal")
                    }
                }
                // Streak info
                if let streak = try? WorkoutService.workoutStreak() {
                    lines.append("Streak: \(streak.current) weeks (longest: \(streak.longest))")
                }
                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "exercise.log_activity", name: "log_activity", service: "exercise",
            description: "User says they COMPLETED an activity: 'I did yoga', 'went running', 'just finished pilates'. NOT for starting a new workout.",
            parameters: [
                ToolParam("name", "string", "Activity name like 'yoga', 'running', 'swimming'"),
                ToolParam("duration", "number", "Duration in minutes if mentioned", required: false)
            ],
            needsConfirmation: true,
            preHook: { params in
                guard var name = params.string("name") else { return .invalid(reason: "What activity did you do?") }
                var duration = params.double("duration")

                // Parse duration embedded in name: "30 min yoga" → 30, "yoga"
                let durPattern = #"^(\d+)\s*(?:min(?:ute)?s?)\s+"#
                if duration == nil,
                   let regex = try? NSRegularExpression(pattern: durPattern),
                   let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let numRange = Range(match.range(at: 1), in: name),
                   let matchRange = Range(match.range, in: name) {
                    duration = Double(String(name[numRange]))
                    name = String(name[matchRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }

                // Also: "yoga for 30 min" → "yoga", 30
                let trailingDurPattern = #"\s+(?:for\s+)?(\d+)\s*(?:min(?:ute)?s?)\s*$"#
                if duration == nil,
                   let regex = try? NSRegularExpression(pattern: trailingDurPattern),
                   let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let numRange = Range(match.range(at: 1), in: name),
                   let matchRange = Range(match.range, in: name) {
                    duration = Double(String(name[numRange]))
                    name = String(name[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }

                // Validate duration range
                if let d = duration, (d < 1 || d > 600) {
                    return .invalid(reason: "Duration should be 1-600 minutes.")
                }
                var enriched: [String: String] = ["name": name]
                if let d = duration { enriched["duration"] = "\(Int(d))" }
                return .transform(ToolCallParams(values: enriched))
            },
            handler: { params in
                guard let name = params.string("name"), !name.isEmpty else {
                    return .error("What activity did you do?")
                }
                let display = name.capitalized
                let durText = params.double("duration").map { " (\(Int($0)) min)" } ?? ""
                return .text("Log \(display)\(durText) for today? Say yes to confirm.")
            }
        ))

        // MARK: - Health Data Tools (2 — consolidated from 5)

        r.register(ToolSchema(
            id: "health.sleep_recovery", name: "sleep_recovery", service: "sleep",
            description: "User asks about SLEEP, RECOVERY, HRV, heart rate, tiredness, or whether to rest vs train.",
            parameters: [ToolParam("period", "string", "'today', 'week', or 'last week'", required: false)],
            handler: { params in
                var lines: [String] = []
                let sleep = SleepRecoveryService.getSleep()
                let recovery = SleepRecoveryService.getRecovery()
                let readiness = SleepRecoveryService.getReadiness()
                if !sleep.contains("No ") { lines.append(sleep) }
                if !recovery.contains("No ") { lines.append(recovery) }
                lines.append(readiness)
                // Weekly sleep trend from HealthKit
                let period = params.string("period")?.lowercased() ?? ""
                if period.contains("week") || period.contains("last") {
                    if let hk = DriftPlatform.health, let recent = try? await hk.fetchRecentSleepData(days: 7), !recent.isEmpty {
                        let avgHours = recent.map(\.hours).reduce(0, +) / Double(recent.count)
                        lines.append("Last 7 days avg: \(String(format: "%.1f", avgHours))h sleep (\(recent.count) nights tracked)")
                    }
                }
                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "health.supplements", name: "supplements", service: "supplement",
            description: "User asks about SUPPLEMENTS or VITAMINS: what they took, what's remaining.",
            parameters: [],
            handler: { _ in .text(SupplementService.getStatus()) }
        ))

        r.register(ToolSchema(
            id: "health.add_supplement", name: "add_supplement", service: "supplement",
            description: "User wants to ADD a new supplement to their daily stack. NOT for marking taken.",
            parameters: [ToolParam("name", "string", "Supplement name"),
                         ToolParam("dosage", "string", "Dosage like '5g' or '2000 IU'", required: false)],
            handler: { params in
                guard let name = params.string("name") else { return .error("Which supplement?") }
                return .text(SupplementService.addSupplement(name: name, dosage: params.string("dosage")))
            }
        ))

        r.register(ToolSchema(
            id: "health.mark_supplement", name: "mark_supplement", service: "supplement",
            description: "User TOOK a supplement. Use when they say 'took my creatine', 'had vitamin D', 'took fish oil'.",
            parameters: [ToolParam("name", "string", "Supplement name")],
            handler: { params in
                guard let name = params.string("name") else { return .error("Which supplement?") }
                return .text(SupplementService.markTaken(name: name))
            }
        ))

        r.register(ToolSchema(
            id: "health.log_medication", name: "log_medication", service: "medication",
            description: "User LOGGED a medication dose. Use when they say 'took Ozempic', 'injected semaglutide', 'took my metformin', 'log GLP-1', 'took insulin'. NOT for adding a new medication to their profile (use add_medication for that).",
            parameters: [
                ToolParam("name", "string", "Medication name (e.g. 'Ozempic', 'metformin', 'semaglutide')"),
                ToolParam("dose", "number", "Dose amount (e.g. 0.5, 500, 2)", required: false),
                ToolParam("unit", "string", "Dose unit: mg, mcg, ml, units, IU (default mg)", required: false)
            ],
            handler: { params in
                guard let name = params.string("name") else { return .error("Which medication?") }
                return .text(MedicationService.logMedication(
                    name: name,
                    doseMg: params.double("dose"),
                    doseUnit: params.string("unit")
                ))
            }
        ))

        r.register(ToolSchema(
            id: "health.add_medication", name: "add_medication", service: "medication",
            description: "User wants to ADD a new medication to their profile. Use when they say 'I'm on Wegovy', 'I started Ozempic', 'add metformin 500mg daily', 'I was prescribed atorvastatin'. NOT for logging a dose (use log_medication for that).",
            parameters: [
                ToolParam("name", "string", "Generic medication name (e.g. 'semaglutide', 'metformin')"),
                ToolParam("brand", "string", "Brand name if user mentioned one (e.g. 'Ozempic', 'Wegovy')", required: false),
                ToolParam("dose", "number", "Prescribed dose amount (e.g. 0.5, 500)"),
                ToolParam("unit", "string", "Dose unit: mg, mcg, mL, units, IU (default mg)", required: false),
                ToolParam("schedule", "string", "Schedule: daily | weekly | biweekly | asneeded (default daily)", required: false),
                ToolParam("reminder_time", "string", "HH:mm reminder time if user wants one", required: false),
                ToolParam("reminder_day", "number", "0-6 Sun-Sat for weekly/biweekly schedules", required: false),
                ToolParam("start_date", "string", "YYYY-MM-DD start date (for chart markers)", required: false)
            ],
            preHook: { params in
                guard let name = params.string("name")?.trimmingCharacters(in: .whitespaces),
                      !name.isEmpty else {
                    return .invalid(reason: "What medication should I add?")
                }
                guard params.double("dose") != nil else {
                    return .invalid(reason: "What dose are you on?")
                }
                return .transform(params)
            },
            handler: { params in
                guard let name = params.string("name") else { return .error("Which medication?") }
                guard let dose = params.double("dose"), dose > 0 else {
                    return .error("What dose? e.g. '0.5mg' or '500mg'.")
                }
                let unit = params.string("unit") ?? "mg"
                let schedule = (params.string("schedule") ?? "daily").lowercased()
                let validSchedules: Set<String> = ["daily", "weekly", "biweekly", "asneeded"]
                let resolvedSchedule = validSchedules.contains(schedule) ? schedule : "daily"
                return .text(MedicationService.addMedicationProfile(
                    name: name,
                    brandName: params.string("brand"),
                    doseAmount: dose,
                    doseUnit: unit,
                    scheduleType: resolvedSchedule,
                    reminderTime: params.string("reminder_time"),
                    reminderDay: params.int("reminder_day"),
                    startDate: params.string("start_date")
                ))
            }
        ))

        // NOTE: Glucose, biomarker, and body composition tools are registered but NOT shown
        // in the default 6-tool prompt. They appear when user is on those specific screens.
        // This keeps the main prompt focused for the 1.5B model.

        r.register(ToolSchema(
            id: "health.glucose", name: "glucose", service: "glucose",
            description: "User asks about blood sugar, glucose readings, or spikes.",
            parameters: [],
            handler: { _ in .text(GlucoseService.getReadings() + "\n" + GlucoseService.detectSpikes()) }
        ))

        r.register(ToolSchema(
            id: "health.biomarkers", name: "biomarkers", service: "biomarker",
            description: "User asks about lab results, blood tests, or biomarkers.",
            parameters: [],
            handler: { _ in .text(BiomarkerService.getResults()) }
        ))

        r.register(ToolSchema(
            id: "health.body_comp", name: "body_comp", service: "bodycomp",
            description: "User asks about body composition, body fat %, BMI, lean mass, DEXA scans, or muscle mass.",
            parameters: [],
            handler: { _ in .text(AIContextBuilder.dexaContext()) }
        ))

        r.register(ToolSchema(
            id: "health.log_body_comp", name: "log_body_comp", service: "bodycomp",
            description: "User LOGS body composition data: body fat %, BMI, or weight from a smart scale.",
            parameters: [ToolParam("body_fat", "number", "Body fat percentage", required: false),
                         ToolParam("bmi", "number", "BMI value", required: false)],
            handler: { params in
                let bf = params.double("body_fat")
                let bmi = params.double("bmi")
                guard bf != nil || bmi != nil else { return .error("Provide body fat % or BMI.") }
                var entry = BodyComposition(date: DateFormatters.todayString, bodyFatPct: bf, bmi: bmi,
                                             source: "manual", createdAt: DateFormatters.iso8601.string(from: Date()))
                try? AppDatabase.shared.saveBodyComposition(&entry)
                var parts: [String] = []
                if let bf { parts.append("body fat \(String(format: "%.1f", bf))%") }
                if let bmi { parts.append("BMI \(String(format: "%.1f", bmi))") }
                return .text("Logged \(parts.joined(separator: ", ")).")
            }
        ))
        // MARK: - Navigation Tool

        r.register(ToolSchema(
            id: "nav.navigate_to", name: "navigate_to", service: "nav",
            description: "Navigate to a screen. Use when user says 'show me', 'go to', 'open', 'switch to'.",
            parameters: [ToolParam("screen", "string", "Screen: dashboard, weight, food, exercise, supplements, glucose, biomarkers, settings")],
            handler: { params in
                guard let screen = params.string("screen")?.lowercased()
                    .trimmingCharacters(in: .whitespaces) else {
                    return .error("Which screen? Try: dashboard, weight, food, exercise, supplements, glucose, biomarkers, or settings.")
                }
                let tabMap: [String: (tab: Int, label: String)] = [
                    "dashboard": (0, "Dashboard"), "home": (0, "Dashboard"),
                    "weight": (1, "Weight"), "weight chart": (1, "Weight"), "weight trend": (1, "Weight"), "scale": (1, "Weight"),
                    "food": (2, "Food"), "food log": (2, "Food"), "diary": (2, "Food"), "nutrition": (2, "Food"), "meals": (2, "Food"),
                    "exercise": (3, "Exercise"), "workout": (3, "Exercise"), "workouts": (3, "Exercise"), "gym": (3, "Exercise"), "training": (3, "Exercise"),
                    "supplements": (4, "Supplements"), "vitamins": (4, "Supplements"),
                    "glucose": (4, "Glucose"), "blood sugar": (4, "Glucose"),
                    "biomarkers": (4, "Biomarkers"), "labs": (4, "Biomarkers"), "blood work": (4, "Biomarkers"),
                    "settings": (4, "Settings"), "more": (4, "Settings"), "preferences": (4, "Settings"),
                ]
                guard let entry = tabMap[screen] else {
                    return .text("I can navigate to: Dashboard, Weight, Food, Exercise, Supplements, Glucose, Biomarkers, or Settings.")
                }
                return .action(.navigate(tab: entry.tab))
            }
        ))

        // MARK: - Insights Tools

        // Cross-domain correlation tool — answers "did I lose weight on
        // workout days" style questions by correlating two on-device
        // metrics over a window. Read-only. #317.
        CrossDomainInsightTool.syncRegistration(registry: r)

        // Web tools — DuckDuckGo search (no API key) + URL fetch. The coach's
        // reach beyond on-device data; only fire when the model picks them, and
        // they are an explicit cloud touch-point. #coach-agent-loop.
        WebSearchTool.syncRegistration(registry: r)
        FetchURLTool.syncRegistration(registry: r)

        // Cross-domain pattern detector — proactively scans every metric
        // pair and surfaces the 1-3 strongest signals. Different from
        // cross_domain_insight: open-ended discovery vs. specific question. #739.
        CrossDomainPatternDetectorTool.syncRegistration(registry: r)

        // Weight trend prediction — "when will I reach my goal weight?"
        // OLS regression on last 30 days → projected date + R² confidence. #402.
        WeightTrendPredictionTool.syncRegistration(registry: r)

        // Medication history — last dose time, typical timing, recent pattern.
        MedicationInfoTool.syncRegistration(registry: r)

        // GLP-1 insight — adherence streak, missed doses, weight delta since first dose.
        GLP1InsightTool.syncRegistration(registry: r)

        // Supplement adherence — streak, adherence %, last missed date. #417.
        SupplementInsightTool.syncRegistration(registry: r)

        // Meal timing patterns — avg meal times, late-night eating %. #418.
        FoodTimingInsightTool.syncRegistration(registry: r)

        // Sleep-food correlation — does late eating hurt sleep? #426.
        SleepFoodCorrelationTool.syncRegistration(registry: r)

        // Exercise volume by muscle group — training volume, undertrained groups. #335.
        ExerciseVolumeSummaryTool.syncRegistration(registry: r)

        // Progressive overload plateau detection — which lifts are stalling + suggestions. #633.
        ProgressiveOverloadCheckTool.syncRegistration(registry: r)

        // Glucose-food correlation — which foods spike glucose? ±2h window analysis. #324.
        GlucoseFoodCorrelationTool.syncRegistration(registry: r)

        // Glucose spike analysis — peak-based spike detection per meal, >30 mg/dL threshold. #631.
        GlucoseSpikeAnalysisTool.syncRegistration(registry: r)

        // Cycle × biomarker correlation — does iron / D / ferritin shift across cycle phases? #689.
        CycleBiomarkerInsightTool.syncRegistration(registry: r)

        // Protein consistency vs recovery — does day-to-day protein variance track HRV/sleep? #730.
        ProteinConsistencyVsRecoveryTool.syncRegistration(registry: r)

        // PhotoLog tool is registered separately by the iOS Drift app
        // after this base registration runs (it depends on iOS-only
        // CloudVision / Keychain).
    }
}
