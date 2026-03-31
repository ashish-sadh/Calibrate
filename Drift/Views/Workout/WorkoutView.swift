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
    @State private var showingCreateTemplate = false
    @State private var showingExerciseBrowser = false
    @State private var importResult: String?
    @State private var isLoading = true
    @State private var selectedTemplate: WorkoutTemplate? = nil

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
                Button { selectedTemplate = nil; showingNewWorkout = true } label: {
                    Label("Start Empty Workout", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)

                // Templates
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Templates").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { showingCreateTemplate = true } label: {
                            Label("New", systemImage: "plus").font(.caption)
                        }
                    }

                    if templates.isEmpty {
                        Text("Save a workout as template or create one here")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(templates) { t in
                            HStack {
                                Button {
                                    selectedTemplate = t
                                    showingNewWorkout = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.subheadline.weight(.medium))
                                        let working = t.exercises.filter { !$0.isWarmup }
                                        Text(working.map(\.name).prefix(3).joined(separator: ", "))
                                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                        let warmupCount = t.exercises.filter(\.isWarmup).count
                                        if warmupCount > 0 {
                                            Text("\(warmupCount) warmup + \(working.count) exercises")
                                                .font(.system(size: 9)).foregroundStyle(.quaternary)
                                        }
                                    }
                                }.tint(.primary)

                                Spacer()

                                Button { selectedTemplate = t; showingNewWorkout = true } label: {
                                    Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent)
                                }

                                if let tid = t.id {
                                    Button {
                                        try? AppDatabase.shared.writer.write { db in _ = try WorkoutTemplate.deleteOne(db, id: tid) }
                                        loadData()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.tertiary)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .card()

                // Browse exercises + Import
                HStack(spacing: 8) {
                    Button { showingExerciseBrowser = true } label: {
                        Label("Exercises", systemImage: "dumbbell").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)

                    Button { showingImport = true } label: {
                        Label("Import", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
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
        .sheet(isPresented: $showingNewWorkout) {
            ActiveWorkoutView(template: selectedTemplate) {
                selectedTemplate = nil
                loadData()
            }
        }
        .sheet(isPresented: $showingCreateTemplate) {
            CreateTemplateView { loadData() }
        }
        .sheet(isPresented: $showingExerciseBrowser) {
            ExerciseBrowserView()
        }
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
        // Determine warmup vs working from the saved sets
        let warmupNames = Set(sets.filter(\.isWarmup).map(\.exerciseName))
        let exercises = summary.exercises.map { name in
            let isW = warmupNames.contains(name)
            let count = sets.filter { $0.exerciseName == name && !$0.isWarmup }.count
            return WorkoutTemplate.TemplateExercise(name: name, sets: max(count, isW ? 2 : 3), isWarmup: isW,
                                                    restSeconds: isW ? 30 : 90)
        }
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
    var template: WorkoutTemplate? = nil
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
        var restTime: Int = 90
        var isWarmupExercise: Bool = false  // entire exercise is warmup (from template)
        var notes: String?                   // trainer notes (e.g. "6-8 reps")
        var sets: [ActiveSet]
        var previousSets: [String]
    }

    struct ActiveSet: Identifiable {
        let id = UUID()
        var weight: String
        var reps: String
        var done: Bool = false
        var isWarmup: Bool = false  // individual set warmup toggle
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

                    // Warmup exercises
                    let warmupIndices = exercises.indices.filter { exercises[$0].isWarmupExercise }
                    let workingIndices = exercises.indices.filter { !exercises[$0].isWarmupExercise }

                    if !warmupIndices.isEmpty {
                        Text("WARMUP").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                            .padding(.horizontal, 16)
                        ForEach(warmupIndices, id: \.self) { ei in exerciseSection(ei) }

                        if !workingIndices.isEmpty {
                            Divider().padding(.horizontal, 16).padding(.vertical, 4)
                            Text("WORKING SETS").font(.caption2.weight(.bold)).foregroundStyle(Theme.calorieBlue)
                                .padding(.horizontal, 16)
                        }
                    }

                    // Working exercises
                    ForEach(workingIndices, id: \.self) { ei in exerciseSection(ei) }

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
            .onAppear {
                startWorkoutTimer()
                if let t = template {
                    workoutName = t.name
                    let warmups = t.exercises.filter(\.isWarmup)
                    let working = t.exercises.filter { !$0.isWarmup }
                    // Add warmup exercises
                    for ex in warmups {
                        addExercise(name: ex.name, setCount: ex.sets, restTime: ex.restSeconds, isWarmup: true, notes: ex.notes)
                    }
                    // Add working exercises
                    for ex in working {
                        addExercise(name: ex.name, setCount: ex.sets, restTime: ex.restSeconds, notes: ex.notes)
                    }
                }
            }
            .onDisappear { stopTimers() }
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(_ ei: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Exercise header
            HStack {
                if exercises[ei].isWarmupExercise {
                    Text("W").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.fatYellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                }
                Text(exercises[ei].name).font(.subheadline.weight(.bold))
                    .foregroundStyle(exercises[ei].isWarmupExercise ? Theme.fatYellow : Theme.calorieBlue)
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

            // Notes from trainer
            if let notes = exercises[ei].notes, !notes.isEmpty {
                Text(notes).font(.caption2).foregroundStyle(.secondary).italic()
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
                        Button {
                            exercises[ei].sets[si].isWarmup.toggle()
                        } label: {
                            Text(exercises[ei].sets[si].isWarmup || exercises[ei].isWarmupExercise ? "W" : "\(si + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(exercises[ei].sets[si].isWarmup || exercises[ei].isWarmupExercise ? Theme.fatYellow : .secondary)
                        }.buttonStyle(.plain).frame(width: 28, alignment: .leading)

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
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            Task { @MainActor in
                elapsedSeconds = Int(Date().timeIntervalSince(startTime))
            }
        }
    }

    private func startRest(exerciseIndex: Int, setIndex: Int, duration: Int) {
        restTotalSeconds = duration
        restSeconds = duration
        activeRestExerciseIndex = exerciseIndex
        activeRestSetIndex = setIndex
        restTimerActive = true
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if restSeconds > 0 {
                    restSeconds -= 1
                } else {
                    restTimer?.invalidate()
                    restTimerActive = false
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }

    private func stopTimers() { workoutTimer?.invalidate(); restTimer?.invalidate() }

    // MARK: - Add Exercise (with prefill)

    private func addExercise(name: String, setCount: Int? = nil, restTime: Int = 90, isWarmup: Bool = false, notes: String? = nil) {
        let history = (try? WorkoutService.fetchExerciseHistory(name: name).prefix(10)) ?? []
        let previous = history.prefix(3).map { s in
            "\(Int(s.weightLbs ?? 0)) lb \u{00D7} \(s.reps ?? 0)"
        }

        let count = setCount ?? (previous.isEmpty ? 3 : max(previous.count, 3))
        var sets: [ActiveSet] = []
        for i in 0..<count {
            if i < history.count {
                let s = history[i]
                sets.append(ActiveSet(weight: s.weightLbs.map { String(Int($0)) } ?? "",
                                      reps: s.reps.map { String($0) } ?? "", isWarmup: isWarmup))
            } else {
                sets.append(ActiveSet(weight: "", reps: "", isWarmup: isWarmup))
            }
        }

        exercises.append(ActiveExercise(name: name, restTime: restTime, isWarmupExercise: isWarmup,
                                         notes: notes, sets: sets, previousSets: Array(previous)))
    }

    private func saveWorkout() {
        stopTimers()
        var workout = Workout(name: workoutName, date: DateFormatters.dateOnly.string(from: Date()),
                              durationSeconds: elapsedSeconds, createdAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try WorkoutService.saveWorkout(&workout)
            guard let wid = workout.id else {
                Log.app.error("Save workout: no ID after save")
                return
            }
            var allSets: [WorkoutSet] = []
            for ex in exercises {
                for (si, s) in ex.sets.enumerated() where s.done {
                    let w = Double(s.weight) ?? 0
                    let r = Int(s.reps) ?? 0
                    guard r > 0 else { continue }
                    allSets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                             weightLbs: w, reps: r, isWarmup: s.isWarmup || ex.isWarmupExercise))
                }
            }
            if allSets.isEmpty {
                for ex in exercises {
                    for (si, s) in ex.sets.enumerated() {
                        let w = Double(s.weight) ?? 0
                        let r = Int(s.reps) ?? 0
                        guard r > 0 else { continue }
                        allSets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                                 weightLbs: w, reps: r, isWarmup: s.isWarmup || ex.isWarmupExercise))
                    }
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

// MARK: - Exercise Picker (873 exercises + history + custom)

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showingCustom = false
    @State private var selectedBodyPartFilter: String? = nil

    private var results: [ExerciseDatabase.ExerciseInfo] {
        var list = query.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: query) + ExerciseDatabase.customExercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if let filter = selectedBodyPartFilter { list = list.filter { $0.bodyPart == filter } }
        return Array(list.prefix(50))
    }

    // Exercises from workout history that aren't in the database
    private var historyExtras: [String] {
        let dbNames = Set(ExerciseDatabase.all.map { $0.name.lowercased() })
        let history = (try? WorkoutService.allExerciseNames()) ?? []
        let filtered = history.filter { !dbNames.contains($0.lowercased()) }
        if query.isEmpty { return filtered }
        return filtered.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search 873 exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }.padding().background(.ultraThinMaterial)

                // Body part filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip("All", selected: selectedBodyPartFilter == nil) { selectedBodyPartFilter = nil }
                        ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"], id: \.self) { part in
                            filterChip(part, selected: selectedBodyPartFilter == part) { selectedBodyPartFilter = part }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }

                List {
                    // Custom exercise option
                    Button { showingCustom = true } label: {
                        Label("Create Custom Exercise", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }

                    // History exercises (not in DB)
                    if !historyExtras.isEmpty {
                        Section("Your Exercises") {
                            ForEach(historyExtras, id: \.self) { name in
                                Button { onSelect(name); dismiss() } label: {
                                    HStack {
                                        Text(name).font(.subheadline)
                                        Spacer()
                                        Text(ExerciseDatabase.bodyPart(for: name)).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }.tint(.primary)
                            }
                        }
                    }

                    // Database exercises
                    Section(query.isEmpty ? "All Exercises (\(results.count))" : "\(results.count) results") {
                        ForEach(results) { ex in
                            Button { onSelect(ex.name); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(ex.name).font(.subheadline)
                                        Spacer()
                                        Text(ex.bodyPart).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    HStack(spacing: 6) {
                                        Text(ex.equipment).font(.system(size: 9)).foregroundStyle(.tertiary)
                                        Text(ex.primaryMuscles.joined(separator: ", ")).font(.system(size: 9)).foregroundStyle(.quaternary)
                                    }
                                }
                            }.tint(.primary)
                        }
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingCustom) {
                CustomExerciseSheet { name in onSelect(name); dismiss() }
            }
        }
    }

    private func filterChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.3) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
    }
}

// MARK: - Custom Exercise Sheet

struct CustomExerciseSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bodyPart = "Chest"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Targets", selection: $bodyPart) {
                    ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body"], id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle("Custom Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        ExerciseDatabase.addCustomExercise(name: name, bodyPart: bodyPart)
                        onSave(name)
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Create Template

struct CreateTemplateView: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var exercises: [WorkoutTemplate.TemplateExercise] = []
    @State private var showingPicker = false
    @State private var addingWarmup = false
    @State private var editingIndex: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Name") {
                    TextField("e.g., Push Day", text: $name)
                }

                let warmups = exercises.filter(\.isWarmup)
                let working = exercises.filter { !$0.isWarmup }

                if !warmups.isEmpty {
                    Section("Warmup (\(warmups.count))") {
                        ForEach(exercises.indices.filter { exercises[$0].isWarmup }, id: \.self) { i in
                            templateExerciseRow(i)
                        }
                        .onDelete { offsets in
                            let warmupIndices = exercises.indices.filter { exercises[$0].isWarmup }
                            for offset in offsets.sorted().reversed() { exercises.remove(at: warmupIndices[offset]) }
                        }
                        Button { addingWarmup = true; showingPicker = true } label: {
                            Label("Add Warmup", systemImage: "plus.circle").foregroundStyle(Theme.fatYellow)
                        }
                    }
                }

                Section(warmups.isEmpty ? "Exercises" : "Working Sets (\(working.count))") {
                    ForEach(exercises.indices.filter { !exercises[$0].isWarmup }, id: \.self) { i in
                        templateExerciseRow(i)
                    }
                    .onDelete { offsets in
                        let workingIndices = exercises.indices.filter { !exercises[$0].isWarmup }
                        for offset in offsets.sorted().reversed() { exercises.remove(at: workingIndices[offset]) }
                    }
                    Button { addingWarmup = false; showingPicker = true } label: {
                        Label("Add Exercise", systemImage: "plus.circle").foregroundStyle(Theme.accent)
                    }
                    if warmups.isEmpty {
                        Button { addingWarmup = true; showingPicker = true } label: {
                            Label("Add Warmup Exercise", systemImage: "plus.circle").foregroundStyle(Theme.fatYellow)
                        }
                    }
                }

                Section {
                    Button {
                        if let json = try? JSONEncoder().encode(exercises), let jsonStr = String(data: json, encoding: .utf8) {
                            var t = WorkoutTemplate(name: name.isEmpty ? "Template" : name, exercisesJson: jsonStr, createdAt: ISO8601DateFormatter().string(from: Date()))
                            try? WorkoutService.saveTemplate(&t)
                        }
                        onSave(); dismiss()
                    } label: {
                        Label("Save Template", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(exercises.isEmpty)
                }
            }
            .navigationTitle("New Template").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exName in
                    exercises.append(.init(name: exName, sets: addingWarmup ? 2 : 3, isWarmup: addingWarmup,
                                           restSeconds: addingWarmup ? 30 : 90))
                }
            }
            .sheet(item: editingBinding) { idx in
                TemplateExerciseEditor(exercise: exercises[idx.value]) { updated in
                    exercises[idx.value] = updated
                }
            }
        }
    }

    private var editingBinding: Binding<IdentifiableInt?> {
        Binding(get: { editingIndex.map { IdentifiableInt(value: $0) } },
                set: { editingIndex = $0?.value })
    }

    private func templateExerciseRow(_ index: Int) -> some View {
        let ex = exercises[index]
        return Button { editingIndex = index } label: {
            HStack {
                if ex.isWarmup {
                    Text("W").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Theme.fatYellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ex.name).font(.subheadline)
                    HStack(spacing: 4) {
                        Text("\(ex.sets) sets").font(.caption2).foregroundStyle(.tertiary)
                        Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                        Text("\(ex.restSeconds/60):\(String(format: "%02d", ex.restSeconds%60)) rest")
                            .font(.caption2).foregroundStyle(.tertiary)
                        if let notes = ex.notes, !notes.isEmpty {
                            Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                            Text(notes).font(.caption2).foregroundStyle(.secondary).italic()
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.quaternary)
            }
        }.tint(.primary)
    }
}

// MARK: - Template Exercise Editor

private struct TemplateExerciseEditor: View {
    let exercise: WorkoutTemplate.TemplateExercise
    let onSave: (WorkoutTemplate.TemplateExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sets: Int
    @State private var restSeconds: Int
    @State private var notes: String
    @State private var isWarmup: Bool

    init(exercise: WorkoutTemplate.TemplateExercise, onSave: @escaping (WorkoutTemplate.TemplateExercise) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _sets = State(initialValue: exercise.sets)
        _restSeconds = State(initialValue: exercise.restSeconds)
        _notes = State(initialValue: exercise.notes ?? "")
        _isWarmup = State(initialValue: exercise.isWarmup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exercise.name).font(.headline)
                }

                Section("Configuration") {
                    Stepper("\(sets) sets", value: $sets, in: 1...10)

                    Picker("Rest", selection: $restSeconds) {
                        ForEach([15, 30, 45, 60, 90, 120, 150, 180], id: \.self) { sec in
                            Text("\(sec/60):\(String(format: "%02d", sec%60))").tag(sec)
                        }
                    }

                    Toggle("Warmup exercise", isOn: $isWarmup)
                }

                Section("Notes") {
                    TextField("e.g., 8-12 reps, slow eccentric", text: $notes)
                }
            }
            .navigationTitle("Edit Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(.init(name: exercise.name, sets: sets, isWarmup: isWarmup,
                                     restSeconds: restSeconds, notes: notes.isEmpty ? nil : notes))
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Exercise Browser (873 exercises)

struct ExerciseBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedPart: String? = nil
    @State private var showingCustom = false

    private var results: [ExerciseDatabase.ExerciseInfo] {
        var list = query.isEmpty ? ExerciseDatabase.all : ExerciseDatabase.search(query: query)
        if let part = selectedPart { list = list.filter { $0.bodyPart == part } }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search 873 exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                }.padding().background(.ultraThinMaterial)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", selected: selectedPart == nil) { selectedPart = nil }
                        ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"], id: \.self) { p in
                            chip(p, selected: selectedPart == p) { selectedPart = p }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }

                List {
                    if !query.isEmpty && results.isEmpty {
                        Button { showingCustom = true } label: {
                            Label("Add \"\(query)\" as custom exercise", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }

                    ForEach(results.prefix(100)) { ex in
                        NavigationLink {
                            ExerciseDetailView(exerciseName: ex.name, info: ex)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(ex.name).font(.subheadline)
                                    Spacer()
                                    Text(ex.bodyPart).font(.caption2).foregroundStyle(.tertiary)
                                }
                                HStack(spacing: 8) {
                                    Label(ex.equipment, systemImage: "wrench.and.screwdriver").font(.caption2).foregroundStyle(.tertiary)
                                    Text(ex.primaryMuscles.joined(separator: ", ")).font(.caption2).foregroundStyle(.quaternary)
                                }
                            }
                        }.tint(.primary)
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Exercise Database").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCustom = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCustom) {
                CustomExerciseSheet { _ in } // just adding to DB, no callback needed
            }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.3) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
    }
}

// MARK: - Exercise Detail (history + PR)

struct ExerciseDetailView: View {
    let exerciseName: String
    let info: ExerciseDatabase.ExerciseInfo?
    @State private var history: [WorkoutSet] = []
    @State private var pr: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Exercise info
                VStack(alignment: .leading, spacing: 6) {
                    Text(exerciseName).font(.title3.weight(.bold))
                    if let info {
                        HStack(spacing: 8) {
                            Label(info.bodyPart, systemImage: "figure.strengthtraining.traditional").font(.caption)
                            Label(info.equipment, systemImage: "wrench.and.screwdriver").font(.caption)
                        }.foregroundStyle(.secondary)
                        if !info.primaryMuscles.isEmpty {
                            Text("Muscles: \(info.primaryMuscles.joined(separator: ", "))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if let pr {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Theme.fatYellow)
                            Text("PR: \(Int(pr)) lb (est. 1RM)")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.fatYellow)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                // History
                if history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock").font(.title2).foregroundStyle(.tertiary)
                        Text("No history yet").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(history.prefix(20), id: \.id) { s in
                            HStack {
                                Text(s.isWarmup ? "W" : "\(s.setOrder)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(s.isWarmup ? Theme.fatYellow : .secondary)
                                    .frame(width: 20)
                                Text(s.display).font(.subheadline.monospacedDigit())
                                Spacer()
                                if let rm = s.estimated1RM {
                                    Text("1RM: \(Int(rm))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }.card()
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            history = (try? WorkoutService.fetchExerciseHistory(name: exerciseName)) ?? []
            pr = try? WorkoutService.fetchPR(for: exerciseName)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
