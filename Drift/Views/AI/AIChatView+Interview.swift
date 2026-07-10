import SwiftUI
import DriftCore

// MARK: - Coach Interview ("set me up" → TrainingProfile → personalized routine)
//
// Multi-turn Q&A modeled on the split-builder flow: a persisted
// `ConversationState.Phase.interviewing(step:)` drives one question per turn,
// answers save into TrainingProfile as they arrive (so a half-finished
// interview survives relaunch and is never re-asked from scratch), and the
// finale generates a weekly routine via the Nebius Qwen coach model —
// grounded against the equipment-filtered catalog — with a deterministic
// offline fallback. Design notes: exercise-UX session 2026-07-09/10
// (question budget ≤7, one question per message, chips for enumerable
// answers, draft skeleton before the last questions, never a toll booth).

extension AIChatViewModel {

    private enum InterviewStep {
        static let experience = 0
        static let location = 1
        static let equipment = 2
        static let schedule = 3
        static let constraints = 4
        static let clearance = 5
        static let priority = 6
    }

    /// Phase 6 trigger: "set me up", "build me a plan/routine", "training plan".
    func handleInterviewTrigger(_ lower: String) -> Bool {
        if case .interviewing = convState.phase { return false }
        let phrases = ["set me up", "personal trainer", "training plan", "workout plan",
                       "build me a plan", "make me a plan", "create a plan",
                       "build me a routine", "make me a routine", "create a routine",
                       "plan my training", "plan my workouts"]
        guard phrases.contains(where: { lower.contains($0) }) else { return false }

        var greet = "Let's build your plan — a few quick questions and I'll put a week together."
        if let goal = WeightGoal.load(), let current = WeightTrendService.shared.latestWeightKg {
            let direction = goal.targetWeightKg < current ? "weight-loss" : "muscle-gain"
            greet = "Let's build your plan around your \(direction) goal — a few quick questions."
        }
        messages.append(ChatMessage(role: .assistant,
            text: greet + "\n\n" + interviewQuestion(InterviewStep.experience)))
        convState.phase = .interviewing(step: InterviewStep.experience)
        quickReplies = interviewChips(InterviewStep.experience)
        return true
    }

    /// Mid-flow handler — first in handleMultiTurnState so bare answers
    /// ("intermediate", "3 days") resolve against the current question.
    func handlePendingInterview(_ lower: String, originalText: String) -> Bool {
        guard case .interviewing(let step) = convState.phase else { return false }

        // Escape hatch — answers so far stay saved on the profile.
        let exits = ["cancel", "stop", "quit", "exit", "nevermind", "never mind", "not now"]
        if exits.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
            convState.phase = .idle
            quickReplies = []
            messages.append(ChatMessage(role: .assistant,
                text: "No problem — what you told me is saved. Say \"set me up\" to pick it back up."))
            return true
        }

        var profile = TrainingProfile.load() ?? TrainingProfile()
        var ack: String? = nil
        var next = step + 1

        switch step {
        case InterviewStep.experience:
            if lower.contains("begin") || lower.contains("new") || lower.contains("just start") || lower.contains("never") {
                profile.experience = .beginner
            } else if lower.contains("advanc") || lower.contains("years") {
                profile.experience = .advanced
            } else if lower.contains("inter") || lower.contains("while") || lower.contains("some") {
                profile.experience = .intermediate
            } else {
                return reaskInterview(step)
            }
            next = InterviewStep.location

        case InterviewStep.location:
            if lower.contains("both") {
                profile.location = .both
                next = InterviewStep.equipment
            } else if lower.contains("no equipment") || lower.contains("nothing") || lower.contains("bodyweight") {
                profile.location = .home
                profile.equipment = []
                next = InterviewStep.schedule
            } else if lower.contains("home") {
                profile.location = .home
                next = InterviewStep.equipment
            } else if lower.contains("gym") {
                profile.location = .gym
                profile.equipment = []
                next = InterviewStep.schedule
            } else {
                return reaskInterview(step)
            }

        case InterviewStep.equipment:
            let noneWords = ["none", "nothing", "no", "nope", "just my body"]
            let slugs = TrainingProfile.normalizeEquipment(lower)
            if noneWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }) {
                profile.equipment = []
            } else if slugs.isEmpty {
                messages.append(ChatMessage(role: .assistant,
                    text: "Didn't catch any equipment I know — try things like dumbbells, bands, kettlebell, barbell, or say \"none\"."))
                return true
            } else {
                profile.equipment = slugs
                ack = "Got it — \(slugs.joined(separator: ", "))."
            }
            next = InterviewStep.schedule

        case InterviewStep.schedule:
            let numbers = lower.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard let days = numbers.first(where: { (1...7).contains($0) }) else {
                return reaskInterview(step)
            }
            profile.daysPerWeek = days
            if lower.contains("hour") {
                profile.sessionMinutes = lower.contains("half") ? 90 : 60
            } else {
                profile.sessionMinutes = numbers.first(where: { (15...180).contains($0) }) ?? 45
            }
            // Draft-first: show the week's shape before the last questions.
            let skeleton = RoutinePlanGenerator.fallbackPlan(profile: profile)
                .map(\.name).joined(separator: " / ")
            if !skeleton.isEmpty {
                ack = "Sketching a \(days)-day week — \(skeleton). Two more questions."
            }
            next = InterviewStep.constraints

        case InterviewStep.constraints:
            let noneWords = ["nothing", "none", "no", "nope", "all good", "nah"]
            if noneWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }) {
                profile.constraints = []
                profile.medicalClearance = nil
                next = InterviewStep.priority
            } else {
                var text = originalText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                for prefix in ["i have ", "i've got ", "ive got ", "i am ", "i'm ", "my "] where text.hasPrefix(prefix) {
                    text = String(text.dropFirst(prefix.count))
                    break
                }
                profile.constraints = [text]
                ack = "Noted — I'll pick exercises that work with that."
                next = interviewNeedsClearance(text) ? InterviewStep.clearance : InterviewStep.priority
            }

        case InterviewStep.clearance:
            if lower.contains("yes") || lower.contains("yep") || lower.contains("cleared") || lower.contains("yeah") {
                profile.medicalClearance = true
            } else {
                profile.medicalClearance = false
                ack = "No problem — I'll keep everything gentle. Please check with your doctor before ramping up."
            }
            next = InterviewStep.priority

        case InterviewStep.priority:
            let noneWords = ["balanced", "nothing", "none", "no", "nope", "all"]
            if noneWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
                profile.priority = nil
            } else {
                profile.priority = lower.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            profile.updatedAt = DateFormatters.iso8601.string(from: Date())
            profile.save()
            convState.phase = .idle
            quickReplies = []
            generateInterviewRoutine(from: profile)
            return true

        default:
            convState.phase = .idle
            return false
        }

        profile.updatedAt = DateFormatters.iso8601.string(from: Date())
        profile.save()
        convState.phase = .interviewing(step: next)
        let text = [ack, interviewQuestion(next)].compactMap { $0 }.joined(separator: "\n\n")
        messages.append(ChatMessage(role: .assistant, text: text))
        quickReplies = interviewChips(next)
        return true
    }

    // MARK: - Questions & chips

    private func interviewQuestion(_ step: Int) -> String {
        switch step {
        case InterviewStep.experience: "How experienced are you with training?"
        case InterviewStep.location: "Where will you train?"
        case InterviewStep.equipment: "What equipment do you have there?"
        case InterviewStep.schedule: "How many days a week — and roughly how long per session?"
        case InterviewStep.constraints: "Anything I should work around — injuries, postpartum, health conditions?"
        case InterviewStep.clearance: "Quick check: has your doctor okayed light exercise?"
        default: "Last one — any muscle group or activity you want to prioritize?"
        }
    }

    private func interviewChips(_ step: Int) -> [String] {
        switch step {
        case InterviewStep.experience: ["Beginner", "Intermediate", "Advanced"]
        case InterviewStep.location: ["Full gym", "Home — no equipment", "Home with equipment", "Both"]
        case InterviewStep.equipment: ["Dumbbells", "Dumbbells + bands", "None"]
        case InterviewStep.schedule: ["3 days · 45 min", "4 days · 60 min", "5 days · 60 min"]
        case InterviewStep.constraints: ["Nothing", "Knee", "Lower back", "Shoulder"]
        case InterviewStep.clearance: ["Yes", "Not yet"]
        default: ["Balanced", "Chest", "Back", "Legs"]
        }
    }

    private func reaskInterview(_ step: Int) -> Bool {
        messages.append(ChatMessage(role: .assistant,
            text: "Didn't catch that — tap an option below, or say \"cancel\" to stop.\n\n" + interviewQuestion(step)))
        quickReplies = interviewChips(step)
        return true
    }

    private func interviewNeedsClearance(_ text: String) -> Bool {
        // Bare body parts count — the constraint chips ("Knee", "Lower back")
        // mean an issue there, not a preference.
        ["postpartum", "pregnan", "c-section", "csection", "surgery", "injur",
         "rehab", "pain", "hernia", "cardiac", "heart", "fracture",
         "knee", "back", "shoulder", "wrist", "ankle", "hip", "elbow", "neck"].contains { text.contains($0) }
    }

    // MARK: - Generation

    private func generateInterviewRoutine(from profile: TrainingProfile) {
        messages.append(ChatMessage(role: .assistant, text: "Building your week..."))
        let statusIdx = messages.count - 1
        Task {
            var goalLine: String? = nil
            if let goal = WeightGoal.load(), let current = WeightTrendService.shared.latestWeightKg {
                goalLine = goal.targetWeightKg < current
                    ? "fat loss — preserve muscle" : "muscle gain"
            }
            var plan = await NebiusRoutineGenerator.generate(profile: profile, goalLine: goalLine)
            let fromCloud = plan?.isEmpty == false
            if plan?.isEmpty != false {
                plan = RoutinePlanGenerator.fallbackPlan(profile: profile)
            }
            guard statusIdx < messages.count else { return }
            guard let days = plan, !days.isEmpty else {
                messages[statusIdx] = ChatMessage(role: .assistant,
                    text: "I couldn't put a plan together right now — say \"set me up\" to try again.")
                return
            }

            var lines: [String] = []
            for day in days {
                let templateExercises = day.exercises.map { ex in
                    var notes = "\(ex.reps) reps"
                    if let tip = ExerciseService.formTip(for: ex.name) { notes += " | \(tip)" }
                    return WorkoutTemplate.TemplateExercise(name: ex.name, sets: ex.sets, notes: notes)
                }
                if let json = try? JSONEncoder().encode(templateExercises),
                   let jsonStr = String(data: json, encoding: .utf8) {
                    var template = WorkoutTemplate(
                        name: "Plan — \(day.name)",
                        exercisesJson: jsonStr,
                        createdAt: DateFormatters.iso8601.string(from: Date()))
                    try? WorkoutService.saveTemplate(&template)
                }
                lines.append("**\(day.name)** — " + day.exercises
                    .map { "\($0.name) \($0.sets)×\($0.reps)" }.joined(separator: ", "))
            }

            var summary = "Here's your \(days.count)-day week:\n" + lines.joined(separator: "\n")
            summary += "\n\nSaved to your templates. Say \"start \(days[0].name.lowercased())\" when you're ready, or \"set me up\" anytime to rebuild."
            if !fromCloud {
                summary += "\n_(Built offline from your history — run \"set me up\" again when online for a smarter pass.)_"
            }
            messages[statusIdx] = ChatMessage(role: .assistant, text: summary)
            quickReplies = ["Start \(days[0].name)"]
        }
    }
}
