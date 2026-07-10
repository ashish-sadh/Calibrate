import Foundation
import DriftCore

/// Generates a personalized weekly routine via the coach cloud model (Qwen on
/// Nebius) from the interview's TrainingProfile. Prompt building, decoding,
/// grounding, and the offline fallback live in DriftCore's
/// `RoutinePlanGenerator` (Tier-0 tested); this wraps only the model call.
/// Mirrors `NebiusExerciseLogger` / `MealTextLogger`. Returns nil when the
/// cloud isn't configured/reachable or nothing survives grounding — the
/// caller then uses `RoutinePlanGenerator.fallbackPlan`.
@MainActor
enum NebiusRoutineGenerator {

    static let systemPrompt = """
    You are a careful strength coach designing safe, balanced weekly routines.
    Respond with ONLY the requested JSON — no prose, no markdown fences.
    Never invent exercise names: copy every name EXACTLY from the provided list.
    Respect every stated constraint (injury, postpartum, age) by picking gentler options for the affected area.
    """

    static func generate(profile: TrainingProfile, goalLine: String?) async -> [RoutinePlanGenerator.PlannedDay]? {
        guard AIBackendCoordinator.hasCoachCloud else { return nil }
        AIBackendCoordinator.installCoachBackend()
        let pool = RoutinePlanGenerator.candidatePool(profile: profile)
        let prompt = RoutinePlanGenerator.buildPrompt(profile: profile, goalLine: goalLine, pool: pool)
        let raw = await LocalAIService.shared.respondDirect(systemPrompt: systemPrompt, message: prompt)
        guard let days = RoutinePlanGenerator.decode(raw) else { return nil }
        return RoutinePlanGenerator.grounded(days)
    }
}
