import SwiftUI
import DriftCore

/// Android port of the iOS `WorkoutView` (Drift/Views/Workout/WorkoutView.swift)
/// — same layout, cards, and Theme, driving the same DriftCore services.
/// Omitted pending parity work: Strong/Hevy CSV import, template rename
/// alert, workout context menus, progressive-overload alerts, Health card.
struct DriftWorkoutView: View {
    @State var workouts: [WorkoutSummary] = []
    @State var weeklyCounts: [(weekStart: Date, count: Int)] = []
    @State var templates: [WorkoutTemplate] = []
    @State var showingNewWorkout = false
    @State var showingPastWorkout = false
    @State var showingVoiceLog = false
    @State var showingExerciseBrowser = false
    @State var showingCreateTemplate = false
    @State var editingTemplateForEdit: WorkoutTemplate? = nil
    @State var isLoading = true
    @State var selectedTemplate: WorkoutTemplate? = nil
    @State var previewTemplate: WorkoutTemplate? = nil
    @State var previewFollowUp: PreviewFollowUp? = nil
    @State var loadResult: String?
    @State var showingLoadAlert = false
    @State var showingDeleteAllTemplates = false

    enum PreviewFollowUp { case start(WorkoutTemplate), edit(WorkoutTemplate) }

    @State var showHistory = false
    @State var showAllTemplates = false
    @State var streak: (current: Int, longest: Int)?
    // Cached: hasActiveSession JSON-decodes from UserDefaults — too heavy to
    // run on every body evaluation over the JNI bridge (#1074).
    @State var hasActiveSession = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Active session banner
                if !showingNewWorkout && hasActiveSession {
                    Button { showingNewWorkout = true } label: {
                        HStack {
                            Image(systemName: sym("figure.strengthtraining.traditional"))
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
                        Label("Start Workout", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    }.buttonStyle(.plain)

                    Button {
                        if let smart = ExerciseService.buildSmartSession() {
                            selectedTemplate = smart
                            showingNewWorkout = true
                        }
                    } label: {
                        Label("Coach Me", systemImage: sym("brain.head.profile"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    }.buttonStyle(.plain)
                }

                // Conversational entry — the shared ExerciseVoiceLogSheet, typed
                // until Android speech support lands (#1063); parse/save pipeline
                // matches iOS.
                Button { showingVoiceLog = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: sym("mic.fill"))
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.ink, in: Circle())
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

                Button { showingPastWorkout = true } label: {
                    Label("Log Past Workout", systemImage: sym("clock.arrow.circlepath"))
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
                            // iOS also offers "Import from Strong / Hevy" here —
                            // needs a document-picker seam on Android (#1064).
                            // Package items drop iOS's numbered-circle icons:
                            // skip-ui maps no numeric glyphs.
                            Button { loadPackage(DefaultTemplates.loadPackageI, name: "Drift Package I") } label: {
                                Text("Load Drift Package I")
                            }
                            Button { loadPackage(DefaultTemplates.loadPackageII, name: "Drift Package II") } label: {
                                Text("Load Drift Package II")
                            }
                            Button { loadPackage(DefaultTemplates.loadPackageIII, name: "Drift Package III") } label: {
                                Text("Load Drift Package III (Bands)")
                            }
                            Button { loadPackage(DefaultTemplates.loadPackageIV, name: "Drift Package IV") } label: {
                                Text("Load Drift Package IV")
                            }
                            if !templates.isEmpty {
                                Divider()
                                Button(role: .destructive) { showingDeleteAllTemplates = true } label: {
                                    Label("Remove All Templates", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: sym("ellipsis.circle")).font(.body).foregroundStyle(Theme.accent)
                        }
                    }

                    if templates.isEmpty {
                        emptyTemplatesActions
                    } else {
                        VStack(spacing: 0) {
                            ForEach(showAllTemplates ? templates : Array(templates.prefix(5))) { t in
                                Button {
                                    previewTemplate = t
                                } label: {
                                    HStack(spacing: 8) {
                                        if t.isFavorite {
                                            Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.fatYellow)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                                            Text(templateSubtitle(t))
                                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                            if templates.count > 5 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { showAllTemplates.toggle() }
                                } label: {
                                    Text(showAllTemplates ? "Show fewer" : "Show all \(templates.count)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Theme.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .card()

                // Browse exercises
                Button { showingExerciseBrowser = true } label: {
                    HStack {
                        Label("Browse Exercises", systemImage: sym("dumbbell"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("950+").font(.caption2).foregroundStyle(Theme.textTertiary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                // Body recovery map (same slot as iOS: before streak/consistency)
                BodyMapView { template in
                    WorkoutService.clearSession()
                    selectedTemplate = template
                    showingNewWorkout = true
                }

                if weeklyCounts.reduce(0, { $0 + $1.count }) > 0 {
                    if let streak, streak.current > 0 {
                        streakRow(current: streak.current, longest: streak.longest)
                    }
                    consistencyChart
                }

                // History — collapsible
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: sym("dumbbell.fill")).font(.system(size: Theme.FontSize.display2)).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Workouts Yet").font(.headline)
                        Text("Start a workout above").font(.caption).foregroundStyle(Theme.textSecondary)
                    }.padding(.top, 30)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: sym("clock.arrow.circlepath"))
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
                                workoutCard(s)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercise")
        .sheet(isPresented: $showingNewWorkout, onDismiss: { loadData() }) {
            ActiveWorkoutView(template: selectedTemplate) {
                selectedTemplate = nil
                loadData()
            }
        }
        .sheet(isPresented: $showingPastWorkout, onDismiss: { loadData() }) {
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
            // Present the follow-up ONLY after the preview has finished
            // dismissing — no timer, no race, no dead gap between sheets.
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
        .alert("Remove All Templates?", isPresented: $showingDeleteAllTemplates) {
            Button("Remove All", role: .destructive) {
                for t in templates {
                    if let tid = t.id { WorkoutService.deleteTemplate(id: tid) }
                }
                loadData()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All \(templates.count) templates will be permanently deleted.") }
        .alert("Templates", isPresented: $showingLoadAlert) {
            Button("OK") {}
        } message: { Text(loadResult ?? "Done") }
        .onAppear { loadData() }
    }

    private func templateSubtitle(_ t: WorkoutTemplate) -> String {
        let w = t.exercises.filter { !$0.isWarmup }
        let wm = t.exercises.filter { $0.isWarmup }
        let base = "\(w.count) exercises"
        guard !wm.isEmpty else { return base }
        let label = wm.count == 1 ? "warmup" : "warmups"
        return base + " · \(wm.count) \(label)"
    }

    var consistencyChart: some View {
        let total = weeklyCounts.reduce(0) { $0 + $1.count }
        let thisWeek = weeklyCounts.first?.count ?? 0

        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("\(thisWeek)").font(.title2.weight(.bold).monospacedDigit())
                Text("this week").font(.caption2).foregroundStyle(Theme.textTertiary)
            }.frame(maxWidth: .infinity)

            Divider().frame(height: 28)

            VStack(spacing: 2) {
                Text("\(total)").font(.title2.weight(.bold).monospacedDigit())
                Text("in 12 wks").font(.caption2).foregroundStyle(Theme.textTertiary)
            }.frame(maxWidth: .infinity)
        }
        .card()
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
                if !s.workout.durationDisplay.isEmpty {
                    Label(s.workout.durationDisplay, systemImage: sym("clock")).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Label("\(Int(wu.convertFromLbs(s.totalVolume))) \(wu.displayName)", systemImage: sym("scalemass")).font(.caption).foregroundStyle(Theme.textSecondary)
                Label("\(s.exercises.count) exercises", systemImage: sym("dumbbell")).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            let bodyParts = Array(Set(s.exercises.map { ExerciseDatabase.bodyPart(for: $0) })).sorted()
            if !bodyParts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(bodyParts.prefix(4), id: \.self) { part in
                        Text(part).font(.system(size: Theme.FontSize.nano))
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

    private func abbreviate(_ n: String) -> String { n.count <= 25 ? n : String(n.prefix(22)) + "..." }
    private func formatDate(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; guard let date = f.date(from: String(d.prefix(10))) else { return d }
        return DateFormatters.dayDisplay.string(from: date)
    }

    var emptyTemplatesActions: some View {
        VStack(spacing: 12) {
            Text("No templates yet").font(.caption).foregroundStyle(Theme.textTertiary)
            Menu {
                Button { loadPackage(DefaultTemplates.loadPackageI, name: "Drift Package I") } label: { Text("Drift Package I") }
                Button { loadPackage(DefaultTemplates.loadPackageII, name: "Drift Package II") } label: { Text("Drift Package II") }
                Button { loadPackage(DefaultTemplates.loadPackageIII, name: "Drift Package III") } label: { Text("Drift Package III (Bands)") }
                Button { loadPackage(DefaultTemplates.loadPackageIV, name: "Drift Package IV") } label: { Text("Drift Package IV") }
            } label: {
                Label("Load Drift Packages", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func loadPackage(_ loader: () -> Int, name: String) {
        let added = loader()
        loadResult = "Added \(added) \(name) templates"
        showingLoadAlert = true
        loadData()
    }

    private func loadData() {
        isLoading = true
        Task {
            let snapshot = await Self.fetchSnapshot()
            workouts = snapshot.workouts
            weeklyCounts = snapshot.weeklyCounts
            templates = snapshot.templates
            streak = snapshot.streak
            hasActiveSession = snapshot.hasActiveSession
            isLoading = false
        }
    }

    private struct Snapshot: @unchecked Sendable {
        var workouts: [WorkoutSummary] = []
        var weeklyCounts: [(weekStart: Date, count: Int)] = []
        var templates: [WorkoutTemplate] = []
        var streak: (current: Int, longest: Int)?
        var hasActiveSession = false
    }

    /// Off-main load — AppDatabase work on the UI thread ANRs debug builds
    /// on Android (unlike iOS, where WorkoutView loads inline).
    private static func fetchSnapshot() async -> Snapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var s = Snapshot()
                let raw = (try? WorkoutService.fetchWorkouts(limit: 500)) ?? []
                s.workouts = (try? WorkoutService.buildSummaries(for: raw)) ?? []
                s.weeklyCounts = (try? WorkoutService.weeklyWorkoutCounts(weeks: 12)) ?? []
                s.templates = (try? WorkoutService.fetchTemplates()) ?? []
                s.streak = try? WorkoutService.workoutStreak()
                s.hasActiveSession = WorkoutService.hasActiveSession
                continuation.resume(returning: s)
            }
        }
    }

    private func streakRow(current: Int, longest: Int) -> some View {
        let label = current == 1 ? "week" : "weeks"
        return HStack {
            Image(systemName: sym("flame.fill")).foregroundStyle(.orange)
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
