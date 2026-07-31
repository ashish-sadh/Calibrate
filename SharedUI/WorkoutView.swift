import SwiftUI
import DriftCore
#if DRIFT_IOS_APP
import UniformTypeIdentifiers
#endif

struct WorkoutView: View {
    @Binding var selectedTab: Int
    @State var workouts: [WorkoutSummary] = []
    @State var overloadAlerts: [PlateauResult] = []
    @State var showAllOverload = false
    @State var weeklyCounts: [(weekStart: Date, count: Int)] = []
    @State var templates: [WorkoutTemplate] = []
    @State var showingNewWorkout = false
    @State var showingCoach = false
    @State var showingPastWorkout = false
    @State var showingVoiceLog = false
    @State var showingScan = false
    @State var showingImport = false
    @State var showingCreateTemplate = false
    @State var showingExerciseBrowser = false
    @State var importResult: String?
    @State var showingImportAlert = false
    @State var isLoading = true
    @State var selectedTemplate: WorkoutTemplate? = nil
    @State var previewTemplate: WorkoutTemplate? = nil
    @State var editingTemplateForEdit: WorkoutTemplate? = nil
    /// #premium-polish: what to present once the preview sheet finishes
    /// dismissing — set before clearing `previewTemplate`, run in the sheet's
    /// onDismiss. Replaces an asyncAfter(0.3) dead gap between the two sheets.
    enum PreviewFollowUp { case start(WorkoutTemplate), edit(WorkoutTemplate) }
    @State var previewFollowUp: PreviewFollowUp? = nil
    @State var renameTemplateId: Int64?
    @State var renameTemplateName = ""
    @State var showingRenameAlert = false
    @State var deleteTemplateId: Int64?
    @State var showingDeleteTemplate = false
    @State var deleteWorkoutId: Int64?
    @State var showingDeleteWorkout = false
    @State var showingDeleteAllTemplates = false

    @State var activeCalories: Double = 0
    @State var steps: Double = 0
    @State var showHistory = false
    @State var showAllTemplates = false
    @State var healthWorkouts: [HealthWorkout] = []
    @State var streak: (current: Int, longest: Int)?
    /// Freshness stamp — tab re-selection within 30s skips the reload.
    @State var lastLoadedAt = Date.distantPast

    #if os(Android)
    /// Android-only cache. `ExerciseDatabase.bodyPart(for:)` (catalog lookup) is
    /// cheap on iOS but crosses the JNI bridge on every Compose recomposition
    /// here — directive 0e forbids that work in a view body, so it's hoisted
    /// into the off-main Snapshot.
    @State var bodyPartsByWorkout: [Int64: [String]] = [:]
    #endif

    /// The root minimized-workout pill asked to reopen the sheet (#1167).
    /// Present it and clear the flag so a later tab rebuild doesn't reopen it.
    private func consumeResumeRequest() {
        guard LiveWorkoutMonitor.shared.wantsResume else { return }
        LiveWorkoutMonitor.shared.wantsResume = false
        showingNewWorkout = true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // The in-tab "Workout in progress" banner was removed with #1167:
                // the root minimized-workout pill (MinimizedWorkoutBar) now shows
                // the same Resume affordance on EVERY tab, so a second copy here
                // would be a duplicate whenever you're on the Workout tab.

                // Start buttons
                HStack(spacing: 10) {
                    Button {
                        WorkoutService.clearSession()
                        selectedTemplate = nil
                        FeatureUsage.record(TelemetryEvent.workoutStarted)
                        showingNewWorkout = true
                    } label: {
                        Label("Start Workout", systemImage: sym("plus.circle.fill")).frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent)

                    // Coach Me opens a CONVERSATION now. It used to call
                    // buildSmartSession() and drop a generated session on you
                    // with no questions asked, which is why it felt like a dice
                    // roll — the coach asks, remembers, drafts, then saves.
                    Button {
                        showingCoach = true
                    } label: {
                        Label("AI Coach", systemImage: sym("brain.head.profile")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Theme.accent)
                }

                // Conversational entry point.
                #if DRIFT_IOS_APP
                // iOS: scan-primary. Photograph / screenshot / PDF-upload any
                // workout page and the Nebius vision model decides template vs.
                // logged session; an optional note rides along as context.
                // Replaces the old voice/text sheet (bolt-on parallel flow).
                Button { showingScan = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: sym("doc.viewfinder"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.ink.opacity(0.10)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan or Log a Workout")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Photo, screenshot or PDF → template or logged session")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: sym("chevron.right"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan or log a workout")
                .accessibilityIdentifier("workout-scan-entry")
                #else
                // Android has no camera/PDF seam yet (#1063) — keep the text
                // logging card until the scan pipeline is ported.
                Button { showingVoiceLog = true } label: {
                    HStack(spacing: 12) {
                        VoiceMicButton(tint: Theme.ink, diameter: 40, iconSize: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log by Text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Type your sets — \u{201C}3×10 bench at 135\u{201D}")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: sym("chevron.right"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log workout by text")
                .accessibilityIdentifier("workout-voice-entry")
                #endif

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
                                Label("New Template", systemImage: sym("plus"))
                            }
                            #if DRIFT_IOS_APP
                            Button { showingImport = true } label: {
                                Label("Import from Strong / Hevy", systemImage: sym("square.and.arrow.down"))
                            }
                            #endif
                            // Numbered icons, not star/star.fill — the filled
                            // star read as "Package II is favorited" (field
                            // report 2026-07-09).
                            Button {
                                loadPackage(DefaultTemplates.loadPackageI, name: "Drift Package I")
                            } label: {
                                Label("Load Drift Package I", systemImage: sym("1.circle"))
                            }
                            Button {
                                loadPackage(DefaultTemplates.loadPackageII, name: "Drift Package II")
                            } label: {
                                Label("Load Drift Package II", systemImage: sym("2.circle"))
                            }
                            Button {
                                loadPackage(DefaultTemplates.loadPackageIII, name: "Drift Package III")
                            } label: {
                                Label("Load Drift Package III (Bands)", systemImage: sym("3.circle"))
                            }
                            Button {
                                loadPackage(DefaultTemplates.loadPackageIV, name: "Drift Package IV")
                            } label: {
                                Label("Load Drift Package IV", systemImage: sym("4.circle"))
                            }
                            if !templates.isEmpty {
                                Divider()
                                Button(role: .destructive) {
                                    showingDeleteAllTemplates = true
                                } label: {
                                    Label("Remove All Templates", systemImage: sym("trash"))
                                }
                            }
                        } label: {
                            Image(systemName: sym("ellipsis.circle")).font(.body).foregroundStyle(Theme.accent)
                        }
                        .accessibilityLabel("Template options")
                    }

                    if templates.isEmpty {
                        emptyTemplatesActions
                    } else {
                        // Plain stack, not a nested ScrollView — the capped
                        // inner scroller fought the page scroll (field report
                        // 2026-07-09: template scroll "confused with page
                        // scroll"). The page owns scrolling; long lists
                        // collapse behind Show all.
                        VStack(spacing: 0) {
                            ForEach(showAllTemplates ? templates : Array(templates.prefix(5))) { t in
                                    Button {
                                        previewTemplate = t
                                    } label: {
                                        HStack(spacing: 8) {
                                            if t.isFavorite {
                                                Image(systemName: sym("star.fill")).font(.caption).foregroundStyle(Theme.fatYellow)
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
                                            Image(systemName: sym("chevron.right")).font(.caption2).foregroundStyle(Theme.textTertiary)
                                        }
                                        .padding(.vertical, 6)
                                        // contentShape: with .buttonStyle(.plain) there is
                                        // no background, so the hit region is the drawn
                                        // content — and the middle of this row is the
                                        // Spacer. Tapping a template anywhere but directly
                                        // on its name or chevron did nothing, which read as
                                        // "template preview is broken". Same fix, same
                                        // reason as the history rows below (:403).
                                        .contentShape(Rectangle())
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

                // Browse row lives with the action cluster — stranded at the
                // very bottom it was dead weight (field report 2026-07-09).
                Button { showingExerciseBrowser = true } label: {
                    HStack {
                        browseExercisesLabel
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("950+").font(.caption2).foregroundStyle(Theme.textTertiary)
                        Image(systemName: sym("chevron.right"))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                // Analytics below the fold — operator call 2026-07-09:
                // gym users reach Start Workout / templates first; burn
                // chips, Apple Health list, recovery map and consistency
                // are review content, not mid-session actions.
                // Today's burn metrics — needs a health provider. Android has
                // none until the Health Connect adapter (#1070), so the values
                // stay 0 and the band read "0 active cal / 0 steps"; hide it
                // there rather than show zeros. iOS always wires
                // HealthKitService in DriftApp.init → band unchanged (#1064).
                #if os(Android)
                if DriftPlatform.health != nil { burnMetricsBand }
                #else
                burnMetricsBand
                #endif

                // Platform-health-provider Workouts (last 7 days): Apple
                // Health on iOS, Health Connect on Android.
                if !healthWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            #if os(Android)
                            Image(systemName: sym("figure.strengthtraining.traditional")).font(.caption).foregroundStyle(Theme.heartRed)
                            Text("Health Connect").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            #else
                            Image(systemName: sym("heart.fill")).font(.caption).foregroundStyle(Theme.heartRed)
                            Text("Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            #endif
                            Spacer()
                            Text("\(healthWorkouts.count) \(healthWorkouts.count == 1 ? "workout" : "workouts") this week").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        }

                        ForEach(healthWorkouts.prefix(5)) { w in
                            HStack(spacing: 10) {
                                Image(systemName: sym("figure.strengthtraining.traditional"))
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
                    FeatureUsage.record(TelemetryEvent.workoutStarted)
                    showingNewWorkout = true
                }

                // Progressive overload alerts
                if !overloadAlerts.isEmpty {
                    overloadCard
                }

                if weeklyCounts.reduce(0, { $0 + $1.count }) > 0 {
                    // Streak computed in loadData — a DB call in `body`
                    // re-ran on every render pass (perf 2026-07-09).
                    if let streak, streak.current > 0 {
                        streakRow(current: streak.current, longest: streak.longest)
                    }
                    consistencyChart
                }

                // History — collapsible
                if workouts.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        emptyHistoryGlyph
                        Text("No Workouts Yet").font(.headline)
                        Text("Start a workout above, or import your history").font(.caption).foregroundStyle(Theme.textSecondary)
                        #if DRIFT_IOS_APP
                        Button { showingImport = true } label: {
                            Label("Import from Strong / Hevy", systemImage: sym("square.and.arrow.down"))
                                .font(.caption)
                        }.buttonStyle(.bordered)
                        #endif
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
                                Image(systemName: sym("chevron.down"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .rotationEffect(.degrees(showHistory ? 0 : -90))
                            }
                            .card()
                        }
                        .buttonStyle(.plain)

                        if showHistory {
                            ForEach(workouts, id: \.workout.id) { s in
                                NavigationLink { WorkoutDetailView(summary: s) { loadData() } } label: {
                                    // contentShape: the card's whitespace was
                                    // not tappable — history rows felt "very
                                    // hard to click" (field report 2026-07-10).
                                    workoutCard(s).contentShape(Rectangle())
                                }.tint(.primary)
                                    // .contextMenu DOES exist on Android, but SkipUI
                                    // implements it via pointerInput on the initial
                                    // pass, which starves sibling TextFields of focus
                                    // taps (same class of bug as the set-row menu in
                                    // ActiveWorkoutView). Keep it iOS-only; Android
                                    // reaches delete via the detail view's ⋯ menu.
                                    #if !os(Android)
                                    .contextMenu {
                                        if let wid = s.workout.id {
                                            Button(role: .destructive) {
                                                deleteWorkoutId = wid
                                                showingDeleteWorkout = true
                                            } label: { Label("Delete Workout", systemImage: sym("trash")) }
                                        }
                                    }
                                    #endif
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, bottomInset)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
        #if !os(Android)
        .toolbarColorScheme(.light, for: .navigationBar)
        #endif
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
            // user sees the workout they just logged. (Android entry point; iOS
            // uses the scan sheet below.)
            ExerciseVoiceLogSheet {
                loadData()
                showHistory = true
            }
        }
        #if DRIFT_IOS_APP
        .sheet(isPresented: $showingScan) {
            WorkoutScanSheet {
                loadData()
                showHistory = true
            }
        }
        #endif
        .sheet(isPresented: $showingCoach) {
            CoachMeView { loadData() }
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
                FeatureUsage.record(TelemetryEvent.workoutStarted)
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
        // CSV import is UTType + fileImporter — no SkipUI equivalent. Android
        // CSV import is a filed seam (#1067); the entry points above are gated
        // to match so nothing dead-ends.
        #if DRIFT_IOS_APP
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText]) { handleImport($0) }
        #endif
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
            // The root minimized-workout pill asks to resume by setting a flag
            // and switching to this tab. On Android the tab is rebuilt on
            // switch, so reading the flag here (onAppear) is what catches it
            // (#1167). On iOS the tab stays alive, so the onChange below fires.
            consumeResumeRequest()
            // Deferred one frame so the tab swap renders instantly (same
            // treatment Food/Weight already had), and skipped entirely when
            // data is <30s fresh — explicit paths (workout saved, template
            // edited) still call loadData() directly.
            if Date().timeIntervalSince(lastLoadedAt) > 30 {
                Task { @MainActor in loadData() }
            }
        }
        .onChange(of: LiveWorkoutMonitor.shared.wantsResume) { _, wants in
            if wants { consumeResumeRequest() }
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

    /// The pill tab bar floats over the scroll view on Android; iOS keeps its
    /// original 24pt inset.
    var bottomInset: CGFloat {
        #if os(Android)
        return 100
        #else
        return 24
        #endif
    }

    /// skip-ui maps `dumbbell` to `list.bullet` — a bullet list, a different
    /// object entirely (directive 0a). Android draws the real barbell instead
    /// (DumbbellGlyph.swift), matching the ForkKnifeShape/ClockFaceShape
    /// precedent.
    @ViewBuilder var browseExercisesLabel: some View {
        #if os(Android)
        Label {
            Text("Browse Exercises")
        } icon: {
            DumbbellShape().fill(Theme.textPrimary).frame(width: 16, height: 16)
        }
        #else
        Label("Browse Exercises", systemImage: "dumbbell")
        #endif
    }

    @ViewBuilder var emptyHistoryGlyph: some View {
        #if os(Android)
        DumbbellShape().fill(Theme.accent.opacity(0.5))
            .frame(width: Theme.FontSize.display2, height: Theme.FontSize.display2)
        #else
        Image(systemName: "dumbbell.fill").font(.system(size: Theme.FontSize.display2)).foregroundStyle(Theme.accent.opacity(0.5))
        #endif
    }

    private func refreshHealthData() async {
        guard let hk = DriftPlatform.health else { return }
        activeCalories = (try? await hk.fetchCaloriesBurned(for: Date()).active) ?? 0
        steps = (try? await hk.fetchSteps(for: Date())) ?? 0
        healthWorkouts = (try? await hk.fetchRecentWorkouts(days: 7)) ?? []
    }

    private var consistencyChart: some View {
        let total = weeklyCounts.reduce(0) { $0 + $1.count }
        // weeklyWorkoutCounts runs oldest → newest, so the current week is `.last`.
        // Reading `.first` rendered the bucket from 11 weeks ago and showed
        // "0 this week" for a workout logged today (#1076).
        let thisWeek = weeklyCounts.last?.count ?? 0

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
                #if os(Android)
                // Pinned skip-ui 1.58 has no chart glyph (sym's chart.bar.xaxis
                // target is 1.59+) — drawn bars instead (ChartGlyph.swift).
                BarChartShape().fill(Theme.accent).frame(width: 12, height: 12)
                #else
                Image(systemName: sym("chart.line.uptrend.xyaxis")).font(.caption).foregroundStyle(Theme.accent)
                #endif
                Text("Plateau Alert").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if hasMore {
                    Text("\(overloadAlerts.count)").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            ForEach(visible, id: \.exercise) { info in
                HStack(spacing: 8) {
                    Image(systemName: sym("exclamationmark.triangle.fill"))
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
                        Image(systemName: sym("xmark")).font(.caption2).foregroundStyle(Theme.textTertiary)
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
                if !s.workout.durationDisplay.isEmpty {
                    #if os(Android)
                    // "clock" is deliberately unmapped (Symbols.swift) — draw the
                    // face, matching the ActiveWorkoutView call site.
                    Label { Text(s.workout.durationDisplay) } icon: {
                        ClockFaceShape().fill(Theme.textSecondary).frame(width: 12, height: 12)
                    }.font(.caption).foregroundStyle(Theme.textSecondary)
                    #else
                    Label(s.workout.durationDisplay, systemImage: sym("clock")).font(.caption).foregroundStyle(Theme.textSecondary)
                    #endif
                }
                #if os(Android)
                // sym("scalemass") targets chart.bar.xaxis — 1.59-only under
                // the skip-ui pin (#1134); drawn bars keep the volume stat
                // distinct from the dumbbell exercise-count glyph beside it.
                Label { Text("\(Int(wu.convertFromLbs(s.totalVolume))) \(wu.displayName)") } icon: {
                    BarChartShape().fill(Theme.textSecondary).frame(width: 11, height: 11)
                }.font(.caption).foregroundStyle(Theme.textSecondary)
                #else
                Label("\(Int(wu.convertFromLbs(s.totalVolume))) \(wu.displayName)", systemImage: sym("scalemass")).font(.caption).foregroundStyle(Theme.textSecondary)
                #endif
                exerciseCountLabel(s.exercises.count).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            // Muscle group chips
            let bodyParts = bodyPartChips(for: s)
            if !bodyParts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(bodyParts.prefix(4), id: \.self) { part in
                        HStack(spacing: 2) {
                            Image(systemName: sym(muscleIcon(part))).font(.system(size: 8))
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
                    Text("\(WeightFormatter.plain(wu.convertFromLbs(best.weight))) \(wu.displayName) × \(best.reps)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                }
            }
        }.card()
    }

    @ViewBuilder private func exerciseCountLabel(_ count: Int) -> some View {
        #if os(Android)
        Label {
            Text("\(count) exercises")
        } icon: {
            DumbbellShape().fill(Theme.textSecondary).frame(width: 11, height: 11)
        }
        #else
        Label("\(count) exercises", systemImage: "dumbbell")
        #endif
    }

    /// iOS resolves body parts inline exactly as before. Android reads the
    /// Snapshot-precomputed chips — `ExerciseDatabase.bodyPart(for:)` is a
    /// catalog lookup and would run per exercise per card on every
    /// recomposition (directive 0e).
    private func bodyPartChips(for s: WorkoutSummary) -> [String] {
        #if os(Android)
        return bodyPartsByWorkout[s.workout.id ?? -1] ?? []
        #else
        return Array(Set(s.exercises.map { ExerciseDatabase.bodyPart(for: $0) })).sorted()
        #endif
    }

    // Extracted so the health-gate at the call site (#1070/#1064) reads as one
    // line and iOS renders it byte-for-byte as before.
    @ViewBuilder private var burnMetricsBand: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                #if os(Android)
                // No fire glyph in skip-ui's map — the star fallback
                // read as a rating (FlameGlyph.swift).
                FlameShape().fill(Theme.stepsOrange).frame(width: 12, height: 12)
                #else
                Image(systemName: "flame.fill").font(.caption).foregroundStyle(Theme.stepsOrange)
                #endif
                Text("\(Int(activeCalories))").font(.subheadline.weight(.bold).monospacedDigit())
                Text("active cal").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity).card()

            HStack(spacing: 4) {
                Image(systemName: sym("figure.walk")).font(.caption).foregroundStyle(Theme.deficit)
                Text(steps >= 1000 ? String(format: "%.1fk", steps/1000) : "\(Int(steps))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("steps").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity).card()
        }
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
        // The shared pinned formatter, never an ad-hoc one: an unpinned
        // DateFormatter parses as UTC on Android, so a workout dated today
        // rendered as yesterday in the history card (#1076).
        guard let date = DateFormatters.dateOnly.date(from: String(d.prefix(10))) else { return d }
        return DateFormatters.dayDisplay.string(from: date)
    }
    #if DRIFT_IOS_APP
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
    #endif
    /// Empty-state actions — extracted (#941): three buttons inline pushed the
    /// enclosing ViewBuilder past the type-checker's budget.
    private var emptyTemplatesActions: some View {
        VStack(spacing: 12) {
            Text("No templates yet").font(.caption).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 12) {
                #if DRIFT_IOS_APP
                Button { showingImport = true } label: {
                    Label("Import", systemImage: sym("square.and.arrow.down")).font(.caption)
                }.buttonStyle(.bordered)
                #endif
                // Three packages don't fit as siblings — collapse into a menu.
                Menu {
                    Button { loadPackage(DefaultTemplates.loadPackageI, name: "Drift Package I") } label: {
                        Label("Drift Package I", systemImage: sym("1.circle"))
                    }
                    Button { loadPackage(DefaultTemplates.loadPackageII, name: "Drift Package II") } label: {
                        Label("Drift Package II", systemImage: sym("2.circle"))
                    }
                    Button { loadPackage(DefaultTemplates.loadPackageIII, name: "Drift Package III") } label: {
                        Label("Drift Package III (Bands)", systemImage: sym("3.circle"))
                    }
                    Button { loadPackage(DefaultTemplates.loadPackageIV, name: "Drift Package IV") } label: {
                        Label("Drift Package IV", systemImage: sym("4.circle"))
                    }
                } label: {
                    Label("Drift Packages", systemImage: sym("square.stack.3d.up")).font(.caption)
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
        #if os(Android)
        // AppDatabase work on the UI thread ANRs debug builds on Android
        // (unlike iOS, where this whole load runs inline). Same queries, moved
        // off-main and applied as one Snapshot.
        isLoading = true
        lastLoadedAt = Date()
        Task {
            let snapshot = await Self.fetchSnapshot()
            workouts = snapshot.workouts
            weeklyCounts = snapshot.weeklyCounts
            templates = snapshot.templates
            streak = snapshot.streak
            overloadAlerts = snapshot.overloadAlerts
            bodyPartsByWorkout = snapshot.bodyPartsByWorkout
            isLoading = false
        }
        #else
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
        #endif
    }

    #if os(Android)
    struct Snapshot: @unchecked Sendable {
        var workouts: [WorkoutSummary] = []
        var weeklyCounts: [(weekStart: Date, count: Int)] = []
        var templates: [WorkoutTemplate] = []
        var streak: (current: Int, longest: Int)?
        var overloadAlerts: [PlateauResult] = []
        var bodyPartsByWorkout: [Int64: [String]] = [:]
    }

    /// Off-main load — every query the iOS `loadData()` runs inline, plus the
    /// body-hoisted per-workout body-part chip lookup, so the Android view body
    /// does zero DB/catalog work.
    static func fetchSnapshot() async -> Snapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var s = Snapshot()
                let raw = (try? WorkoutService.fetchWorkouts(limit: 500)) ?? []
                s.workouts = (try? WorkoutService.buildSummaries(for: raw)) ?? []
                s.weeklyCounts = (try? WorkoutService.weeklyWorkoutCounts(weeks: 12)) ?? []
                s.templates = (try? WorkoutService.fetchTemplates()) ?? []
                s.streak = try? WorkoutService.workoutStreak()
                s.overloadAlerts = ProgressiveOverloadService.allPlateaus()
                var chips: [Int64: [String]] = [:]
                for summary in s.workouts {
                    guard let wid = summary.workout.id else { continue }
                    chips[wid] = Array(Set(summary.exercises.map { ExerciseDatabase.bodyPart(for: $0) })).sorted()
                }
                s.bodyPartsByWorkout = chips
                continuation.resume(returning: s)
            }
        }
    }
    #endif

    private func streakRow(current: Int, longest: Int) -> some View {
        let label = current == 1 ? "week" : "weeks"
        return HStack {
            #if os(Android)
            FlameShape().fill(.orange).frame(width: 17, height: 17)
            #else
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            #endif
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
