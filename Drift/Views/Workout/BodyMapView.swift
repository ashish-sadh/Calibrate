import SwiftUI

/// Shows muscle groups with recovery status colors.
/// Green = recovered (worked 2-7 days ago)
/// Orange = moderately recovered (worked 1-2 days ago)
/// Red = needs recovery (worked today/yesterday)
/// Gray = not trained recently (>7 days)
struct BodyMapView: View {
    @State private var muscleStatus: [String: MuscleStatus] = [:]
    @State private var selectedGroup: String?

    enum MuscleStatus: Sendable {
        case recovered    // 2-7 days ago (green)
        case moderate     // 1-2 days ago (orange)
        case recovering   // today/yesterday (red)
        case untrained    // >7 days (gray)

        var color: Color {
            switch self {
            case .recovered: Theme.deficit
            case .moderate: Theme.stepsOrange
            case .recovering: Theme.surplus
            case .untrained: .gray.opacity(0.4)
            }
        }

        var label: String {
            switch self {
            case .recovered: "Recovered"
            case .moderate: "Moderate"
            case .recovering: "Recovering"
            case .untrained: "Not trained"
            }
        }
    }

    static let muscleGroups = ["Chest", "Back", "Shoulders", "Arms", "Core", "Legs"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Muscle Recovery").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            // Body grid (2 columns)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.muscleGroups, id: \.self) { group in
                    let status = muscleStatus[group] ?? .untrained
                    Button {
                        selectedGroup = group
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: iconFor(group))
                                .font(.title3)
                                .foregroundStyle(status.color)
                            Text(group)
                                .font(.caption2.weight(.semibold))
                            Text(status.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if selectedGroup == group {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(status.color, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Legend
            HStack(spacing: 10) {
                legendDot("Recovered", color: Theme.deficit)
                legendDot("Moderate", color: Theme.stepsOrange)
                legendDot("Recovering", color: Theme.surplus)
                legendDot("Untrained", color: .gray.opacity(0.4))
            }

            // Exercise suggestions for selected group
            if let group = selectedGroup {
                exerciseSuggestions(for: group)
            }
        }
        .card()
        .onAppear { loadMuscleStatus() }
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

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

    private func exerciseSuggestions(for group: String) -> some View {
        let exercises = ExerciseDatabase.byBodyPart(group).filter { ["beginner", "intermediate"].contains($0.level) && $0.equipment != "other" }.prefix(5).map(\.name)
        let status = muscleStatus[group] ?? .untrained

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Exercises for \(group)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                // Recovery countdown
                if status == .recovering {
                    Text("~1-2 days to recover").font(.caption2).foregroundStyle(Theme.surplus)
                } else if status == .moderate {
                    Text("~1 day to recover").font(.caption2).foregroundStyle(Theme.stepsOrange)
                } else if status == .recovered {
                    Text("Ready to train").font(.caption2).foregroundStyle(Theme.deficit)
                } else {
                    Text("Not trained recently").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ForEach(exercises, id: \.self) { ex in
                Text("• \(ex)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func loadMuscleStatus() {
        let cal = Calendar.current
        let today = Date()

        // Get all workout sets from last 7 days
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 50) else { return }

        var lastWorked: [String: Date] = [:]

        for w in workouts {
            guard let wDate = DateFormatters.dateOnly.date(from: String(w.date.prefix(10))),
                  let wid = w.id else { continue }
            let daysDiff = cal.dateComponents([.day], from: wDate, to: today).day ?? 999
            guard daysDiff <= 7 else { continue }

            let sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? []
            for s in sets {
                let group = guessMuscleGroup(s.exerciseName)
                if let existing = lastWorked[group] {
                    if wDate > existing { lastWorked[group] = wDate }
                } else {
                    lastWorked[group] = wDate
                }
            }
        }

        for group in Self.muscleGroups {
            if let lastDate = lastWorked[group] {
                let days = cal.dateComponents([.day], from: lastDate, to: today).day ?? 999
                if days <= 1 { muscleStatus[group] = .recovering }
                else if days <= 2 { muscleStatus[group] = .moderate }
                else if days <= 7 { muscleStatus[group] = .recovered }
                else { muscleStatus[group] = .untrained }
            } else {
                muscleStatus[group] = .untrained
            }
        }
    }

    private func guessMuscleGroup(_ name: String) -> String {
        ExerciseDatabase.bodyPart(for: name)
    }
}
