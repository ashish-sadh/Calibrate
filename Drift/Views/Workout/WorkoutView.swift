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
    @State private var showingPastWorkout = false
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
                        Label("Start Workout", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
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

                Button { showingPastWorkout = true } label: {
                    Label("Log Past Workout", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                }.buttonStyle(.bordered).tint(.secondary)

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
        .sheet(isPresented: $showingPastWorkout) {
            ActiveWorkoutView(pastDate: Date().addingTimeInterval(-86400)) { loadData() }
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
            TemplatePreviewSheet(
                template: t,
                onStartWorkout: { template in
                    previewTemplate = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        WorkoutService.clearSession()
                        selectedTemplate = template
                        showingNewWorkout = true
                    }
                },
                onEditTemplate: { template in
                    previewTemplate = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        editingTemplateForEdit = template
                    }
                },
                onDismiss: { previewTemplate = nil },
                onReload: { loadData() }
            )
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

