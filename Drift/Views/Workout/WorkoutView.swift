import SwiftUI
import Charts
import UniformTypeIdentifiers
import AudioToolbox

struct WorkoutView: View {
    @State private var workouts: [WorkoutSummary] = []
    @State private var weeklyCounts: [(weekStart: Date, count: Int)] = []
    @State private var templates: [WorkoutTemplate] = []
    @State private var showingNewWorkout = false
    @State private var showingImport = false
    @State private var importResult: String?
    @State private var isLoading = true

    @State private var activeCalories: Double = 0
    @State private var steps: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Today's burn metrics
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.caption).foregroundStyle(Theme.stepsOrange)
                        Text("\(Int(activeCalories))").font(.subheadline.weight(.bold).monospacedDigit())
                        Text("active cal").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).card()

                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk").font(.caption).foregroundStyle(Theme.deficit)
                        Text(steps >= 1000 ? String(format: "%.1fk", steps/1000) : "\(Int(steps))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text("steps").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).card()
                }

                // Body recovery map
                BodyMapView()

                if !weeklyCounts.isEmpty { consistencyChart }

                // Start buttons
                VStack(spacing: 8) {
                    Button { showingNewWorkout = true } label: {
                        Label("Start Empty Workout", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent)

                    // Templates
                    if !templates.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Templates").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(templates) { t in
                                Button {
                                    showingNewWorkout = true
                                    // Template loading handled in ActiveWorkoutView
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(t.name).font(.subheadline)
                                            Text(t.exercises.map(\.name).prefix(3).joined(separator: ", "))
                                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle").foregroundStyle(Theme.accent)
                                    }
                                }.tint(.primary)
                            }
                        }
                        .card()
                    }

                    Button { showingImport = true } label: {
                        Label("Import from Strong", systemImage: "doc.badge.plus")
                    }.buttonStyle(.bordered)
                }

                if let r = importResult { Text(r).font(.caption).foregroundStyle(.secondary) }

                // History
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Workouts").font(.headline)
                        Text("Start a workout or import from Strong").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 30)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(workouts, id: \.workout.id) { s in
                            NavigationLink { WorkoutDetailView(summary: s) } label: { workoutCard(s) }.tint(.primary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingNewWorkout) { ActiveWorkoutView { loadData() } }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText]) { handleImport($0) }
        .onAppear { loadData() }
        .task {
            let hk = HealthKitService.shared
            activeCalories = (try? await hk.fetchCaloriesBurned(for: Date()).active) ?? 0
            steps = (try? await hk.fetchSteps(for: Date())) ?? 0
        }
    }

    private var consistencyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workouts Per Week").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(weeklyCounts.reduce(0) { $0 + $1.count }) total").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Chart {
                ForEach(weeklyCounts.indices, id: \.self) { i in
                    BarMark(x: .value("", weeklyCounts[i].weekStart), y: .value("", weeklyCounts[i].count))
                        .foregroundStyle(weeklyCounts[i].count > 0 ? Theme.accent : Theme.cardBackgroundElevated).cornerRadius(3)
                }
            }
            .chartYScale(domain: 0...max(5, (weeklyCounts.map(\.count).max() ?? 3) + 1))
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2)); AxisValueLabel().foregroundStyle(.secondary) } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(.secondary) } }
            .frame(height: 100)
        }.card()
    }

    private func workoutCard(_ s: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.workout.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDate(s.workout.date)).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                if !s.workout.durationDisplay.isEmpty { Label(s.workout.durationDisplay, systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                Label("\(Int(s.totalVolume)) lb", systemImage: "scalemass").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(s.bestSets.prefix(3), id: \.exercise) { best in
                HStack {
                    Text(abbreviate(best.exercise)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(Int(best.weight)) lb × \(best.reps)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }.card()
    }

    private func abbreviate(_ n: String) -> String { n.count <= 25 ? n : String(n.prefix(22)) + "..." }
    private func formatDate(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; guard let date = f.date(from: String(d.prefix(10))) else { return d }
        return DateFormatters.dayDisplay.string(from: date)
    }
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): do { let r = try WorkoutService.importStrongCSV(url: url); importResult = "Imported \(r.workouts) workouts, \(r.sets) sets"; loadData() } catch { importResult = "Failed: \(error.localizedDescription)" }
        case .failure(let error): importResult = "Error: \(error.localizedDescription)"
        }
    }
    private func loadData() {
        isLoading = true
        do {
            let raw = try WorkoutService.fetchWorkouts(limit: 50)
            workouts = try raw.map { try WorkoutService.buildSummary(for: $0) }
            weeklyCounts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
            templates = try WorkoutService.fetchTemplates()
        } catch { Log.app.error("Workout load: \(error.localizedDescription)") }
        isLoading = false
    }
}

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    @State private var sets: [WorkoutSet] = []
    @State private var showingShare = false
    @State private var showingSaveTemplate = false

    private var shareText: String {
        var t = "💪 \(summary.workout.name)\n📅 \(formatDate(summary.workout.date))\n"
        if !summary.workout.durationDisplay.isEmpty { t += "⏱ \(summary.workout.durationDisplay)  " }
        t += "🏋️ \(Int(summary.totalVolume)) lb\n\n"
        let grouped = Dictionary(grouping: sets.filter { !$0.isWarmup }) { $0.exerciseName }
        for ex in summary.exercises {
            if let exSets = grouped[ex] {
                t += "\(ex)\n"
                for s in exSets { t += "  \(s.setOrder). \(s.display)\n" }
                t += "\n"
            }
        }
        t += "Logged with Drift"; return t
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.workout.name).font(.headline)
                    Text(formatDate(summary.workout.date)).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if !summary.workout.durationDisplay.isEmpty { Label(summary.workout.durationDisplay, systemImage: "clock") }
                        Label("\(Int(summary.totalVolume)) lb", systemImage: "scalemass")
                        Label("\(summary.totalSets) sets", systemImage: "number")
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).card()

                let grouped = Dictionary(grouping: sets) { $0.exerciseName }
                ForEach(summary.exercises, id: \.self) { ex in
                    if let exSets = grouped[ex] {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ex).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(muscleGroup(for: ex)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            ForEach(exSets, id: \.id) { s in
                                HStack {
                                    Text(s.isWarmup ? "W" : "\(s.setOrder)").font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(s.isWarmup ? Theme.fatYellow : .primary).frame(width: 20)
                                    Text(s.display).font(.subheadline.monospacedDigit())
                                    Spacer()
                                    if let rm = s.estimated1RM { Text("1RM: \(Int(rm))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                                }
                            }
                        }.card()
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Workout").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { saveAsTemplate() } label: { Label("Save as Template", systemImage: "doc.on.doc") }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.accent) }
            }
        }
        .sheet(isPresented: $showingShare) { ShareSheet(text: shareText) }
        .onAppear { if let wid = summary.workout.id { sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? [] } }
    }

    private func muscleGroup(for exercise: String) -> String {
        let e = exercise.lowercased()
        if e.contains("bench") || e.contains("chest") || e.contains("fly") || e.contains("dip") { return "Chest" }
        if e.contains("squat") || e.contains("leg") || e.contains("calf") || e.contains("hip") || e.contains("deadlift") || e.contains("lunge") || e.contains("press") && e.contains("leg") { return "Legs" }
        if e.contains("lat") || e.contains("row") || e.contains("pull") || e.contains("back") { return "Back" }
        if e.contains("shoulder") || e.contains("lateral raise") || e.contains("overhead press") || e.contains("face pull") { return "Shoulders" }
        if e.contains("bicep") || e.contains("curl") || e.contains("tricep") || e.contains("hammer") { return "Arms" }
        if e.contains("crunch") || e.contains("plank") || e.contains("ab") || e.contains("leg raise") { return "Core" }
        if e.contains("farmer") { return "Full Body" }
        return ""
    }

    private func saveAsTemplate() {
        let exercises = summary.exercises.map { WorkoutTemplate.TemplateExercise(name: $0, sets: 3) }
        if let json = try? JSONEncoder().encode(exercises), let jsonStr = String(data: json, encoding: .utf8) {
            var t = WorkoutTemplate(name: summary.workout.name, exercisesJson: jsonStr, createdAt: ISO8601DateFormatter().string(from: Date()))
            try? WorkoutService.saveTemplate(&t)
        }
    }

    private func formatDate(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; guard let date = f.date(from: String(d.prefix(10))) else { return d }
        f.dateFormat = "EEEE, MMM d, yyyy"; return f.string(from: date)
    }
}

// MARK: - Active Workout (with live timer, rest timer, prefilled weights)

struct ActiveWorkoutView: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workoutName = "Workout"
    @State private var exercises: [ActiveExercise] = []
    @State private var showingExercisePicker = false
    @State private var startTime = Date()
    @State private var elapsedSeconds = 0
    @State private var workoutTimer: Timer?
    // Global rest timer state
    @State private var restSeconds = 0
    @State private var restTotalSeconds = 90
    @State private var restTimerActive = false
    @State private var restTimer: Timer?
    @State private var activeRestExerciseIndex: Int? = nil
    @State private var activeRestSetIndex: Int? = nil

    struct ActiveExercise: Identifiable {
        let id = UUID()
        var name: String
        var restTime: Int = 90 // seconds, customizable per exercise
        var sets: [ActiveSet]
        var previousSets: [String] // display strings like "35 lb × 10"
    }

    struct ActiveSet: Identifiable {
        let id = UUID()
        var weight: String
        var reps: String
        var done: Bool = false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Workout header
                    VStack(spacing: 6) {
                        TextField("Workout name", text: $workoutName)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Label(DateFormatters.dayDisplay.string(from: Date()), systemImage: "calendar")
                            Label(formatDuration(elapsedSeconds), systemImage: "clock")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 12)

                    // Exercises
                    ForEach(exercises.indices, id: \.self) { ei in
                        exerciseSection(ei)
                    }

                    // Add exercise
                    Button { showingExercisePicker = true } label: {
                        Text("Add Exercise").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(Theme.accent).padding(.horizontal, 12)

                    if !exercises.isEmpty {
                        Button { saveWorkout() } label: {
                            Text("Finish").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(Theme.deficit).padding(.horizontal, 12)

                        Button("Cancel Workout", role: .destructive) { stopTimers(); dismiss() }
                            .font(.caption).padding(.top, 4)
                    }
                }.padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { stopTimers(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if !exercises.isEmpty {
                        Button("Finish") { saveWorkout() }.foregroundStyle(Theme.deficit)
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { name in
                    addExercise(name: name)
                }
            }
            .onAppear { startWorkoutTimer() }
            .onDisappear { stopTimers() }
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(_ ei: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Exercise header
            HStack {
                Text(exercises[ei].name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.calorieBlue)
                Text(guessGroup(exercises[ei].name)).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                // Rest time customizer
                Menu {
                    ForEach([30, 60, 90, 120, 150, 180], id: \.self) { sec in
                        Button("\(sec / 60):\(String(format: "%02d", sec % 60))") {
                            exercises[ei].restTime = sec
                        }
                    }
                } label: {
                    Text("\(exercises[ei].restTime / 60):\(String(format: "%02d", exercises[ei].restTime % 60))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
                Button { exercises.remove(at: ei) } label: {
                    Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary)
                }
            }

            // Column headers
            HStack(spacing: 0) {
                Text("Set").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 28, alignment: .leading)
                Text("Previous").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 85, alignment: .leading)
                Text("lbs").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 55)
                Text("Reps").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 50)
                Spacer()
                Text("✓").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 30)
            }

            // Sets
            ForEach(exercises[ei].sets.indices, id: \.self) { si in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("\(si + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)

                        // Previous
                        Text(si < exercises[ei].previousSets.count ? exercises[ei].previousSets[si] : "—")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 85, alignment: .leading)

                        // Weight
                        TextField(si < exercises[ei].previousSets.count ? prevWeight(exercises[ei].previousSets[si]) : "0",
                                  text: $exercises[ei].sets[si].weight)
                            .keyboardType(.decimalPad).font(.subheadline.monospacedDigit())
                            .multilineTextAlignment(.center).frame(width: 55)
                            .padding(.vertical, 4)
                            .background(exercises[ei].sets[si].done ? Theme.deficit.opacity(0.1) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 4))

                        // Reps
                        TextField(si < exercises[ei].previousSets.count ? prevReps(exercises[ei].previousSets[si]) : "0",
                                  text: $exercises[ei].sets[si].reps)
                            .keyboardType(.numberPad).font(.subheadline.monospacedDigit())
                            .multilineTextAlignment(.center).frame(width: 50)
                            .padding(.vertical, 4).padding(.leading, 4)
                            .background(exercises[ei].sets[si].done ? Theme.deficit.opacity(0.1) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 4))

                        Spacer()

                        // Done button
                        Button {
                            exercises[ei].sets[si].done.toggle()
                            if exercises[ei].sets[si].done {
                                startRest(exerciseIndex: ei, setIndex: si, duration: exercises[ei].restTime)
                            }
                        } label: {
                            Image(systemName: exercises[ei].sets[si].done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(exercises[ei].sets[si].done ? Theme.deficit : .secondary)
                        }.frame(width: 30)
                    }
                    .padding(.vertical, 2)

                    // Inline rest timer bar (shows after this set if active)
                    if restTimerActive && activeRestExerciseIndex == ei && activeRestSetIndex == si {
                        restTimerBar
                    }
                }
            }

            // Add set button with rest time
            Button {
                exercises[ei].sets.append(ActiveSet(weight: "", reps: ""))
            } label: {
                Text("+ Add Set (\(exercises[ei].restTime / 60):\(String(format: "%02d", exercises[ei].restTime % 60)))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
        }
        .card().padding(.horizontal, 12)
    }

    // MARK: - Rest Timer Bar (inline, like Strong)

    private var restTimerBar: some View {
        let progress = restTotalSeconds > 0 ? Double(restSeconds) / Double(restTotalSeconds) : 0

        return VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.cardBackgroundElevated)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.calorieBlue)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 28)
            .overlay {
                Text(formatRestTime(restSeconds))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatRestTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func prevWeight(_ prev: String) -> String {
        prev.components(separatedBy: " ").first ?? "0"
    }

    private func prevReps(_ prev: String) -> String {
        let parts = prev.components(separatedBy: "× ")
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "0"
    }

    private func guessGroup(_ name: String) -> String {
        let e = name.lowercased()
        if e.contains("bench") || e.contains("chest") || e.contains("fly") || e.contains("dip") { return "· Chest" }
        if e.contains("squat") || e.contains("leg") || e.contains("calf") || e.contains("deadlift") || e.contains("hip") || e.contains("lunge") { return "· Legs" }
        if e.contains("lat") || e.contains("row") || e.contains("pull") || e.contains("back") { return "· Back" }
        if e.contains("shoulder") || e.contains("lateral") || e.contains("overhead") || e.contains("face pull") { return "· Shoulders" }
        if e.contains("bicep") || e.contains("curl") || e.contains("tricep") || e.contains("hammer") { return "· Arms" }
        if e.contains("crunch") || e.contains("plank") || e.contains("ab") || e.contains("leg raise") { return "· Core" }
        return ""
    }

    // MARK: - Timers

    private func startWorkoutTimer() {
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds = Int(Date().timeIntervalSince(startTime))
        }
    }

    private func startRest(exerciseIndex: Int, setIndex: Int, duration: Int) {
        restTotalSeconds = duration
        restSeconds = duration
        activeRestExerciseIndex = exerciseIndex
        activeRestSetIndex = setIndex
        restTimerActive = true
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if restSeconds > 0 {
                restSeconds -= 1
            } else {
                t.invalidate()
                restTimerActive = false
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    private func stopTimers() { workoutTimer?.invalidate(); restTimer?.invalidate() }

    // MARK: - Add Exercise (with prefill)

    private func addExercise(name: String) {
        let history = (try? WorkoutService.fetchExerciseHistory(name: name).prefix(10)) ?? []
        let previous = history.prefix(3).map { s in
            "\(Int(s.weightLbs ?? 0)) lb × \(s.reps ?? 0)"
        }

        let prefilled = history.prefix(3).map { s in
            ActiveSet(weight: s.weightLbs.map { String(Int($0)) } ?? "", reps: s.reps.map { String($0) } ?? "")
        }
        let sets = prefilled.isEmpty ? [ActiveSet(weight: "", reps: ""), ActiveSet(weight: "", reps: ""), ActiveSet(weight: "", reps: "")] : Array(prefilled)

        exercises.append(ActiveExercise(name: name, sets: sets, previousSets: Array(previous)))
    }

    private func saveWorkout() {
        stopTimers()
        var workout = Workout(name: workoutName, date: DateFormatters.dateOnly.string(from: Date()),
                              durationSeconds: elapsedSeconds, createdAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try WorkoutService.saveWorkout(&workout)
            guard let wid = workout.id else { return }
            var allSets: [WorkoutSet] = []
            for ex in exercises {
                for (si, s) in ex.sets.enumerated() {
                    guard let w = Double(s.weight), let r = Int(s.reps), r > 0 else { continue }
                    allSets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1, weightLbs: w, reps: r, isWarmup: false))
                }
            }
            try WorkoutService.saveSets(allSets)
            onComplete(); dismiss()
        } catch { Log.app.error("Save workout: \(error.localizedDescription)") }
    }

    private func formatDuration(_ s: Int) -> String {
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Exercise Picker (with muscle group labels + custom)

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var exerciseList: [(name: String, group: String)] {
        let all = (try? WorkoutService.allExerciseNames()) ?? []
        let defaults = ["Bench Press (Barbell)", "Squat (Barbell)", "Deadlift (Barbell)", "Overhead Press (Barbell)",
                        "Bench Press (Dumbbell)", "Incline Bench Press (Dumbbell)", "Lat Pulldown (Cable)",
                        "Seated Row (Cable)", "Leg Press", "Leg Extension (Machine)", "Leg Curl (Machine)",
                        "Bicep Curl (Dumbbell)", "Triceps Pushdown (Cable)", "Lateral Raise (Dumbbell)",
                        "Pull Up", "Push Up", "Plank", "Hip Thrust (Barbell)", "Romanian Deadlift (Barbell)",
                        "Face Pull (Cable)", "Chest Fly (Cable)", "Hammer Curl (Dumbbell)"]
        let combined = Array(Set(all + defaults)).sorted()
        let filtered = query.isEmpty ? combined : combined.filter { $0.localizedCaseInsensitiveContains(query) }
        return filtered.map { (name: $0, group: guessGroup($0)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search or add exercise", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                }.padding().background(.ultraThinMaterial)

                List {
                    if !query.isEmpty && !exerciseList.contains(where: { $0.name.lowercased() == query.lowercased() }) {
                        Button { onSelect(query); dismiss() } label: {
                            Label("Add \"\(query)\"", systemImage: "plus.circle").foregroundStyle(Theme.accent)
                        }
                    }
                    ForEach(exerciseList, id: \.name) { ex in
                        Button { onSelect(ex.name); dismiss() } label: {
                            HStack {
                                Text(ex.name).font(.subheadline)
                                Spacer()
                                Text(ex.group).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.tint(.primary)
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func guessGroup(_ name: String) -> String {
        let e = name.lowercased()
        if e.contains("bench") || e.contains("chest") || e.contains("fly") || e.contains("dip") { return "Chest" }
        if e.contains("squat") || e.contains("leg") || e.contains("calf") || e.contains("hip") || e.contains("deadlift") || e.contains("lunge") || e.contains("thrust") { return "Legs" }
        if e.contains("lat") || e.contains("row") || e.contains("pull") || e.contains("back") { return "Back" }
        if e.contains("shoulder") || e.contains("lateral raise") || e.contains("overhead") || e.contains("face pull") { return "Shoulders" }
        if e.contains("bicep") || e.contains("curl") || e.contains("tricep") || e.contains("hammer") { return "Arms" }
        if e.contains("crunch") || e.contains("plank") || e.contains("ab") || e.contains("leg raise") { return "Core" }
        return "Other"
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
