import SwiftUI

/// Shows muscle groups with recovery status colors and contextual coaching.
struct BodyMapView: View {
    @State private var muscleStatus: [String: MuscleStatus] = [:]
    @State private var daysSince: [String: Int] = [:]
    @State private var recentExercises: [String: [String]] = [:] // group → exercise names
    @State private var selectedGroup: String?

    enum MuscleStatus: Sendable {
        case recovered, moderate, recovering, untrained

        var color: Color {
            switch self {
            case .recovered: Theme.deficit
            case .moderate: Theme.stepsOrange
            case .recovering: Theme.surplus
            case .untrained: .gray.opacity(0.4)
            }
        }
    }

    static let muscleGroups = ["Chest", "Back", "Shoulders", "Arms", "Core", "Legs"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Muscle Recovery").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.muscleGroups, id: \.self) { group in
                    let status = muscleStatus[group] ?? .untrained
                    Button { selectedGroup = selectedGroup == group ? nil : group } label: {
                        VStack(spacing: 3) {
                            Image(systemName: iconFor(group)).font(.title3).foregroundStyle(status.color)
                            Text(group).font(.caption2.weight(.semibold))
                            if let days = daysSince[group] {
                                Text(days == 0 ? "Today" : "\(days)d ago")
                                    .font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary)
                            } else {
                                Text("\u{2014}").font(.system(size: 8)).foregroundStyle(.quaternary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if selectedGroup == group {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(status.color, lineWidth: 1.5)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }

            // Contextual panel for selected group
            if let group = selectedGroup {
                groupPanel(group)
            }
        }
        .card()
        .onAppear { loadMuscleStatus() }
    }

    // MARK: - Contextual Group Panel

    private func groupPanel(_ group: String) -> some View {
        let status = muscleStatus[group] ?? .untrained
        let recent = recentExercises[group] ?? []
        let templates = (try? WorkoutService.fetchTemplates()) ?? []
        let matchingTemplate = templates.first { t in
            t.name.lowercased().contains(group.lowercased()) ||
            t.exercises.filter { !$0.isWarmup }.contains { ExerciseDatabase.bodyPart(for: $0.name) == group }
        }

        return VStack(alignment: .leading, spacing: 8) {
            // Status message
            switch status {
            case .recovering:
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill").font(.caption).foregroundStyle(Theme.surplus)
                    Text("You trained \(group.lowercased()) \(dayText(group)). Give it 1-2 days to recover.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !recent.isEmpty {
                    Text("Last session: \(recent.prefix(3).joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

            case .moderate:
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill").font(.caption).foregroundStyle(Theme.stepsOrange)
                    Text("\(group) is almost recovered. Light work is okay, heavy lifting tomorrow.")
                        .font(.caption).foregroundStyle(.secondary)
                }

            case .recovered:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.deficit)
                    Text("\(group) is fully recovered and ready to train!")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let t = matchingTemplate {
                    quickStartButton(template: t)
                }

            case .untrained:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.secondary)
                    Text("You haven't trained \(group.lowercased()) in over a week.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let t = matchingTemplate {
                    quickStartButton(template: t)
                } else {
                    // Show standard exercises for this group
                    let standards = standardExercises(for: group)
                    if !standards.isEmpty {
                        Text("Try: \(standards.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func quickStartButton(template: WorkoutTemplate) -> some View {
        // This is just informational - actual navigation handled by parent
        HStack(spacing: 4) {
            Image(systemName: "play.circle.fill").font(.caption).foregroundStyle(Theme.accent)
            Text("Template: \(template.name)").font(.caption2.weight(.medium)).foregroundStyle(Theme.accent)
        }
        .padding(.top, 2)
    }

    private func dayText(_ group: String) -> String {
        guard let days = daysSince[group] else { return "recently" }
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    /// Standard dumbbell-focused exercises for each body part
    private func standardExercises(for group: String) -> [String] {
        switch group {
        case "Chest": return ["Dumbbell Bench Press", "Incline DB Press", "Dips"]
        case "Back": return ["Lat Pulldown", "Dumbbell Row", "Face Pull"]
        case "Shoulders": return ["Shoulder Press", "Lateral Raise", "Rear Delt Fly"]
        case "Arms": return ["Bicep Curl", "Hammer Curls", "Tricep Pushdown"]
        case "Core": return ["Leg Raise", "Plank", "Cable Crunch"]
        case "Legs": return ["Squat", "Romanian Deadlift", "Leg Press"]
        default: return []
        }
    }

    // MARK: - Icons

    private func iconFor(_ group: String) -> String {
        switch group {
        case "Chest": "figure.arms.open"
        case "Back": "figure.walk"
        case "Shoulders": "figure.flexibility"
        case "Arms": "figure.boxing"
        case "Core": "figure.core.training"
        case "Legs": "figure.run"
        default: "figure.stand"
        }
    }

    // MARK: - Data Loading

    private func loadMuscleStatus() {
        let cal = Calendar.current
        let today = Date()
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 50) else { return }

        var lastWorked: [String: Date] = [:]
        var exercisesByGroup: [String: [String]] = [:]

        for w in workouts {
            guard let wDate = DateFormatters.dateOnly.date(from: String(w.date.prefix(10))),
                  let wid = w.id else { continue }
            let daysDiff = cal.dateComponents([.day], from: wDate, to: today).day ?? 999
            guard daysDiff <= 14 else { continue }

            let sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? []
            for s in sets {
                let group = ExerciseDatabase.bodyPart(for: s.exerciseName)
                if let existing = lastWorked[group] {
                    if wDate > existing { lastWorked[group] = wDate }
                } else {
                    lastWorked[group] = wDate
                }
                // Track recent exercises per group
                if exercisesByGroup[group] == nil { exercisesByGroup[group] = [] }
                if !exercisesByGroup[group]!.contains(s.exerciseName) {
                    exercisesByGroup[group]!.append(s.exerciseName)
                }
            }
        }

        recentExercises = exercisesByGroup

        for group in Self.muscleGroups {
            if let lastDate = lastWorked[group] {
                let days = cal.dateComponents([.day], from: lastDate, to: today).day ?? 999
                daysSince[group] = days
                if days <= 1 { muscleStatus[group] = .recovering }
                else if days <= 2 { muscleStatus[group] = .moderate }
                else if days <= 7 { muscleStatus[group] = .recovered }
                else { muscleStatus[group] = .untrained }
            } else {
                muscleStatus[group] = .untrained
            }
        }
    }
}
