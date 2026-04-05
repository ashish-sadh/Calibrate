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

                if !weeklyCounts.isEmpty { consistencyChart }

                // Start buttons
                Button {
                    WorkoutService.clearSession()
                    selectedTemplate = nil
                    showingNewWorkout = true
                } label: {
                    Label("Start Empty Workout", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)

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
                .card()

                // Browse exercises
                Button { showingExerciseBrowser = true } label: {
                    Label("Browse Exercises", systemImage: "dumbbell").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)

                // History — collapsible
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Workouts").font(.headline)
                        Text("Start a workout or import from Strong / Hevy").font(.caption).foregroundStyle(.secondary)
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
        .onAppear { loadData() }
        .onChange(of: showingNewWorkout) { _, showing in if !showing { loadData() } }
        .onChange(of: showingCreateTemplate) { _, showing in if !showing { loadData() } }
        .task {
            let hk = HealthKitService.shared
            activeCalories = (try? await hk.fetchCaloriesBurned(for: Date()).active) ?? 0
            steps = (try? await hk.fetchSteps(for: Date())) ?? 0
            healthWorkouts = (try? await hk.fetchRecentWorkouts(days: 7)) ?? []
        }
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
            let raw = try WorkoutService.fetchWorkouts(limit: 50)
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

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var sets: [WorkoutSet] = []
    @State private var showingShare = false
    @State private var showingSaveTemplate = false
    @State private var showingDeleteConfirm = false
    @State private var saveTemplateName = ""

    private var shareText: String {
        var t = "💪 \(summary.workout.name)\n📅 \(formatDate(summary.workout.date))\n"
        if !summary.workout.durationDisplay.isEmpty { t += "⏱ \(summary.workout.durationDisplay)  " }
        t += "🏋️ \(Int(summary.totalVolume)) lb\n"
        if let notes = summary.workout.notes, !notes.isEmpty { t += "📝 \(notes)\n" }
        t += "\n"
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
                    if let notes = summary.workout.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(.tertiary).italic()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).card()

                let grouped = Dictionary(grouping: sets) { $0.exerciseName }
                ForEach(summary.exercises, id: \.self) { ex in
                    if let exSets = grouped[ex] {
                        let workingSets = exSets.filter { !$0.isWarmup }
                        let exVolume = workingSets.reduce(0.0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ex).font(.subheadline.weight(.semibold))
                                Spacer()
                                if exVolume > 0 {
                                    Text("\(Int(exVolume)) lb").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
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
                    Button { saveTemplateName = summary.workout.name; showingSaveTemplate = true } label: { Label("Save as Template", systemImage: "doc.on.doc") }
                    if summary.workout.id != nil {
                        Divider()
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: { Label("Delete Workout", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.accent) }
            }
        }
        .alert("Delete Workout?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let wid = summary.workout.id {
                    try? WorkoutService.deleteWorkout(id: wid)
                    onDelete?()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This workout and all its sets will be permanently deleted.") }
        .sheet(isPresented: $showingShare) { ShareSheet(text: shareText) }
        .alert("Save as Template", isPresented: $showingSaveTemplate) {
            TextField("Template name", text: $saveTemplateName)
            Button("Save") { saveAsTemplate(name: saveTemplateName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this template")
        }
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

    private func saveAsTemplate(name: String? = nil) {
        // Determine warmup vs working from the saved sets
        let warmupNames = Set(sets.filter(\.isWarmup).map(\.exerciseName))
        let exercises = summary.exercises.map { name in
            let isW = warmupNames.contains(name)
            let count = sets.filter { $0.exerciseName == name && !$0.isWarmup }.count
            return WorkoutTemplate.TemplateExercise(name: name, sets: max(count, isW ? 2 : 3), isWarmup: isW,
                                                    restSeconds: isW ? 30 : 90)
        }
        if let json = try? JSONEncoder().encode(exercises), let jsonStr = String(data: json, encoding: .utf8) {
            let templateName = (name?.isEmpty ?? true) ? summary.workout.name : name!
            var t = WorkoutTemplate(name: templateName, exercisesJson: jsonStr, createdAt: ISO8601DateFormatter().string(from: Date()))
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
    @Environment(\.scenePhase) private var scenePhase
    var template: WorkoutTemplate? = nil
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workoutName = defaultWorkoutName()
    @State private var workoutNotes = ""
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
    @State private var restEndTime: Date?
    @State private var activeRestExerciseIndex: Int? = nil
    @State private var activeRestSetIndex: Int? = nil
    @State private var workoutEnded = false  // prevents re-persisting after finish/cancel
    @State private var showingFinishOptions = false
    @State private var templateName = ""
    @State private var showingTemplateName = false
    @State private var saveAsTemplateToggle = false
    @State private var favoriteAllToggle = false
    @State private var showingCompletionSheet = false
    @State private var completionShareText = ""
    @State private var completionMilestone: String? = nil

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

                    // Notes (collapsed by default)
                    if !workoutNotes.isEmpty || exercises.count > 0 {
                        TextField("Workout notes...", text: $workoutNotes, axis: .vertical)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1...3)
                            .padding(.horizontal, 16)
                    }

                    // Quick add exercise at top (useful when template already has many)
                    if exercises.count >= 3 {
                        Button { showingExercisePicker = true } label: {
                            Label("Add Exercise", systemImage: "plus.circle").font(.caption)
                        }.buttonStyle(.bordered).tint(Theme.accent).padding(.horizontal, 12)
                    }

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
                        Button { showingFinishOptions = true } label: {
                            Text("Finish").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(Theme.deficit).padding(.horizontal, 12)

                        Button("Cancel Workout", role: .destructive) {
                            workoutEnded = true
                            WorkoutService.clearSession(); stopTimers(); dismiss()
                        }.font(.caption).padding(.top, 4)
                    }
                }.padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Minimize (keep running)") { persistSession(); dismiss() }
                        Button("Cancel Workout", role: .destructive) {
                            workoutEnded = true
                            WorkoutService.clearSession(); stopTimers(); dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !exercises.isEmpty {
                        Button("Finish") { showingFinishOptions = true }.foregroundStyle(Theme.deficit)
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { name in
                    addExercise(name: name)
                }
            }
            .sheet(isPresented: $showingFinishOptions) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.deficit)
                            .padding(.top, 24)

                        Text("Nice work!").font(.title2.weight(.bold))

                        // Workout summary
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text(formatDuration(elapsedSeconds)).font(.title3.weight(.bold).monospacedDigit())
                                Text("Duration").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Divider().frame(height: 28)
                            VStack(spacing: 2) {
                                Text("\(exercises.count)").font(.title3.weight(.bold).monospacedDigit())
                                Text("Exercises").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Divider().frame(height: 28)
                            VStack(spacing: 2) {
                                let totalSets = exercises.flatMap(\.sets).filter(\.done).count
                                Text("\(totalSets)").font(.title3.weight(.bold).monospacedDigit())
                                Text("Sets").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .card()

                        // Save as template toggle
                        Toggle(isOn: $saveAsTemplateToggle) {
                            Label("Save as template", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .tint(Theme.accent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))

                        // Favorite all exercises toggle
                        Toggle(isOn: $favoriteAllToggle) {
                            Label("Favorite all exercises", systemImage: "star")
                                .font(.subheadline)
                        }
                        .tint(Theme.fatYellow)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))

                        if saveAsTemplateToggle {
                            TextField("Template name", text: $templateName)
                                .font(.subheadline)
                                .padding(12)
                                .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))
                        }

                        Spacer()

                        Button {
                            showingFinishOptions = false
                            if favoriteAllToggle {
                                for ex in exercises where !ex.isWarmupExercise {
                                    if !WorkoutService.exerciseFavorites.contains(ex.name) {
                                        WorkoutService.toggleExerciseFavorite(ex.name)
                                    }
                                }
                            }
                            saveWorkout(andDismiss: !saveAsTemplateToggle)
                            if saveAsTemplateToggle {
                                saveAsTemplate(name: templateName.isEmpty ? workoutName : templateName)
                                onComplete(); dismiss()
                            }
                        } label: {
                            Text("Save Workout").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.deficit)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.background)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { showingFinishOptions = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingCompletionSheet) {
                // Dismiss everything when completion sheet closes
                onComplete(); dismiss()
            } content: {
                VStack(spacing: 20) {
                    if let milestone = completionMilestone {
                        Text("🎉").font(.system(size: 48))
                        Text(milestone).font(.title2.weight(.bold))
                    } else {
                        Text("💪").font(.system(size: 48))
                        Text("Workout Complete").font(.title2.weight(.bold))
                    }

                    Text(completionShareText)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let root = scene.windows.first?.rootViewController else { return }
                        let vc = UIActivityViewController(activityItems: [completionShareText], applicationActivities: nil)
                        root.present(vc, animated: true)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button("Done") { showingCompletionSheet = false }
                        .buttonStyle(.borderedProminent).tint(Theme.deficit)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
                .presentationDetents([.medium])
                .background(Theme.background)
            }
            .onAppear {
                // Restore session BEFORE starting timer so startTime is correct
                let restored = restoreSession()
                startWorkoutTimer()
                if restored { return }
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
            .onDisappear {
                stopTimers()
                // Only persist if workout wasn't finished or cancelled
                if !workoutEnded && !exercises.isEmpty { persistSession() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && !workoutEnded {
                    // Restart workout timer — elapsed recalculates from startTime
                    workoutTimer?.invalidate()
                    elapsedSeconds = Int(Date().timeIntervalSince(startTime))
                    startWorkoutTimer()
                    // Update rest timer from wall-clock end time
                    if restTimerActive, let endTime = restEndTime {
                        let remaining = Int(endTime.timeIntervalSince(Date()))
                        if remaining > 0 {
                            restSeconds = remaining
                            restTimer?.invalidate()
                            startRestTimerTick()
                        } else {
                            // Rest finished while in background
                            restSeconds = 0
                            restTimer?.invalidate()
                            restTimerActive = false
                            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                        }
                    }
                }
            }
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
                NavigationLink {
                    ExerciseDetailView(exerciseName: exercises[ei].name, info: ExerciseDatabase.info(for: exercises[ei].name))
                } label: {
                    Text(exercises[ei].name).font(.subheadline.weight(.bold))
                        .foregroundStyle(exercises[ei].isWarmupExercise ? Theme.fatYellow : Theme.calorieBlue)
                }
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
                Menu {
                    let name = exercises[ei].name
                    let isFav = WorkoutService.exerciseFavorites.contains(name)
                    Button {
                        WorkoutService.toggleExerciseFavorite(name)
                    } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive) { exercises.remove(at: ei) } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(.tertiary)
                }
            }

            // Notes (editable - pre-filled from template)
            TextField("Notes...", text: Binding(
                get: { exercises[ei].notes ?? "" },
                set: { exercises[ei].notes = $0.isEmpty ? nil : $0 }
            ))
            .font(.caption2).foregroundStyle(.secondary).italic()

            // Column headers
            let assisted = isAssistedExercise(exercises[ei].name)
            HStack(spacing: 0) {
                Text("Set").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 28, alignment: .leading)
                Text("Previous").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 85, alignment: .leading)
                Text(assisted ? "-lbs" : "lbs").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 55)
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
                                // Auto-add next set prefilled with same weight/reps (copy to next)
                                if si == exercises[ei].sets.count - 1 {
                                    let s = exercises[ei].sets[si]
                                    if !s.weight.isEmpty || !s.reps.isEmpty {
                                        exercises[ei].sets.append(ActiveSet(weight: s.weight, reps: s.reps))
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: exercises[ei].sets[si].done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(exercises[ei].sets[si].done ? Theme.deficit : .secondary)
                        }.frame(width: 30)

                        // Inline delete button
                        Button {
                            exercises[ei].sets.remove(at: si)
                            if exercises[ei].sets.isEmpty { exercises.remove(at: ei) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.quaternary)
                        }.frame(width: 20)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button(role: .destructive) {
                            exercises[ei].sets.remove(at: si)
                            if exercises[ei].sets.isEmpty {
                                exercises.remove(at: ei)
                            }
                        } label: {
                            Label("Delete Set", systemImage: "trash")
                        }
                    }

                    // Inline rest timer bar (shows after this set if active)
                    if restTimerActive && activeRestExerciseIndex == ei && activeRestSetIndex == si {
                        restTimerBar
                    }
                }
            }

            // Add set button — prefills from last set
            Button {
                let last = exercises[ei].sets.last
                exercises[ei].sets.append(ActiveSet(weight: last?.weight ?? "", reps: last?.reps ?? ""))
            } label: {
                Text("+ Set")
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

    private func isAssistedExercise(_ name: String) -> Bool {
        let e = name.lowercased()
        return e.contains("assisted") || e.contains("assist")
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
                // Auto-save session every 30 seconds
                if elapsedSeconds % 30 == 0 && !exercises.isEmpty {
                    persistSession()
                }
            }
        }
    }

    private func startRest(exerciseIndex: Int, setIndex: Int, duration: Int) {
        restTotalSeconds = duration
        restSeconds = duration
        restEndTime = Date().addingTimeInterval(Double(duration))
        activeRestExerciseIndex = exerciseIndex
        activeRestSetIndex = setIndex
        restTimerActive = true
        restTimer?.invalidate()
        startRestTimerTick()
    }

    private func startRestTimerTick() {
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard let endTime = restEndTime else { return }
                let remaining = Int(ceil(endTime.timeIntervalSince(Date())))
                if remaining > 0 {
                    restSeconds = remaining
                } else {
                    restSeconds = 0
                    restTimer?.invalidate()
                    restTimerActive = false
                    restEndTime = nil
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }

    private func stopTimers() { workoutTimer?.invalidate(); restTimer?.invalidate() }

    // MARK: - Session Persistence

    private func persistSession() {
        let sessionExercises = exercises.map { ex in
            WorkoutService.SavedSession.SessionExercise(
                name: ex.name, isWarmup: ex.isWarmupExercise,
                notes: ex.notes, restTime: ex.restTime,
                sets: ex.sets.map { s in
                    WorkoutService.SavedSession.SessionSet(
                        weight: s.weight, reps: s.reps, done: s.done, isWarmup: s.isWarmup)
                })
        }
        WorkoutService.saveSession(.init(workoutName: workoutName, startTime: startTime, exercises: sessionExercises))
    }

    private func restoreSession() -> Bool {
        guard let session = WorkoutService.loadSession() else { return false }
        workoutName = session.workoutName
        startTime = session.startTime
        exercises = session.exercises.map { ex in
            ActiveExercise(
                name: ex.name, restTime: ex.restTime, isWarmupExercise: ex.isWarmup,
                notes: ex.notes,
                sets: ex.sets.map { s in ActiveSet(weight: s.weight, reps: s.reps, done: s.done, isWarmup: s.isWarmup) },
                previousSets: [])
        }
        return true
    }

    // MARK: - Add Exercise (with prefill)

    private func addExercise(name: String, setCount: Int? = nil, restTime: Int = 90, isWarmup: Bool = false, notes: String? = nil) {
        let allHistory = (try? WorkoutService.fetchExerciseHistory(name: name)) ?? []

        // Get the most recent workout's sets for this exercise (in set_order)
        // History is ordered by id DESC, so first entry is from most recent workout
        let lastWorkoutId = allHistory.first?.workoutId
        let lastSession = lastWorkoutId.map { wid in
            allHistory.filter { $0.workoutId == wid }.sorted { $0.setOrder < $1.setOrder }
        } ?? []

        let previous = lastSession.prefix(5).map { s in
            "\(Int(s.weightLbs ?? 0)) lb \u{00D7} \(s.reps ?? 0)"
        }

        let count = setCount ?? (lastSession.isEmpty ? 3 : max(lastSession.count, 3))
        var sets: [ActiveSet] = []
        for i in 0..<count {
            if i < lastSession.count {
                let s = lastSession[i]
                sets.append(ActiveSet(weight: s.weightLbs.map { String(Int($0)) } ?? "",
                                      reps: s.reps.map { String($0) } ?? "", isWarmup: isWarmup))
            } else {
                sets.append(ActiveSet(weight: "", reps: "", isWarmup: isWarmup))
            }
        }

        exercises.append(ActiveExercise(name: name, restTime: restTime, isWarmupExercise: isWarmup,
                                         notes: notes, sets: sets, previousSets: Array(previous)))
    }

    private func saveWorkout(andDismiss: Bool = true) {
        workoutEnded = true
        stopTimers()
        WorkoutService.clearSession()
        var workout = Workout(name: workoutName, date: DateFormatters.dateOnly.string(from: Date()),
                              durationSeconds: elapsedSeconds, notes: workoutNotes.isEmpty ? nil : workoutNotes,
                              createdAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try WorkoutService.saveWorkout(&workout)
            guard let wid = workout.id else {
                Log.app.error("Save workout: no ID after save")
                return
            }
            var allSets: [WorkoutSet] = []
            for (ei, ex) in exercises.enumerated() {
                let isDuration = WorkoutSet.isDurationExercise(ex.name)
                for (si, s) in ex.sets.enumerated() where s.done {
                    let w = Double(s.weight) ?? 0
                    let r = Int(s.reps) ?? 0
                    let dur = isDuration ? (Int(s.reps) ?? 0) : nil // duration exercises store seconds in reps field
                    guard r > 0 || (isDuration && (dur ?? 0) > 0) else { continue }
                    allSets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                             weightLbs: w > 0 ? w : nil, reps: isDuration ? nil : r,
                                             isWarmup: s.isWarmup || ex.isWarmupExercise,
                                             durationSec: dur, exerciseOrder: ei))
                }
            }
            if allSets.isEmpty {
                for (ei, ex) in exercises.enumerated() {
                    let isDuration = WorkoutSet.isDurationExercise(ex.name)
                    for (si, s) in ex.sets.enumerated() {
                        let w = Double(s.weight) ?? 0
                        let r = Int(s.reps) ?? 0
                        let dur = isDuration ? (Int(s.reps) ?? 0) : nil
                        guard r > 0 || (isDuration && (dur ?? 0) > 0) else { continue }
                        allSets.append(WorkoutSet(workoutId: wid, exerciseName: ex.name, setOrder: si + 1,
                                                 weightLbs: w > 0 ? w : nil, reps: isDuration ? nil : r,
                                                 isWarmup: s.isWarmup || ex.isWarmupExercise,
                                                 durationSec: dur, exerciseOrder: ei))
                    }
                }
            }
            try WorkoutService.saveSets(allSets)
            if andDismiss {
                // Build completion share text + check milestones
                let totalVol = allSets.reduce(0.0) { $0 + (($1.weightLbs ?? 0) * Double($1.reps ?? 0)) }
                let exerciseNames = exercises.map(\.name).filter { !$0.isEmpty }
                let duration = workout.durationDisplay
                var shareLines = ["💪 \(workout.name)"]
                if !duration.isEmpty { shareLines.append("⏱ \(duration)") }
                shareLines.append("🏋️ \(Int(totalVol)) lb total volume")
                shareLines.append("\(exerciseNames.count) exercises · \(allSets.count) sets")
                completionShareText = shareLines.joined(separator: "\n")

                // Check milestone
                if let count = try? WorkoutService.totalWorkoutCount() {
                    let milestones = [1, 5, 10, 25, 50, 100, 150, 200, 250, 300, 500]
                    if milestones.contains(count) {
                        completionMilestone = count == 1 ? "First workout!" : "Workout #\(count)!"
                    }
                }
                showingCompletionSheet = true
            }
        } catch { Log.app.error("Save workout: \(error.localizedDescription)") }
    }

    private func saveAsTemplate(name: String) {
        let templateExercises = exercises.map { ex in
            WorkoutTemplate.TemplateExercise(name: ex.name, sets: ex.sets.count,
                                             isWarmup: ex.isWarmupExercise,
                                             restSeconds: ex.restTime, notes: ex.notes)
        }
        if let json = try? JSONEncoder().encode(templateExercises),
           let jsonStr = String(data: json, encoding: .utf8) {
            var t = WorkoutTemplate(name: name.isEmpty ? workoutName : name,
                                    exercisesJson: jsonStr,
                                    createdAt: ISO8601DateFormatter().string(from: Date()))
            try? WorkoutService.saveTemplate(&t)
        }
    }

    private static func defaultWorkoutName() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<21: return "Evening Workout"
        default: return "Night Workout"
        }
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
    @State private var favs: Set<String> = WorkoutService.exerciseFavorites
    @FocusState private var searchFocused: Bool

    private var results: [ExerciseDatabase.ExerciseInfo] {
        var list = query.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: query)
        if let filter = selectedBodyPartFilter { list = list.filter { $0.bodyPart == filter } }
        // Rank favorites first
        let f = favs
        list.sort { f.contains($0.name) && !f.contains($1.name) }
        return Array(list.prefix(50))
    }

    private var favoriteExercises: [ExerciseDatabase.ExerciseInfo] {
        guard !favs.isEmpty, query.isEmpty else { return [] }
        let all = ExerciseDatabase.allWithCustom
        var matched = all.filter { favs.contains($0.name) }
        if let filter = selectedBodyPartFilter { matched = matched.filter { $0.bodyPart == filter } }
        return matched
    }

    private var recentExercises: [String] {
        let recents = (try? WorkoutService.recentExerciseNames(limit: 10)) ?? []
        let favNames = favs
        var filtered = recents.filter { !favNames.contains($0) }
        if !query.isEmpty { filtered = filtered.filter { $0.localizedCaseInsensitiveContains(query) } }
        if let filter = selectedBodyPartFilter {
            filtered = filtered.filter { ExerciseDatabase.bodyPart(for: $0) == filter }
        }
        return filtered
    }

    // Exercises from workout history that aren't in the database
    private var historyExtras: [String] {
        let allKnown = Set(ExerciseDatabase.allWithCustom.map { $0.name.lowercased() })
        let history = (try? WorkoutService.allExerciseNames()) ?? []
        let filtered = history.filter { !allKnown.contains($0.lowercased()) }
        if query.isEmpty { return filtered }
        return filtered.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                        .focused($searchFocused)
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

                    // Favorite exercises
                    if !favoriteExercises.isEmpty {
                        Section("Favorites") {
                            ForEach(favoriteExercises) { ex in
                                exerciseRow(name: ex.name, bodyPart: ex.bodyPart, equipment: ex.equipment)
                            }
                        }
                    }

                    // Recently used
                    if !recentExercises.isEmpty {
                        Section("Recent") {
                            ForEach(recentExercises, id: \.self) { name in
                                exerciseRow(name: name, bodyPart: ExerciseDatabase.bodyPart(for: name))
                            }
                        }
                    }

                    // History exercises (logged before but not in DB)
                    if !historyExtras.isEmpty {
                        Section("Your Exercises") {
                            ForEach(historyExtras, id: \.self) { name in
                                exerciseRow(name: name, bodyPart: ExerciseDatabase.bodyPart(for: name))
                            }
                        }
                    }

                    // Database exercises
                    Section(query.isEmpty ? "All Exercises (\(results.count))" : "\(results.count) results") {
                        ForEach(results) { ex in
                            exerciseRow(name: ex.name, bodyPart: ex.bodyPart, equipment: ex.equipment)
                        }
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingCustom) {
                CustomExerciseSheet { name in onSelect(name); dismiss() }
            }
            .onAppear {
                favs = WorkoutService.exerciseFavorites
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
            }
        }
    }

    private func exerciseRow(name: String, bodyPart: String, equipment: String? = nil) -> some View {
        Button { onSelect(name); dismiss() } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if favs.contains(name) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.fatYellow)
                    }
                    Text(name).font(.subheadline)
                    Spacer()
                    if let lastW = try? WorkoutService.lastWeight(for: name) {
                        Text("\(Int(lastW)) lb").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(bodyPart).font(.caption2).foregroundStyle(.tertiary)
                }
                if let equipment, !equipment.isEmpty {
                    Text(equipment).font(.caption).foregroundStyle(.quaternary)
                }
            }
        }
        .tint(.primary)
        .swipeActions(edge: .leading) {
            Button {
                WorkoutService.toggleExerciseFavorite(name)
                favs = WorkoutService.exerciseFavorites
            } label: {
                Label(favs.contains(name) ? "Unfavorite" : "Favorite", systemImage: favs.contains(name) ? "star.slash" : "star")
            }.tint(Theme.fatYellow)
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
