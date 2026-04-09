import SwiftUI
import Charts
import UniformTypeIdentifiers
import AudioToolbox

struct WorkoutView: View {
    @Binding var selectedTab: Int
    @State private var workouts: [WorkoutSummary] = []
    @State private var weeklyCounts: [(weekStart: Date, count: Int)] = []
    @State private var templates: [WorkoutTemplate] = []
    @State private var showingNewWorkout = false
    @State private var showingImport = false
    @State private var showingCreateTemplate = false
    @State private var showingExerciseBrowser = false
    @State private var importResult: String?
    @State private var showingImportAlert = false
    @State private var isLoading = true
    @State private var selectedTemplate: WorkoutTemplate? = nil
    @State private var previewTemplate: WorkoutTemplate? = nil
    @State private var editingTemplateForEdit: WorkoutTemplate? = nil
    @State private var renameTemplateId: Int64?
    @State private var renameTemplateName = ""
    @State private var showingRenameAlert = false
    @State private var deleteTemplateId: Int64?
    @State private var showingDeleteTemplate = false
    @State private var deleteWorkoutId: Int64?
    @State private var showingDeleteWorkout = false
    @State private var showingDeleteAllTemplates = false

    @State private var activeCalories: Double = 0
    @State private var steps: Double = 0
    @State private var showHistory = false
    @State private var healthWorkouts: [HealthKitService.HealthWorkout] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Active session banner
                if !showingNewWorkout && WorkoutService.hasActiveSession {
                    Button { showingNewWorkout = true } label: {
                        HStack {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .foregroundStyle(.white)
                            Text("Workout in progress").font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("Resume").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }

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

                // Apple Health Workouts (last 7 days)
                if !healthWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.heartRed)
                            Text("Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(healthWorkouts.count) this week").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        }

                        ForEach(healthWorkouts.prefix(5)) { w in
                            HStack(spacing: 10) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.caption).foregroundStyle(Theme.stepsOrange)
                                    .frame(width: 28, height: 28)
                                    .background(Theme.stepsOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(w.type).font(.caption.weight(.semibold))
                                    Text(DateFormatters.dayDisplay.string(from: w.date))
                                        .font(.caption2).foregroundStyle(.quaternary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(w.durationDisplay).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    Text("\(Int(w.calories)) cal").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .card()
                }

                // Body recovery map
                BodyMapView { template in
                    WorkoutService.clearSession()
                    selectedTemplate = template
                    showingNewWorkout = true
                }

                if !weeklyCounts.isEmpty {
                    // Streak display
                    if let streak = try? WorkoutService.workoutStreak(), streak.current > 0 {
                        HStack {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                            Text("\(streak.current) week streak")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Best: \(streak.longest)w")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                    consistencyChart
                }

                // Start buttons
                HStack(spacing: 10) {
                    Button {
                        WorkoutService.clearSession()
                        selectedTemplate = nil
                        showingNewWorkout = true
                    } label: {
                        Label("Empty Workout", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent)

                    Button {
                        if let smart = ExerciseService.buildSmartSession() {
                            selectedTemplate = smart
                            showingNewWorkout = true
                        }
                    } label: {
                        Label("Coach Me", systemImage: "brain.head.profile").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.7))
                }

                // Templates
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Templates").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !templates.isEmpty {
                            Text("\(templates.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        Menu {
                            Button { showingCreateTemplate = true } label: {
                                Label("New Template", systemImage: "plus")
                            }
                            Button { showingImport = true } label: {
                                Label("Import from Strong / Hevy", systemImage: "square.and.arrow.down")
                            }
                            Button {
                                let added = DefaultTemplates.loadCurated()
                                importResult = "Added \(added) Drift Curated templates"
                                showingImportAlert = true
                                loadData()
                            } label: {
                                Label("Load Drift Curated", systemImage: "star")
                            }
                            if !templates.isEmpty {
                                Divider()
                                Button(role: .destructive) {
                                    showingDeleteAllTemplates = true
                                } label: {
                                    Label("Remove All Templates", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.body).foregroundStyle(Theme.accent)
                        }
                    }

                    if templates.isEmpty {
                        VStack(spacing: 12) {
                            Text("No templates yet").font(.caption).foregroundStyle(.tertiary)
                            HStack(spacing: 12) {
                                Button { showingImport = true } label: {
                                    Label("Import", systemImage: "square.and.arrow.down").font(.caption)
                                }.buttonStyle(.bordered)
                                Button {
                                    let added = DefaultTemplates.loadCurated()
                                    importResult = "Added \(added) Drift Curated templates"
                                    showingImportAlert = true
                                    loadData()
                                } label: {
                                    Label("Drift Curated", systemImage: "star").font(.caption)
                                }.buttonStyle(.bordered).tint(Theme.accent)
                            }
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(templates) { t in
                                    Button {
                                        previewTemplate = t
                                    } label: {
                                        HStack(spacing: 8) {
                                            if t.isFavorite {
                                                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.fatYellow)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(t.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                                let working = t.exercises.filter { !$0.isWarmup }
                                                let warmups = t.exercises.filter { $0.isWarmup }
                                                Text("\(working.count) exercises\(warmups.isEmpty ? "" : " · \(warmups.count) warmup")")
                                                    .font(.caption2).foregroundStyle(.tertiary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: min(CGFloat(templates.count) * 50, 250))
                    }
                }
                .card()

                // Browse exercises
                Button { showingExerciseBrowser = true } label: {
                    Label("Browse Exercises", systemImage: "dumbbell").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)

                // History — collapsible
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Workouts Yet").font(.headline)
                        Text("Start a workout above, or import your history").font(.caption).foregroundStyle(.secondary)
                        Button { showingImport = true } label: {
                            Label("Import from Strong / Hevy", systemImage: "square.and.arrow.down")
                                .font(.caption)
                        }.buttonStyle(.bordered)
                    }.padding(.top, 30)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                Text("History")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(workouts.count) workouts")
                                    .font(.caption).foregroundStyle(.tertiary)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .rotationEffect(.degrees(showHistory ? 0 : -90))
                            }
                            .card()
                        }
                        .buttonStyle(.plain)

                        if showHistory {
                            ForEach(workouts, id: \.workout.id) { s in
                                NavigationLink { WorkoutDetailView(summary: s) { loadData() } } label: { workoutCard(s) }.tint(.primary)
                                    .contextMenu {
                                        if let wid = s.workout.id {
                                            Button(role: .destructive) {
                                                deleteWorkoutId = wid
                                                showingDeleteWorkout = true
                                            } label: { Label("Delete Workout", systemImage: "trash") }
                                        }
                                    }
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { selectedTab = 0 } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingNewWorkout) {
            ActiveWorkoutView(template: selectedTemplate) {
                selectedTemplate = nil
                loadData()
            }
        }
        .sheet(isPresented: $showingCreateTemplate) {
            CreateTemplateView { loadData() }
        }
        .sheet(item: $editingTemplateForEdit) { template in
            CreateTemplateView(existingTemplate: template) { loadData() }
        }
        .sheet(isPresented: $showingExerciseBrowser) {
            ExerciseBrowserView()
        }
        .sheet(item: $previewTemplate) { t in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        let warmups = t.exercises.filter(\.isWarmup)
                        let working = t.exercises.filter { !$0.isWarmup }

                        if !warmups.isEmpty {
                            Text("WARMUP").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                            ForEach(Array(warmups.enumerated()), id: \.offset) { _, ex in
                                NavigationLink {
                                    ExerciseDetailView(exerciseName: ex.name, info: ExerciseDatabase.info(for: ex.name))
                                } label: {
                                    HStack {
                                        Text("W").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                                            .padding(.horizontal, 3).padding(.vertical, 1)
                                            .background(Theme.fatYellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(ex.name).font(.subheadline)
                                            if let notes = ex.notes { Text(notes).font(.caption2).foregroundStyle(.secondary).italic() }
                                        }
                                        Spacer()
                                        Text("\(ex.sets) sets").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }.tint(.primary)
                            }
                            Divider().padding(.vertical, 4)
                        }

                        if !working.isEmpty {
                            Text("EXERCISES").font(.caption2.weight(.bold)).foregroundStyle(Theme.calorieBlue)
                            ForEach(Array(working.enumerated()), id: \.offset) { i, ex in
                                NavigationLink {
                                    ExerciseDetailView(exerciseName: ex.name, info: ExerciseDatabase.info(for: ex.name))
                                } label: {
                                    HStack {
                                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(ex.name).font(.subheadline)
                                            HStack(spacing: 4) {
                                                Text("\(ex.sets) sets").font(.caption2).foregroundStyle(.tertiary)
                                                if let lastW = try? WorkoutService.lastWeight(for: ex.name) {
                                                    Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                                                    Text("\(Int(lastW)) lb").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                                }
                                                if let notes = ex.notes {
                                                    Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                                                    Text(notes).font(.caption2).foregroundStyle(.secondary).italic()
                                                }
                                            }
                                        }
                                        Spacer()
                                        Text("\(ex.restSeconds/60):\(String(format: "%02d", ex.restSeconds%60))")
                                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                }.tint(.primary)
                            }
                        }

                        // Actions
                        VStack(spacing: 10) {
                            Button {
                                let template = t
                                previewTemplate = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    WorkoutService.clearSession()
                                    selectedTemplate = template
                                    showingNewWorkout = true
                                }
                            } label: {
                                Label("Start Workout", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)

                            HStack(spacing: 12) {
                                Button {
                                    let template = t
                                    previewTemplate = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        editingTemplateForEdit = template
                                    }
                                } label: {
                                    Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered)

                                Button {
                                    if let tid = t.id {
                                        try? WorkoutService.toggleFavorite(id: tid)
                                        previewTemplate = nil
                                        loadData()
                                    }
                                } label: {
                                    Label(t.isFavorite ? "Unfavorite" : "Favorite",
                                          systemImage: t.isFavorite ? "star.slash" : "star")
                                        .frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered).tint(Theme.fatYellow)
                            }

                            Button(role: .destructive) {
                                if let tid = t.id {
                                    try? AppDatabase.shared.writer.write { db in _ = try WorkoutTemplate.deleteOne(db, id: tid) }
                                    previewTemplate = nil
                                    loadData()
                                }
                            } label: {
                                Label("Delete Template", systemImage: "trash").font(.caption)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                }
                .background(Theme.background)
                .navigationTitle(t.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { previewTemplate = nil } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText]) { handleImport($0) }
        .alert("Rename Template", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameTemplateName)
            Button("Save") {
                if let tid = renameTemplateId {
                    try? AppDatabase.shared.writer.write { db in
                        try db.execute(sql: "UPDATE workout_template SET name = ? WHERE id = ?",
                                       arguments: [renameTemplateName, tid])
                    }
                    loadData()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove All Templates?", isPresented: $showingDeleteAllTemplates) {
            Button("Remove All", role: .destructive) {
                for t in templates {
                    if let tid = t.id {
                        try? AppDatabase.shared.writer.write { db in _ = try WorkoutTemplate.deleteOne(db, id: tid) }
                    }
                }
                loadData()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All \(templates.count) templates will be permanently deleted.") }
        .alert("Delete Template?", isPresented: $showingDeleteTemplate) {
            Button("Delete", role: .destructive) {
                if let tid = deleteTemplateId {
                    try? AppDatabase.shared.writer.write { db in _ = try WorkoutTemplate.deleteOne(db, id: tid) }
                    loadData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This template will be permanently deleted.") }
        .alert("Delete Workout?", isPresented: $showingDeleteWorkout) {
            Button("Delete", role: .destructive) {
                if let wid = deleteWorkoutId {
                    try? WorkoutService.deleteWorkout(id: wid)
                    loadData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This workout and all its sets will be permanently deleted.") }
        .alert("Import", isPresented: $showingImportAlert) {
            Button("OK") {}
        } message: {
            Text(importResult ?? "Done")
        }
        .onAppear { AIScreenTracker.shared.currentScreen = .exercise; loadData() }
        .onChange(of: showingNewWorkout) { _, showing in if !showing { loadData() } }
        .onChange(of: showingCreateTemplate) { _, showing in if !showing { loadData() } }
        .task {
            // Initial fetch
            await refreshHealthData()
            // Auto-refresh every 3 minutes while on this tab
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))
                await refreshHealthData()
            }
        }
    }

    private func refreshHealthData() async {
        let hk = HealthKitService.shared
        activeCalories = (try? await hk.fetchCaloriesBurned(for: Date()).active) ?? 0
        steps = (try? await hk.fetchSteps(for: Date())) ?? 0
        healthWorkouts = (try? await hk.fetchRecentWorkouts(days: 7)) ?? []
    }

    private var consistencyChart: some View {
        let total = weeklyCounts.reduce(0) { $0 + $1.count }
        let thisWeek = weeklyCounts.first?.count ?? 0

        return HStack(spacing: 12) {
            // This week
            VStack(spacing: 2) {
                Text("\(thisWeek)").font(.title2.weight(.bold).monospacedDigit())
                Text("this week").font(.caption2).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity)

            Divider().frame(height: 28)

            // Total
            VStack(spacing: 2) {
                Text("\(total)").font(.title2.weight(.bold).monospacedDigit())
                Text("in 12 wks").font(.caption2).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity)
        }
        .card()
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
                Label("\(s.exercises.count) exercises", systemImage: "dumbbell").font(.caption).foregroundStyle(.secondary)
            }
            if let notes = s.workout.notes, !notes.isEmpty {
                Text(notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
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
        case .success(let url):
            do {
                let r = try WorkoutService.importStrongCSV(url: url)
                importResult = "Imported \(r.workouts) workouts, \(r.sets) sets"
                showingImportAlert = true
                loadData()
            } catch {
                importResult = "Failed: \(error.localizedDescription)"
                showingImportAlert = true
            }
        case .failure(let error):
            importResult = "Error: \(error.localizedDescription)"
            showingImportAlert = true
        }
    }
    private func loadData() {
        isLoading = true
        // Load independently so one failure doesn't block the others
        do {
            let raw = try WorkoutService.fetchWorkouts(limit: 500)
            workouts = try raw.map { try WorkoutService.buildSummary(for: $0) }
        } catch { Log.app.error("Workout load: \(error.localizedDescription)") }
        do {
            weeklyCounts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
        } catch { Log.app.error("Weekly counts: \(error.localizedDescription)") }
        do {
            templates = try WorkoutService.fetchTemplates()
        } catch { Log.app.error("Templates load: \(error.localizedDescription)") }
        isLoading = false
    }
}

// MARK: - Create Template

struct CreateTemplateView: View {
    var existingTemplate: WorkoutTemplate? = nil
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

                let warmupIndices = exercises.indices.filter { exercises[$0].isWarmup }
                let workingIndices = exercises.indices.filter { !exercises[$0].isWarmup }

                if !warmupIndices.isEmpty {
                    Section("Warmup (\(warmupIndices.count))") {
                        ForEach(warmupIndices, id: \.self) { i in
                            templateExerciseRow(i)
                        }
                        .onDelete { offsets in
                            let toRemove = offsets.map { warmupIndices[$0] }
                            exercises.remove(atOffsets: IndexSet(toRemove))
                        }
                        Button { addingWarmup = true; showingPicker = true } label: {
                            Label("Add Warmup", systemImage: "plus.circle").foregroundStyle(Theme.fatYellow)
                        }
                    }
                }

                Section(warmupIndices.isEmpty ? "Exercises" : "Working Sets (\(workingIndices.count))") {
                    ForEach(workingIndices, id: \.self) { i in
                        templateExerciseRow(i)
                    }
                    .onDelete { offsets in
                        let toRemove = offsets.map { workingIndices[$0] }
                        exercises.remove(atOffsets: IndexSet(toRemove))
                    }
                    Button { addingWarmup = false; showingPicker = true } label: {
                        Label("Add Exercise", systemImage: "plus.circle").foregroundStyle(Theme.accent)
                    }
                    if warmupIndices.isEmpty {
                        Button { addingWarmup = true; showingPicker = true } label: {
                            Label("Add Warmup Exercise", systemImage: "plus.circle").foregroundStyle(Theme.fatYellow)
                        }
                    }
                }

                Section {
                    Button {
                        if let json = try? JSONEncoder().encode(exercises), let jsonStr = String(data: json, encoding: .utf8) {
                            if let existing = existingTemplate, let id = existing.id {
                                // Update existing template
                                try? AppDatabase.shared.writer.write { db in
                                    try db.execute(sql: "UPDATE workout_template SET name = ?, exercises_json = ? WHERE id = ?",
                                                   arguments: [name.isEmpty ? "Template" : name, jsonStr, id])
                                }
                            } else {
                                // Create new
                                var t = WorkoutTemplate(name: name.isEmpty ? "Template" : name, exercisesJson: jsonStr, createdAt: ISO8601DateFormatter().string(from: Date()))
                                try? WorkoutService.saveTemplate(&t)
                            }
                        }
                        onSave(); dismiss()
                    } label: {
                        Label(existingTemplate != nil ? "Update Template" : "Save Template", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(exercises.isEmpty)
                }
            }
            .navigationTitle(existingTemplate != nil ? "Edit Template" : "New Template").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let t = existingTemplate {
                    name = t.name
                    exercises = t.exercises
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exName in
                    exercises.append(.init(name: exName, sets: addingWarmup ? 2 : 3, isWarmup: addingWarmup,
                                           restSeconds: addingWarmup ? 30 : 90))
                }
            }
            .sheet(item: editingBinding) { idx in
                if idx.value < exercises.count {
                    TemplateExerciseEditor(exercise: exercises[idx.value]) { updated in
                        if idx.value < exercises.count { exercises[idx.value] = updated }
                    }
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
        var list = query.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: query)
        if let part = selectedPart { list = list.filter { $0.bodyPart == part } }
        let favs = WorkoutService.exerciseFavorites
        list.sort { favs.contains($0.name) && !favs.contains($1.name) }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
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
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Exercise info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exerciseName).font(.title3.weight(.bold))
                        Spacer()
                        Button {
                            WorkoutService.toggleExerciseFavorite(exerciseName)
                            isFavorite.toggle()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(isFavorite ? Theme.fatYellow : Color.gray.opacity(0.4))
                        }
                    }

                    if let info {
                        // Tags row
                        HStack(spacing: 6) {
                            detailTag(info.bodyPart, icon: "figure.strengthtraining.traditional", color: Theme.accent)
                            detailTag(info.equipment, icon: "wrench.and.screwdriver", color: .secondary)
                            detailTag(info.level.capitalized, icon: "chart.bar", color: .secondary)
                        }

                        // Muscles
                        if !info.primaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Primary muscles").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                Text(info.primaryMuscles.map(\.capitalized).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.primary)
                            }
                        }
                        if !info.secondaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Secondary muscles").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                Text(info.secondaryMuscles.map(\.capitalized).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
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
            isFavorite = WorkoutService.exerciseFavorites.contains(exerciseName)
            history = (try? WorkoutService.fetchExerciseHistory(name: exerciseName)) ?? []
            pr = try? WorkoutService.fetchPR(for: exerciseName)
        }
    }

    private func detailTag(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var text: String = ""
    var items: [Any]?
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items ?? [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
