import SwiftUI
import DriftCore

/// Shows muscle groups with recovery status colors and contextual coaching.
struct BodyMapView: View {
    var onStartTemplate: ((WorkoutTemplate) -> Void)? = nil
    @State private var muscleStatus: [String: MuscleStatus] = [:]
    @State private var daysSince: [String: Int] = [:]
    @State private var lastTrainedDate: [String: String] = [:] // group → "Mar 29"
    @State private var recentExercises: [String: [String]] = [:] // group → exercise names
    @State private var weeklySetCounts: [String: Int] = [:]
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
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            } else {
                                Text("\u{2014}").font(.caption2).foregroundStyle(.quaternary)
                            }
                            if let count = weeklySetCounts[group], count > 0 {
                                Text("\(count) sets")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(status.color.opacity(0.08 + volumeIntensity(for: group) * 0.22), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if selectedGroup == group {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(status.color, lineWidth: 1.5)
                            }
                        }
                    }.buttonStyle(.plain)
                    .accessibilityLabel("\(group): \(status == .untrained ? "not trained recently" : status == .recovered ? "recovered" : status == .moderate ? "moderately recovered" : "still recovering")\(daysSince[group].map { $0 == 0 ? ", trained today" : ", \($0) days ago" } ?? "")")
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
        let matchingTemplates = templates.filter { t in
            t.name.lowercased().contains(group.lowercased()) ||
            t.exercises.filter { !$0.isWarmup }.contains { ExerciseDatabase.bodyPart(for: $0.name) == group }
        }

        return VStack(alignment: .leading, spacing: 6) {
            if status == .untrained {
                // Not trained recently — encourage with suggestions
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.secondary)
                    Text("You haven't trained \(group.lowercased()) in over a week.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !matchingTemplates.isEmpty {
                    ForEach(matchingTemplates) { t in quickStartButton(template: t) }
                } else {
                    let standards = standardExercises(for: group)
                    if !standards.isEmpty {
                        Text("Try: \(standards.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            } else {
                // Trained recently — show last session info
                HStack(spacing: 6) {
                    let dateStr = lastTrainedDate[group] ?? dayText(group)
                    Text("Last trained: \(dateStr)").font(.caption.weight(.medium)).foregroundStyle(status.color)
                }
                if !recent.isEmpty {
                    Text(recent.prefix(4).joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
                ForEach(matchingTemplates) { t in quickStartButton(template: t) }
            }
        }
    }

    private func quickStartButton(template: WorkoutTemplate) -> some View {
        Button {
            onStartTemplate?(template)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.circle.fill").font(.caption)
                Text("Start \(template.name)").font(.caption2.weight(.medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.top, 2)
        }.buttonStyle(.plain)
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

    // MARK: - Volume Intensity

    /// Normalizes weekly set count for this group against the max across all groups (0.0–1.0).
    private func volumeIntensity(for group: String) -> Double {
        let maxSets = weeklySetCounts.values.max() ?? 1
        guard maxSets > 0, let count = weeklySetCounts[group] else { return 0 }
        return Double(count) / Double(maxSets)
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
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 500) else { return }

        var lastWorked: [String: Date] = [:]
        var exercisesByGroup: [String: [String]] = [:]
        var setCounts: [String: Int] = [:]

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
                var groupExercises = exercisesByGroup[group, default: []]
                if !groupExercises.contains(s.exerciseName) {
                    groupExercises.append(s.exerciseName)
                }
                exercisesByGroup[group] = groupExercises
                // Count sets in the past 7 days for weekly volume display
                if daysDiff <= 7 { setCounts[group, default: 0] += 1 }
            }
        }

        weeklySetCounts = setCounts
        recentExercises = exercisesByGroup

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d"

        for group in Self.muscleGroups {
            if let d = lastWorked[group] { lastTrainedDate[group] = dateFmt.string(from: d) }
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
