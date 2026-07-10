import SwiftUI
import DriftCore
import Charts
import UniformTypeIdentifiers
import AudioToolbox

struct WorkoutView: View {
    @Binding var selectedTab: Int
    @State private var workouts: [WorkoutSummary] = []
    @State private var overloadAlerts: [PlateauResult] = []
    @State private var showAllOverload = false
    @State private var weeklyCounts: [(weekStart: Date, count: Int)] = []
    @State private var templates: [WorkoutTemplate] = []
    @State private var showingNewWorkout = false
    @State private var showingPastWorkout = false
    @State private var showingVoiceLog = false
    @State private var showingImport = false
    @State private var showingCreateTemplate = false
    @State private var showingExerciseBrowser = false
    @State private var importResult: String?
    @State private var showingImportAlert = false
    @State private var isLoading = true
    @State private var selectedTemplate: WorkoutTemplate? = nil
    @State private var previewTemplate: WorkoutTemplate? = nil
    @State private var editingTemplateForEdit: WorkoutTemplate? = nil
    /// #premium-polish: what to present once the preview sheet finishes
    /// dismissing — set before clearing `previewTemplate`, run in the sheet's
    /// onDismiss. Replaces an asyncAfter(0.3) dead gap between the two sheets.
    private enum PreviewFollowUp { case start(WorkoutTemplate), edit(WorkoutTemplate) }
    @State private var previewFollowUp: PreviewFollowUp? = nil
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
    @State private var healthWorkouts: [HealthWorkout] = []
    @State private var streak: (current: Int, longest: Int)?
    /// Freshness stamp — tab re-selection within 30s skips the reload.
    @State private var lastLoadedAt = Date.distantPast

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
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }.buttonStyle(.plain)
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
                    .buttonStyle(.bordered).tint(Theme.accent)
                }

                // Conversational entry — voice/text exercise logging (epic #867,
                // Workout-tab parity with food's VoiceLogSheet). Embeds the shared
                // VoiceMicButton (V7 ink tint, no pink) so the mic affordance reads
                // identically to the food path.
                Button { showingVoiceLog = true } label: {
                    HStack(spacing: 12) {
                        VoiceMicButton(tint: Theme.ink, diameter: 40, iconSize: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log by Voice or Text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Say or type your sets — \u{201C}3×10 bench at 135\u{201D}")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log workout by voice or text")
                .accessibilityIdentifier("workout-voice-entry")

                Button { showingPastWorkout = true } label: {
                    Label("Log Past Workout", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                }.buttonStyle(.bordered).tint(.secondary)

                // Templates
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Templates").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if !templates.isEmpty {
                            Text("\(templates.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        }
                        Menu {
                            Button { showingCreateTemplate = true } label: {
                                Label("New Template", systemImage: "plus")
                            }
                            Button { showingImport = true } label: {
                                Label("Import from Strong / Hevy", systemImage: "square.and.arrow.down")
                            }
                            // Numbered icons, not star/star.fill — the filled
                            // star read as "Package II is favorited" (field
                            // report 2026-07-09).
                            Button {
                                loadPackage(DefaultTemplates.loadCurated, name: "Drift Package I")
                            } label: {
                                Label("Load Drift Package I", systemImage: "1.circle")
                            }
                            Button {
                                loadPackage(DefaultTemplates.loadPackageII, name: "Drift Package II")
                            } label: {
                                Label("Load Drift Package II", systemImage: "2.circle")
                            }
                            Button {
                                loadPackage(DefaultTemplates.loadPackageIII, name: "Drift Package III")
                            } label: {
                                Label("Load Drift Package III (Bands)", systemImage: "3.circle")
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
                        .accessibilityLabel("Template options")
                    }

                    if templates.isEmpty {
                        emptyTemplatesActions
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
                                                let exerciseText: String = {
                                                    let w = t.exercises.filter { !$0.isWarmup }
                                                    let wm = t.exercises.filter { $0.isWarmup }
                                                    let base = "\(w.count) exercises"
                                                    guard !wm.isEmpty else { return base }
                                                    let label = wm.count == 1 ? "warmup" : "warmups"
                                                    return base + " · \(wm.count) \(label)"
                                                }()
                                                Text(exerciseText)
                                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
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

                // Analytics below the fold — operator call 2026-07-09:
                // gym users reach Start Workout / templates first; burn
                // chips, Apple Health list, recovery map and consistency
                // are review content, not mid-session actions.
                // Today's burn metrics
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.caption).foregroundStyle(Theme.stepsOrange)
                        Text("\(Int(activeCalories))").font(.subheadline.weight(.bold).monospacedDigit())
                        Text("active cal").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity).card()

                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk").font(.caption).foregroundStyle(Theme.deficit)
                        Text(steps >= 1000 ? String(format: "%.1fk", steps/1000) : "\(Int(steps))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text("steps").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity).card()
                }

                // Apple Health Workouts (last 7 days)
                if !healthWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.heartRed)
                            Text("Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(healthWorkouts.count) \(healthWorkouts.count == 1 ? "workout" : "workouts") this week").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
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
                                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(w.durationDisplay).font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                    Text("\(Int(w.calories)) cal").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
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

                // Progressive overload alerts
                if !overloadAlerts.isEmpty {
                    overloadCard
                }

                if !weeklyCounts.isEmpty {
                    // Streak computed in loadData — a DB call in `body`
                    // re-ran on every render pass (perf 2026-07-09).
                    if let streak, streak.current > 0 {
                        streakRow(current: streak.current, longest: streak.longest)
                    }
                    consistencyChart
                }

                Button { showingExerciseBrowser = true } label: {
                    Label("Browse Exercises", systemImage: "dumbbell").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(Theme.accent)

                // History — collapsible
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: Theme.FontSize.display2)).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Workouts Yet").font(.headline)
                        Text("Start a workout above, or import your history").font(.caption).foregroundStyle(Theme.textSecondary)
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
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
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
        .toolbarColorScheme(.light, for: .navigationBar)
        // Back chevron removed 2026-07-09: it jumped to the Today tab — an
        // affordance from when MoreTabView PUSHED this view. Workout is now
        // a first-class tab (own NavigationStack in ContentView); tabs don't
        // have "back".
        .sheet(isPresented: $showingNewWorkout) {
            ActiveWorkoutView(template: selectedTemplate) {
                selectedTemplate = nil
                loadData()
            }
        }
        .sheet(isPresented: $showingPastWorkout) {
            ActiveWorkoutView(pastDate: Date().addingTimeInterval(-86400)) { loadData() }
        }
        .sheet(isPresented: $showingVoiceLog) {
            // Voice/text exercise logging — reload history and reveal it so the
            // user sees the workout they just logged.
            ExerciseVoiceLogSheet {
                loadData()
                showHistory = true
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
        .sheet(item: $previewTemplate, onDismiss: {
            // #premium-polish: present the follow-up ONLY after the preview has
            // finished dismissing — no timer, no race, no dead gap between sheets.
            switch previewFollowUp {
            case .start(let template):
                WorkoutService.clearSession()
                selectedTemplate = template
                showingNewWorkout = true
            case .edit(let template):
                editingTemplateForEdit = template
            case nil:
                break
            }
            previewFollowUp = nil
        }) { t in
            TemplatePreviewSheet(
                template: t,
                onStartWorkout: { template in
                    previewFollowUp = .start(template)
                    previewTemplate = nil
                },
                onEditTemplate: { template in
                    previewFollowUp = .edit(template)
                    previewTemplate = nil
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
                    WorkoutService.renameTemplate(id: tid, name: renameTemplateName)
                    loadData()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove All Templates?", isPresented: $showingDeleteAllTemplates) {
            Button("Remove All", role: .destructive) {
                for t in templates {
                    if let tid = t.id {
                        WorkoutService.deleteTemplate(id: tid)
                    }
                }
                loadData()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All \(templates.count) templates will be permanently deleted.") }
        .alert("Delete Template?", isPresented: $showingDeleteTemplate) {
            Button("Delete", role: .destructive) {
                if let tid = deleteTemplateId {
                    WorkoutService.deleteTemplate(id: tid)
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
        .onAppear {
            AIScreenTracker.shared.currentScreen = .exercise
            // Deferred one frame so the tab swap renders instantly (same
            // treatment Food/Weight already had), and skipped entirely when
            // data is <30s fresh — explicit paths (workout saved, template
            // edited) still call loadData() directly.
            if Date().timeIntervalSince(lastLoadedAt) > 30 {
                Task { @MainActor in loadData() }
            }
        }
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
                Text("this week").font(.caption2).foregroundStyle(Theme.textTertiary)
            }.frame(maxWidth: .infinity)

            Divider().frame(height: 28)

            // Total
            VStack(spacing: 2) {
                Text("\(total)").font(.title2.weight(.bold).monospacedDigit())
                Text("in 12 wks").font(.caption2).foregroundStyle(Theme.textTertiary)
            }.frame(maxWidth: .infinity)
        }
        .card()
    }

    private var overloadCard: some View {
        let maxVisible = 5
        let visible = showAllOverload ? overloadAlerts : Array(overloadAlerts.prefix(maxVisible))
        let hasMore = overloadAlerts.count > maxVisible
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(Theme.accent)
                Text("Plateau Alert").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if hasMore {
                    Text("\(overloadAlerts.count)").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            ForEach(visible, id: \.exercise) { info in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.fatYellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.exercise).font(.caption.weight(.semibold))
                        Text("\(info.sessionsChecked) sessions without progress — \(info.suggestion)")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        ProgressiveOverloadService.dismiss(exercise: info.exercise)
                        overloadAlerts = ProgressiveOverloadService.allPlateaus()
                    } label: {
                        Image(systemName: "xmark").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            if hasMore {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAllOverload.toggle() }
                } label: {
                    Text(showAllOverload ? "Show less" : "Show all \(overloadAlerts.count) exercises")
                        .font(.caption2).foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
            }
        }.card()
    }

    private func workoutCard(_ s: WorkoutSummary) -> some View {
        let wu = Preferences.weightUnit
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.workout.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDate(s.workout.date)).font(.caption).foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 12) {
                if !s.workout.durationDisplay.isEmpty { Label(s.workout.durationDisplay, systemImage: "clock").font(.caption).foregroundStyle(Theme.textSecondary) }
                Label("\(Int(wu.convertFromLbs(s.totalVolume))) \(wu.displayName)", systemImage: "scalemass").font(.caption).foregroundStyle(Theme.textSecondary)
                Label("\(s.exercises.count) exercises", systemImage: "dumbbell").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            // Muscle group chips
            let bodyParts = Array(Set(s.exercises.map { ExerciseDatabase.bodyPart(for: $0) })).sorted()
            if !bodyParts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(bodyParts.prefix(4), id: \.self) { part in
                        HStack(spacing: 2) {
                            Image(systemName: muscleIcon(part)).font(.system(size: 8))
                            Text(part).font(.system(size: Theme.FontSize.nano))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.1), in: Capsule())
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            if let notes = s.workout.notes, !notes.isEmpty {
                Text(notes).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            ForEach(s.bestSets.prefix(3), id: \.exercise) { best in
                HStack {
                    Text(abbreviate(best.exercise)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Spacer()
                    Text("\(Int(wu.convertFromLbs(best.weight))) \(wu.displayName) × \(best.reps)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                }
            }
        }.card()
    }

    private func muscleIcon(_ bodyPart: String) -> String {
        switch bodyPart.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.boxing"
        case "arms": return "figure.cooldown"
        case "core": return "figure.core.training"
        case "full body": return "figure.cross.training"
        default: return "figure.mixed.cardio"
        }
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
    /// Empty-state actions — extracted (#941): three buttons inline pushed the
    /// enclosing ViewBuilder past the type-checker's budget.
    private var emptyTemplatesActions: some View {
        VStack(spacing: 12) {
            Text("No templates yet").font(.caption).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 12) {
                Button { showingImport = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down").font(.caption)
                }.buttonStyle(.bordered)
                // Three packages don't fit as siblings — collapse into a menu.
                Menu {
                    Button { loadPackage(DefaultTemplates.loadCurated, name: "Drift Package I") } label: {
                        Label("Drift Package I", systemImage: "1.circle")
                    }
                    Button { loadPackage(DefaultTemplates.loadPackageII, name: "Drift Package II") } label: {
                        Label("Drift Package II", systemImage: "2.circle")
                    }
                    Button { loadPackage(DefaultTemplates.loadPackageIII, name: "Drift Package III") } label: {
                        Label("Drift Package III (Bands)", systemImage: "3.circle")
                    }
                } label: {
                    Label("Drift Packages", systemImage: "square.stack.3d.up").font(.caption)
                }.buttonStyle(.bordered).tint(Theme.accent)
            }
        }
    }

    private func loadPackage(_ loader: () -> Int, name: String) {
        let added = loader()
        importResult = "Added \(added) \(name) templates"
        showingImportAlert = true
        loadData()
    }

    private func loadData() {
        isLoading = true
        lastLoadedAt = Date()
        // Load independently so one failure doesn't block the others
        do {
            let raw = try WorkoutService.fetchWorkouts(limit: 500)
            // Batched: ONE sets query for all workouts. The old per-workout
            // buildSummary was up to 500 serial queries on the tab-switch
            // frame (perf field report 2026-07-09).
            workouts = try WorkoutService.buildSummaries(for: raw)
        } catch { Log.app.error("Workout load: \(error.localizedDescription)") }
        do {
            weeklyCounts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
        } catch { Log.app.error("Weekly counts: \(error.localizedDescription)") }
        do {
            templates = try WorkoutService.fetchTemplates()
        } catch { Log.app.error("Templates load: \(error.localizedDescription)") }
        streak = try? WorkoutService.workoutStreak()
        overloadAlerts = ProgressiveOverloadService.allPlateaus()
        isLoading = false
    }

    private func streakRow(current: Int, longest: Int) -> some View {
        let label = current == 1 ? "week" : "weeks"
        return HStack {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(current) \(label) streak")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Best: \(longest)w")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.radiusChip))
    }
}

