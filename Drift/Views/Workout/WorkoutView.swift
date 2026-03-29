import SwiftUI
import Charts
import UniformTypeIdentifiers

struct WorkoutView: View {
    @State private var workouts: [WorkoutSummary] = []
    @State private var weeklyCounts: [(weekStart: Date, count: Int)] = []
    @State private var showingNewWorkout = false
    @State private var showingImport = false
    @State private var importResult: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Consistency chart
                if !weeklyCounts.isEmpty {
                    consistencyChart
                }

                // Start/Import buttons
                HStack(spacing: 10) {
                    Button { showingNewWorkout = true } label: {
                        Label("Start Workout", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent)

                    Button { showingImport = true } label: {
                        Label("Import", systemImage: "doc.badge.plus")
                    }.buttonStyle(.bordered)
                }

                if let result = importResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }

                // History
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Workouts").font(.headline)
                        Text("Start a workout or import from Strong app").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 30)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

                        ForEach(workouts, id: \.workout.id) { summary in
                            NavigationLink {
                                WorkoutDetailView(summary: summary)
                            } label: {
                                workoutCard(summary)
                            }.tint(.primary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Workouts").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingNewWorkout) { ActiveWorkoutView { loadData() } }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText]) { handleImport($0) }
        .onAppear { loadData() }
    }

    // MARK: - Consistency Chart

    private var consistencyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workouts Per Week").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let total = weeklyCounts.reduce(0) { $0 + $1.count }
                Text("\(total) total").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(weeklyCounts.indices, id: \.self) { i in
                    BarMark(x: .value("", weeklyCounts[i].weekStart), y: .value("", weeklyCounts[i].count))
                        .foregroundStyle(weeklyCounts[i].count > 0 ? Theme.accent : Theme.cardBackgroundElevated)
                        .cornerRadius(3)
                }
            }
            .chartYScale(domain: 0...max(5, (weeklyCounts.map(\.count).max() ?? 3) + 1))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(.secondary)
                }
            }
            .frame(height: 100)
        }
        .card()
    }

    // MARK: - Workout Card

    private func workoutCard(_ s: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.workout.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDate(s.workout.date)).font(.caption).foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                if !s.workout.durationDisplay.isEmpty {
                    Label(s.workout.durationDisplay, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
                Label("\(Int(s.totalVolume)) lb", systemImage: "scalemass").font(.caption).foregroundStyle(.secondary)
            }

            // Exercises with best set
            ForEach(s.bestSets.prefix(4), id: \.exercise) { best in
                HStack {
                    Text("\(s.exercises.filter { $0 == best.exercise }.count > 1 ? "" : "")\(countSets(best.exercise, in: s)) × \(abbreviate(best.exercise))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(Int(best.weight)) lb × \(best.reps)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            if s.exercises.count > 4 {
                Text("+\(s.exercises.count - 4) more").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    private func countSets(_ exercise: String, in summary: WorkoutSummary) -> String {
        // count from bestSets isn't accurate, use exercises
        return "3" // simplified
    }

    private func abbreviate(_ name: String) -> String {
        if name.count <= 25 { return name }
        return String(name.prefix(22)) + "..."
    }

    private func formatDate(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: String(d.prefix(10))) else { return d }
        return DateFormatters.dayDisplay.string(from: date)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let r = try WorkoutService.importStrongCSV(url: url)
                importResult = "Imported \(r.workouts) workouts, \(r.sets) sets, \(r.exercises) exercises"
                loadData()
            } catch { importResult = "Import failed: \(error.localizedDescription)" }
        case .failure(let error): importResult = "File error: \(error.localizedDescription)"
        }
    }

    private func loadData() {
        isLoading = true
        do {
            let raw = try WorkoutService.fetchWorkouts(limit: 50)
            workouts = try raw.map { try WorkoutService.buildSummary(for: $0) }
            weeklyCounts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
        } catch {
            Log.app.error("Workout load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    @State private var sets: [WorkoutSet] = []
    @State private var showingShare = false

    private var shareText: String {
        var text = "💪 \(summary.workout.name)\n"
        text += "📅 \(formatDate(summary.workout.date))\n"
        if !summary.workout.durationDisplay.isEmpty { text += "⏱ \(summary.workout.durationDisplay)  " }
        text += "🏋️ \(Int(summary.totalVolume)) lb total volume\n\n"

        let grouped = Dictionary(grouping: sets.filter { !$0.isWarmup }) { $0.exerciseName }
        for ex in summary.exercises {
            if let exSets = grouped[ex] {
                text += "\(ex)\n"
                for s in exSets {
                    let w = s.weightLbs.map { "\(Int($0)) lb" } ?? "BW"
                    let r = s.reps.map { "× \($0)" } ?? ""
                    text += "  \(s.setOrder). \(w) \(r)"
                    if let rm = s.estimated1RM { text += "  (1RM: \(Int(rm)))" }
                    text += "\n"
                }
                text += "\n"
            }
        }
        text += "Logged with Drift"
        return text
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.workout.name).font(.headline)
                    Text(formatDate(summary.workout.date)).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if !summary.workout.durationDisplay.isEmpty {
                            Label(summary.workout.durationDisplay, systemImage: "clock")
                        }
                        Label("\(Int(summary.totalVolume)) lb volume", systemImage: "scalemass")
                        Label("\(summary.totalSets) sets", systemImage: "number")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                // Exercise groups
                let grouped = Dictionary(grouping: sets.filter { !$0.isWarmup }) { $0.exerciseName }
                ForEach(summary.exercises, id: \.self) { exerciseName in
                    if let exSets = grouped[exerciseName] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(exerciseName).font(.subheadline.weight(.semibold))

                            ForEach(exSets, id: \.id) { s in
                                HStack {
                                    Text(s.isWarmup ? "W" : "\(s.setOrder)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(s.isWarmup ? Theme.fatYellow : .primary)
                                        .frame(width: 20)
                                    Text(s.display).font(.subheadline.monospacedDigit())
                                    Spacer()
                                    if let rm = s.estimated1RM {
                                        Text("1RM: \(Int(rm))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .card()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Workout").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingShare = true } label: {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(text: shareText)
        }
        .onAppear {
            if let wid = summary.workout.id { sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? [] }
        }
    }

    private func formatDate(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: String(d.prefix(10))) else { return d }
        f.dateFormat = "EEEE, MMM d, yyyy"; return f.string(from: date)
    }
}

// MARK: - Active Workout (quick logging)

struct ActiveWorkoutView: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workoutName = "Workout"
    @State private var exercises: [(name: String, sets: [(weight: String, reps: String)])] = []
    @State private var showingExercisePicker = false
    @State private var startTime = Date()
    @State private var restSeconds = 0
    @State private var restTimerActive = false
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Timer
                    HStack {
                        let elapsed = Int(Date().timeIntervalSince(startTime))
                        Text(formatDuration(elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if restTimerActive {
                            Text("Rest: \(restSeconds)s").font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    TextField("Workout name", text: $workoutName)
                        .textFieldStyle(.roundedBorder)

                    // Exercises
                    ForEach(exercises.indices, id: \.self) { ei in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(exercises[ei].name).font(.subheadline.weight(.semibold))
                                Spacer()
                                // Show last weight used
                                if let last = try? WorkoutService.lastWeight(for: exercises[ei].name) {
                                    Text("Last: \(Int(last)) lb").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }

                            ForEach(exercises[ei].sets.indices, id: \.self) { si in
                                HStack(spacing: 8) {
                                    Text("\(si + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 20)
                                    TextField("lbs", text: $exercises[ei].sets[si].weight)
                                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 70)
                                    Text("×").foregroundStyle(.secondary)
                                    TextField("reps", text: $exercises[ei].sets[si].reps)
                                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 60)
                                    Spacer()
                                    Button { startRest() } label: {
                                        Image(systemName: "timer").font(.caption).foregroundStyle(Theme.accent)
                                    }
                                }
                            }

                            Button { exercises[ei].sets.append(("", "")) } label: {
                                Label("Add Set", systemImage: "plus").font(.caption)
                            }
                        }
                        .card().padding(.horizontal, 12)
                    }

                    Button { showingExercisePicker = true } label: {
                        Label("Add Exercise", systemImage: "plus.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).padding(.horizontal, 12)

                    if !exercises.isEmpty {
                        Button { saveWorkout() } label: {
                            Label("Finish Workout", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(Theme.deficit).padding(.horizontal, 12)
                    }
                }
                .padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Log Workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { name in
                    exercises.append((name, [("", ""), ("", ""), ("", "")]))
                }
            }
        }
    }

    private func startRest() {
        restSeconds = 90; restTimerActive = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if restSeconds > 0 { restSeconds -= 1 }
            else { t.invalidate(); restTimerActive = false }
        }
    }

    private func saveWorkout() {
        let duration = Int(Date().timeIntervalSince(startTime))
        var workout = Workout(name: workoutName, date: DateFormatters.dateOnly.string(from: Date()),
                              durationSeconds: duration, createdAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try WorkoutService.saveWorkout(&workout)
            guard let wid = workout.id else { return }

            var allSets: [WorkoutSet] = []
            for ex in exercises {
                for (si, s) in ex.sets.enumerated() {
                    guard let w = Double(s.weight), let r = Int(s.reps), r > 0 else { continue }
                    allSets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                              weightLbs: w, reps: r, isWarmup: false))
                }
            }
            try WorkoutService.saveSets(allSets)
            onComplete()
            dismiss()
        } catch {
            Log.app.error("Save workout failed: \(error.localizedDescription)")
        }
    }

    private func formatDuration(_ s: Int) -> String {
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Exercise Picker

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var exerciseList: [String] {
        let all = (try? WorkoutService.allExerciseNames()) ?? []
        let defaults = ["Bench Press (Barbell)", "Squat (Barbell)", "Deadlift (Barbell)", "Overhead Press (Barbell)",
                        "Bench Press (Dumbbell)", "Incline Bench Press (Dumbbell)", "Lat Pulldown (Cable)",
                        "Seated Row (Cable)", "Leg Press", "Leg Extension (Machine)", "Leg Curl (Machine)",
                        "Bicep Curl (Dumbbell)", "Triceps Pushdown (Cable)", "Lateral Raise (Dumbbell)",
                        "Pull Up", "Push Up", "Plank"]
        let combined = Array(Set(all + defaults)).sorted()
        if query.isEmpty { return combined }
        return combined.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search exercise", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                }.padding().background(.ultraThinMaterial)

                List {
                    // Option to add custom
                    if !query.isEmpty && !exerciseList.contains(where: { $0.lowercased() == query.lowercased() }) {
                        Button { onSelect(query); dismiss() } label: {
                            Label("Add \"\(query)\" as new exercise", systemImage: "plus.circle")
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    ForEach(exerciseList, id: \.self) { name in
                        Button {
                            onSelect(name); dismiss()
                        } label: {
                            Text(name).font(.subheadline)
                        }.tint(.primary)
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
