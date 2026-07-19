import SwiftUI
import DriftCore

/// Shows muscle groups with recovery status colors and contextual coaching.
/// Single-source for iOS and Android (#1064). Skip constraint: `@State` must
/// not be `private`.
struct BodyMapView: View {
    var onStartTemplate: ((WorkoutTemplate) -> Void)? = nil
    @State var muscleStatus: [String: MuscleStatus] = [:]
    @State var daysSince: [String: Int] = [:]
    @State var lastTrainedDate: [String: String] = [:] // group → "Mar 29"
    @State var recentExercises: [String: [String]] = [:] // group → exercise names
    @State var weeklySetCounts: [String: Int] = [:]
    @State var selectedGroup: String?
    // Soreness check-in — one quiet question/day; answers tune the
    // per-group recovery estimate that drives the coloring above.
    @State var sorenessState = MuscleSoreness.loadState()
    @State var sorenessQuestion: String?
    #if os(Android)
    // Group-panel templates ride the status snapshot — a sync fetch in the
    // panel builder would cross JNI on every body evaluation (#1074).
    @State var cachedTemplates: [WorkoutTemplate] = []
    #endif

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

    /// UI group → library body-model slugs (#929). Drives the recovery
    /// coloring on the anatomical figures.
    static let groupSlugs: [String: [String]] = [
        "Chest": ["chest"],
        "Back": ["upper-back", "lower-back", "trapezius"],
        "Shoulders": ["deltoids"],
        "Arms": ["biceps", "triceps", "forearm"],
        "Core": ["abs", "obliques"],
        "Legs": ["quadriceps", "hamstring", "gluteal", "calves", "adductors"],
    ]

    /// Recovery status painted onto the body model. Untrained groups keep
    /// the neutral base fill so the figure reads calm, not alarming.
    private var recoverySlugColors: [String: Color] {
        var colors: [String: Color] = [:]
        for group in Self.muscleGroups {
            let status = muscleStatus[group] ?? .untrained
            guard status != .untrained else { continue }
            let intensity = 0.45 + volumeIntensity(for: group) * 0.45
            for slug in Self.groupSlugs[group] ?? [] {
                colors[slug] = status.color.opacity(intensity)
            }
        }
        return colors
    }

    /// Cache signature matching `recoverySlugColors` — see
    /// `MuscleBodyView.colorSignature`.
    private var recoveryColorSignature: String {
        #if os(Android)
        Self.muscleGroups.map { group in
            let status = muscleStatus[group] ?? .untrained
            return "\(group):\(status):\(String(format: "%.3f", volumeIntensity(for: group)))"
        }.joined(separator: "|")
        #else
        ""
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Muscle Recovery").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)

            // Anatomical recovery figures (#929) — green = recovered,
            // orange = moderate, red = recovering, neutral = not trained
            // recently.
            // Explicit width ≈ the figure's natural fit at this row height —
            // on Android, Compose treats the GeometryReader-backed figure as
            // greedy and would otherwise spread the pair across the card.
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    MuscleBodyView(side: .front, slugColors: recoverySlugColors,
                                   colorSignature: recoveryColorSignature,
                                   fitBox: CGSize(width: 84, height: 152))
                        .frame(width: 84)
                    Text("Front").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                VStack(spacing: 2) {
                    MuscleBodyView(side: .back, slugColors: recoverySlugColors,
                                   colorSignature: recoveryColorSignature,
                                   fitBox: CGSize(width: 84, height: 152))
                        .frame(width: 84)
                    Text("Back").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)  // the group buttons below carry the text

            // 3×2 group grid as plain rows, not LazyVGrid — SkipUI's lazy
            // grid collapses inside this ScrollView (card clips mid-grid).
            // The group list is static; rows render identically on iOS.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(Self.muscleGroups.prefix(3)), id: \.self) { groupChip($0) }
                }
                HStack(spacing: 8) {
                    ForEach(Array(Self.muscleGroups.dropFirst(3)), id: \.self) { groupChip($0) }
                }
            }

            // Soreness check-in — a single quiet line, one question per
            // day. Answers teach the model how long THIS user's muscles
            // take to recover; deliberately whisper-weight so it never
            // competes with the figures above.
            if let group = sorenessQuestion {
                HStack(spacing: 8) {
                    Text("Still sore in \(group.lowercased())?")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 4)
                    sorenessChip("Yes") { answerSoreness(group: group, stillSore: true) }
                    sorenessChip("No") { answerSoreness(group: group, stillSore: false) }
                    Button { dismissSoreness(group: group) } label: {
                        Image(systemName: sym("xmark"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss soreness question")
                }
                .padding(.top, 2)
                .transition(.opacity)
                #if !os(Android)
                // SkipUI declares accessibilityElement(children:) unavailable.
                .accessibilityElement(children: .contain)
                #endif
                .accessibilityIdentifier("soreness-checkin")
            }

            // Contextual panel for selected group
            if let group = selectedGroup {
                groupPanel(group)
            }
        }
        .card()
        .onAppear { loadMuscleStatus() }
    }

    // MARK: - Group Chip

    private func groupChip(_ group: String) -> some View {
        let status = muscleStatus[group] ?? .untrained
        return Button { selectedGroup = selectedGroup == group ? nil : group } label: {
            VStack(spacing: 3) {
                Text(group).font(.caption2.weight(.semibold))
                    .foregroundStyle(status.color)
                if let days = daysSince[group] {
                    Text(days == 0 ? "Today" : "\(days)d ago")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("\u{2014}").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                if let count = weeklySetCounts[group], count > 0 {
                    Text("\(count) sets")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
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

    // MARK: - Contextual Group Panel

    private func groupPanel(_ group: String) -> some View {
        let status = muscleStatus[group] ?? .untrained
        let recent = recentExercises[group] ?? []
        #if os(Android)
        let templates = cachedTemplates
        #else
        let templates = (try? WorkoutService.fetchTemplates()) ?? []
        #endif
        let matchingTemplates = templates.filter { t in
            t.name.lowercased().contains(group.lowercased()) ||
            t.exercises.filter { !$0.isWarmup }.contains { ExerciseDatabase.bodyPart(for: $0.name) == group }
        }

        return VStack(alignment: .leading, spacing: 6) {
            if status == .untrained {
                // Not trained recently — encourage with suggestions
                HStack(spacing: 6) {
                    Image(systemName: sym("exclamationmark.triangle.fill")).font(.caption).foregroundStyle(Theme.textSecondary)
                    Text("You haven't trained \(group.lowercased()) in over a week.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if !matchingTemplates.isEmpty {
                    ForEach(matchingTemplates) { t in quickStartButton(template: t) }
                } else {
                    let standards = standardExercises(for: group)
                    if !standards.isEmpty {
                        Text("Try: \(standards.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
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
                        .font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(2)
                }
                ForEach(matchingTemplates) { t in quickStartButton(template: t) }
            }
        }
    }

    private func sorenessChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.cardBackgroundElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickStartButton(template: WorkoutTemplate) -> some View {
        Button {
            onStartTemplate?(template)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sym("play.circle.fill")).font(.caption)
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
        case "Arms": return ["Bicep Curl", "Hammer Curl", "Tricep Pushdown"]
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

    // MARK: - Data Loading

    struct StatusSnapshot: @unchecked Sendable {
        var muscleStatus: [String: MuscleStatus] = [:]
        var daysSince: [String: Int] = [:]
        var lastTrainedDate: [String: String] = [:]
        var recentExercises: [String: [String]] = [:]
        var weeklySetCounts: [String: Int] = [:]
        var sorenessQuestion: String?
        /// Populated only by the Android off-main load (group-panel templates).
        var templates: [WorkoutTemplate] = []
    }

    private func loadMuscleStatus() {
        #if os(Android)
        // AppDatabase work on the UI thread ANRs debug builds on Android —
        // compute off-main, then apply. iOS keeps its inline load.
        let state = sorenessState
        Task {
            let snap = await withCheckedContinuation { (cont: CheckedContinuation<StatusSnapshot, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var snap = Self.computeStatus(state: state)
                    snap.templates = (try? WorkoutService.fetchTemplates()) ?? []
                    cont.resume(returning: snap)
                }
            }
            apply(snap)
        }
        #else
        apply(Self.computeStatus(state: sorenessState))
        #endif
    }

    private func apply(_ snap: StatusSnapshot) {
        muscleStatus = snap.muscleStatus
        daysSince = snap.daysSince
        lastTrainedDate = snap.lastTrainedDate
        recentExercises = snap.recentExercises
        weeklySetCounts = snap.weeklySetCounts
        sorenessQuestion = snap.sorenessQuestion
        #if os(Android)
        cachedTemplates = snap.templates
        #endif
    }

    static func computeStatus(state: MuscleSoreness.State) -> StatusSnapshot {
        var snap = StatusSnapshot()
        let cal = Calendar.current
        let today = Date()
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 500) else { return snap }

        var lastWorked: [String: Date] = [:]

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
                var groupExercises = snap.recentExercises[group, default: []]
                if !groupExercises.contains(s.exerciseName) {
                    groupExercises.append(s.exerciseName)
                }
                snap.recentExercises[group] = groupExercises
                // Count sets in the past 7 days for weekly volume display
                if daysDiff <= 7 { snap.weeklySetCounts[group, default: 0] += 1 }
            }
        }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d"

        var hoursSinceByGroup: [String: Double] = [:]
        for group in muscleGroups {
            if let d = lastWorked[group] { snap.lastTrainedDate[group] = dateFmt.string(from: d) }
            if let lastDate = lastWorked[group] {
                let days = cal.dateComponents([.day], from: lastDate, to: today).day ?? 999
                snap.daysSince[group] = days
                if days > 7 {
                    snap.muscleStatus[group] = .untrained
                } else {
                    // Learned per-group recovery estimate (default 72h
                    // reproduces the old hardcoded day thresholds). Workout
                    // dates are day-granular, hence days × 24.
                    let hours = Double(days) * 24
                    hoursSinceByGroup[group] = hours
                    let estimate = MuscleSoreness.recoveryHours(for: group, state: state)
                    switch MuscleSoreness.status(hoursSince: hours, recoveryHours: estimate) {
                    case .recovering: snap.muscleStatus[group] = .recovering
                    case .moderate: snap.muscleStatus[group] = .moderate
                    case .recovered: snap.muscleStatus[group] = .recovered
                    }
                }
            } else {
                snap.muscleStatus[group] = .untrained
            }
        }

        snap.sorenessQuestion = MuscleSoreness.questionCandidate(
            hoursSinceByGroup: hoursSinceByGroup,
            state: state,
            today: DateFormatters.dateOnly.string(from: today))
        return snap
    }

    // MARK: - Soreness Check-in

    private func answerSoreness(group: String, stillSore: Bool) {
        guard let days = daysSince[group] else { return }
        MuscleSoreness.applyResponse(
            group: group, stillSore: stillSore, hoursSince: Double(days) * 24,
            today: DateFormatters.dateOnly.string(from: Date()),
            state: &sorenessState)
        MuscleSoreness.saveState(sorenessState)
        withAnimation(.easeOut(duration: 0.25)) { sorenessQuestion = nil }
        loadMuscleStatus()   // recolor with the updated estimate
    }

    private func dismissSoreness(group: String) {
        MuscleSoreness.markAsked(
            group: group, today: DateFormatters.dateOnly.string(from: Date()),
            state: &sorenessState)
        MuscleSoreness.saveState(sorenessState)
        withAnimation(.easeOut(duration: 0.25)) { sorenessQuestion = nil }
    }
}
