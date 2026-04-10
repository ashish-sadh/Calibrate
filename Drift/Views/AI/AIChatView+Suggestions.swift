import SwiftUI

// MARK: - Smart Suggestions, Page Insight, Fallback Responses

extension AIChatView {

    var suggestionsRow: some View {
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

    var smartSuggestions: [String] {
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

    var pageInsight: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning!" : hour < 17 ? "Good afternoon!" : "Good evening!"
        let screen = screenTracker.currentScreen

        switch screen {
        case .weight, .goal:
            if WeightTrendService.shared.latestWeightKg != nil {
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

    // MARK: - Fallback Responses

    /// Determine meal type based on time of day.
    var currentMealType: MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<11: return .breakfast
        case ..<15: return .lunch
        case ..<21: return .dinner
        default: return .snack
        }
    }

    /// Data-aware fallback when LLM fails. Uses actual user data to suggest something useful.
    func fallbackResponse(for screen: AIScreen) -> String {
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
}
