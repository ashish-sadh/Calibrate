import Foundation

/// All screens the AI can be aware of.
public enum AIScreen: String, Sendable {
    case dashboard, weight, food, exercise
    case bodyRhythm, cycle, supplements, bodyComposition, glucose, biomarkers
    case goal, settings, algorithm

    /// Service domain owning this screen — used to bias tool ranking and tool registration.
    /// Single source of truth shared by `ToolRegistry.toolsForScreen` and any screen→service routing.
    public var serviceName: String? {
        switch self {
        case .food: return "food"
        case .weight, .goal: return "weight"
        case .exercise: return "exercise"
        case .bodyRhythm: return "sleep"
        case .supplements: return "supplement"
        case .glucose: return "glucose"
        case .biomarkers: return "biomarker"
        case .bodyComposition: return "body_comp"
        default: return nil
        }
    }

    /// Tool names that should appear by default on this screen when keyword
    /// scoring produces no strong matches. Single source of truth shared by
    /// `ToolRanker.rank` fallback padding.
    public var defaultTools: [String] {
        switch self {
        case .food:            return ["log_food", "food_info"]
        case .weight, .goal:   return ["weight_info", "log_weight"]
        case .exercise:        return ["start_workout", "exercise_info"]
        case .bodyRhythm:      return ["sleep_recovery"]
        case .supplements:     return ["supplements", "mark_supplement"]
        case .glucose:         return ["glucose"]
        case .biomarkers:      return ["biomarkers"]
        case .bodyComposition: return ["body_comp"]
        default:               return ["food_info", "weight_info"]
        }
    }
}
