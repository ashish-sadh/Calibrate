import SwiftUI
import DriftCore
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(UserNotifications) && !os(Android)
import UserNotifications
#endif

// MARK: - Active Workout (with live timer, rest timer, prefilled weights)
//
// SharedUI single-source — ONE file compiles into the iOS app and the Skip
// Fuse Android app (#1064 directive 1c). Deviations from the pre-port iOS
// file, each SkipUI/platform-forced:
//   · property wrappers lose `private` (Skip constraint)
//   · SF Symbol names route through sym()
//   · Timer.scheduledTimer → SecondTicker (Timer on Darwin; Task loop on
//     Android, where swift-corelibs Timer needs a RunLoop nobody pumps)
//   · rest-end UNUserNotification + AudioToolbox vibrate are Darwin-gated —
//     Android rest-end cue is visual-only until the notification seam lands
//   · share: UIActivityViewController on iOS (tap-time read, #967);
//     ShareLink on Android (text is frozen before the sheet opens)
//   · Haptics is an app-target type → DRIFT_IOS_APP. The command strip's coach
//     questions now run on both platforms via DriftCore's CoachCloud (#1064)
//   · notes TextField(axis:) is Darwin-only (SkipUI renders it single-line)

struct ActiveWorkoutView: View {
    @Environment(\.scenePhase) var scenePhase
    var template: WorkoutTemplate? = nil
    var pastDate: Date? = nil  // Non-nil = logging a past workout (no timer)
    let onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State var workoutName = defaultWorkoutName()
    @State var workoutDate = Date()
    @State var workoutNotes = ""
    @State var exercises: [ActiveExercise] = []
    /// Exercise notes as they stood when this workout opened, keyed by exercise
    /// name — the baseline `syncNotesToTemplate()` diffs against (#1169).
    ///
    /// Needed because `addExercise` auto-fills `"Tip: …"` from
    /// `ExerciseService.formTip(for:)` when a template exercise has no note.
    /// Without a baseline, a plain "start template, finish workout" round trip
    /// would write every generated tip into the user's template as if they had
    /// typed it. Only notes that differ from this snapshot are the user's.
    @State var notesAtOpen: [String: String] = [:]
    @State var showingExercisePicker = false
    @State var startTime = Date()
    @State var workoutTimer = SecondTicker()
    // Global rest timer state. The 1s countdown display lives in
    // RestTimerBar's own @State (#1074) — this level only tracks which set
    // is resting and when rest ends.
    @State var restTotalSeconds = 90
    @State var restTimerActive = false
    @State var restTimer = SecondTicker()
    @State var restEndTime: Date?
    // Rest-bar anchor by STABLE IDs, never array indices — deleting or
    // adding an exercise/set above the resting row shifts every index, which
    // made the running rest bar jump to whatever row inherited the index
    // (field report 2026-07-16: "timer randomly starts on different
    // exercises"). Five paths mutate these arrays mid-rest: delete set,
    // remove exercise (card menu), chat-strip "drop X", chat-add undo, and
    // the auto-added next set.
    @State var activeRestExerciseID: UUID? = nil
    @State var activeRestSetID: UUID? = nil
    @State var workoutEnded = false  // prevents re-persisting after finish/cancel
    @State var showingFinishOptions = false
    @State var showingCloseOptions = false
    @State var templateName = ""
    @State var showingTemplateName = false
    @State var saveAsTemplateToggle = false
    @State var favoriteAllToggle = false
    @State var showingCompletionSheet = false
    @State var completionShareText = ""
    @State var completionMilestone: String? = nil
    // Send-to-friend (sharing): the finished workout's sets + inline picker
    // state. Inline (a mode flip inside the completion sheet), not a nested
    // sheet — Skip Fuse breaks on stacked presentations.
    @State var completedSets: [SharingService.SharedSet] = []
    @State var friendSendMode = false
    // Finishing a workout shares it automatically; these two switches are the
    // escape hatch for a session you're only testing (operator 2026-07-29).
    // Seeded from the persisted preference so a coach-only user sets it once.
    @State var shareToFriends = Preferences.shareWorkoutsWithFriends
    @State var shareToCoaches = Preferences.shareWorkoutsWithCoaches
    @State var broadcastResult: WorkoutBroadcast.Result? = nil
    /// Whether this session may appear on the PUBLIC profile a stranger can open
    /// from a global leaderboard. Separate axis from the two switches above.
    @State var showOnPublicProfile = Preferences.showWorkoutsOnPublicProfile
    // Command strip — say it, don't hunt for it: "add face pulls",
    // "drop curls", "last bench?" (exercise-UX design 2026-07-10)
    @State var commandText = ""
    @State var commandFeedback: CommandFeedback? = nil
    @FocusState var commandFocused: Bool
    // Coach toast — transient encouragement on set/exercise milestones
    // (operator 2026-07-12: "feels like a real coach and it disappears")
    @State var coachToast: String? = nil
    @State var coachToastToken = 0
    @State var encouragementTick = 0
    // Soft typo guard — set while a fat-finger entry awaits confirmation.
    @State var sanityPrompt: SanityPrompt? = nil

    struct CommandFeedback {
        let text: String
        var undo: (() -> Void)? = nil
    }

    /// A set whose entered number looked like a typo, held until the user
    /// confirms or goes back to fix it. Anchored by stable IDs, not indices.
    struct SanityPrompt: Identifiable {
        let id = UUID()
        let exerciseID: UUID
        let setID: UUID
        let message: String
    }

    struct ActiveExercise: Identifiable {
        let id = UUID()
        var name: String
        var restTime: Int = 90
        var isWarmupExercise: Bool = false  // entire exercise is warmup (from template)
        var notes: String?                   // trainer notes (e.g. "6-8 reps")
        var sets: [ActiveSet]
        var previousSets: [String]
        /// Last session's top working weight (lbs) — the beat-last-time toast
        /// baseline. Nil (no toast) for restored sessions and fresh exercises.
        var lastMaxWeight: Double? = nil
        /// Reps↔timer tracking. Defaults to the name classifier; user-flippable
        /// per exercise from the exercise menu (operator 2026-07-14).
        var trackByTime: Bool = false
        /// Weight-entry unit for this exercise's fields. Storage stays lbs
        /// (`WorkoutSet.weightLbs`); this only sets how typed numbers are read.
        /// Explicit OPTION, not suffix parsing (operator 2026-07-14). Defaults
        /// from the app-wide weight-unit preference.
        var weighInKg: Bool = Preferences.weightUnit == .kg

        init(name: String, restTime: Int = 90, isWarmupExercise: Bool = false,
             notes: String? = nil, sets: [ActiveSet], previousSets: [String],
             lastMaxWeight: Double? = nil, trackByTime: Bool? = nil, weighInKg: Bool? = nil) {
            self.name = name
            self.restTime = restTime
            self.isWarmupExercise = isWarmupExercise
            self.notes = notes
            self.sets = sets
            self.previousSets = previousSets
            self.lastMaxWeight = lastMaxWeight
            self.trackByTime = trackByTime ?? WorkoutSet.isDurationExercise(name)
            self.weighInKg = weighInKg ?? (Preferences.weightUnit == .kg)
        }

        /// This exercise's weight-entry unit. Storage stays lbs.
        var weightUnit: WeightUnit { weighInKg ? .kg : .lbs }

        /// Interpret a typed weight in this exercise's unit → stored lbs.
        /// Anything that *writes* a weight into a set field must use the
        /// inverse (`weightUnit.entryText(fromLbs:)`) — see #1084.
        func enteredWeightLbs(_ text: String) -> Double? {
            weightUnit.entryTextToLbs(text)
        }
    }

    struct ActiveSet: Identifiable {
        let id = UUID()
        var weight: String
        var reps: String
        var done: Bool = false
        var isWarmup: Bool = false  // individual set warmup toggle
    }

    /// Shared between the iOS toolbar and the Android in-content header
    /// (SkipUI's nav bar inside a sheet wastes an ~80dp band, #1089 pattern).
    private var closeButton: some View {
        // Native confirmation dialog, not a bare Menu popover — discarding a
        // workout is consequential and the naked two-row menu read as
        // unfinished chrome (field report 2026-07-09). Labels say what
        // actually happens.
        Button { showingCloseOptions = true } label: {
            Image(systemName: sym("xmark.circle")).foregroundStyle(Theme.textSecondary)
        }
        .confirmationDialog("Workout in progress", isPresented: $showingCloseOptions, titleVisibility: .visible) {
            // Away time doesn't count once the sheet is closed — the clock
            // resumes from trained time (see restoreSession).
            Button("Minimize — resume anytime") { persistSession(); dismiss() }
            Button("Discard workout", role: .destructive) {
                workoutEnded = true
                WorkoutService.clearSession(); stopTimers(); dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Minimized workouts show as a bar you can resume from any tab. Discarding deletes the logged sets.")
        }
    }

    @ViewBuilder private var finishButton: some View {
        if !exercises.isEmpty {
            Button("Finish") { showingFinishOptions = true }.foregroundStyle(Theme.deficit)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    #if os(Android)
                    // SkipUI's nav bar inside a sheet reserves an ~80dp dead
                    // band above the toolbar row (#1089 pattern) — render the
                    // X/Finish controls as content on Android instead. iOS 26
                    // draws its own glass chrome behind these in the real
                    // toolbar (scout "workout-chrome" finding #1) — replicate
                    // it here since Android gets no free system chrome.
                    HStack {
                        closeButton.toolbarCircleChrome()
                        Spacer()
                        finishButton.toolbarPillChrome()
                    }
                    .padding(.horizontal, 4)
                    #endif
                    // Workout header
                    VStack(spacing: 6) {
                        TextField("Workout name", text: $workoutName)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                        if pastDate != nil {
                            // Past workout: date picker. Label-closure init +
                            // ClosedRange — the title-string and PartialRange
                            // forms are unavailable in SkipSwiftUI.
                            DatePicker(selection: $workoutDate, in: Date.distantPast...Date(), displayedComponents: .date) { Text("Date") }
                                .labelsHidden()
                                .font(.caption)
                        } else {
                            // Live workout: date + timer
                            HStack(spacing: 12) {
                                Label(DateFormatters.dayDisplay.string(from: Date()), systemImage: sym("calendar"))
                                WorkoutClockLabel(startTime: startTime, style: .headerLabel)
                            }
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }.padding(.horizontal, 12)

                    // Notes (collapsed by default)
                    if !workoutNotes.isEmpty || exercises.count > 0 {
                        WorkoutNotesField(text: $workoutNotes)
                    }

                    // Quick add exercise at top (useful when template already has many)
                    if exercises.count >= 3 {
                        Button { showingExercisePicker = true } label: {
                            Label("Add Exercise", systemImage: sym("plus.circle")).font(.caption)
                        }.buttonStyle(.bordered).tint(Theme.accent).padding(.horizontal, 12)
                    }

                    // Warmup exercises — iterate by stable UUID so a removal during
                    // animation can't produce a stale integer index (build-146 crash class).
                    let warmup = exercises.filter { $0.isWarmupExercise }
                    let working = exercises.filter { !$0.isWarmupExercise }

                    if !warmup.isEmpty {
                        Text("WARMUP").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                            .padding(.horizontal, 16)
                        ForEach(warmup) { ex in
                            if let ei = exercises.firstIndex(where: { $0.id == ex.id }) {
                                exerciseSection(ei)
                            }
                        }

                        if !working.isEmpty {
                            Divider().padding(.horizontal, 16).padding(.vertical, 4)
                            Text("WORKING SETS").font(.caption2.weight(.bold)).foregroundStyle(Theme.calorieBlue)
                                .padding(.horizontal, 16)
                        }
                    }

                    // Working exercises
                    ForEach(working) { ex in
                        if let ei = exercises.firstIndex(where: { $0.id == ex.id }) {
                            exerciseSection(ei)
                        }
                    }

                    // Add exercise
                    Button { showingExercisePicker = true } label: {
                        Text("Add Exercise").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(Theme.accent).padding(.horizontal, 12)

                    if !exercises.isEmpty {
                        Button { showingFinishOptions = true } label: {
                            Text("Finish").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(Theme.accent).padding(.horizontal, 12)

                        Button("Cancel Workout", role: .destructive) {
                            workoutEnded = true
                            WorkoutService.clearSession(); stopTimers(); dismiss()
                        }.font(.caption).padding(.top, 4)
                    }
                }.padding(.top, 8).padding(.bottom, 24)
            }
            // SkipUI bridges scrollDismissesKeyboard to a Compose nested-scroll
            // connection that consumes pointer input inside the scroller, so every
            // SetCellField below it stops taking focus taps — weight/reps were
            // completely uneditable on Android (verified 2026-07-20: mInputShown
            // stayed false tapping set fields, while the command strip outside this
            // ScrollView focused fine). Compose hides the IME on scroll by default.
            #if !os(Android)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { commandStrip }
            .overlay(alignment: .top) {
                if let toast = coachToast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.ink, in: Capsule())
                        .shadowSoft(cornerRadius: 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("coach-toast")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #if !os(Android)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { closeButton }
                ToolbarItem(placement: .confirmationAction) { finishButton }
            }
            #endif
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { name in
                    addExercise(name: name)
                }
            }
            // Soft typo guard — a fat-finger number asks "sure?" before logging.
            .confirmationDialog(
                sanityPrompt?.message ?? "",
                isPresented: Binding(get: { sanityPrompt != nil },
                                     set: { if !$0 { sanityPrompt = nil } }),
                titleVisibility: .visible
            ) {
                Button("Yes, log it") {
                    if let p = sanityPrompt { markSetDone(exerciseID: p.exerciseID, setID: p.setID) }
                    sanityPrompt = nil
                }
                Button("Let me fix it", role: .cancel) { sanityPrompt = nil }
            }
            .sheet(isPresented: $showingFinishOptions) {
                NavigationStack {
                    ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: sym("checkmark.circle.fill"))
                            .font(.system(size: Theme.FontSize.display4))
                            .foregroundStyle(Theme.deficit)
                            .padding(.top, 24)

                        Text("Nice work!").font(.title2.weight(.bold))

                        // Workout summary
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                WorkoutClockLabel(startTime: startTime, style: .summaryStat)
                                Text("Duration").font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            Divider().frame(height: 28)
                            VStack(spacing: 2) {
                                Text("\(exercises.count)").font(.title3.weight(.bold).monospacedDigit())
                                Text("Exercises").font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            Divider().frame(height: 28)
                            VStack(spacing: 2) {
                                let totalSets = exercises.flatMap(\.sets).filter(\.done).count
                                Text("\(totalSets)").font(.title3.weight(.bold).monospacedDigit())
                                Text("Sets").font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .card()

                        // Save as template toggle
                        Toggle(isOn: $saveAsTemplateToggle) {
                            Label("Save as template", systemImage: sym("doc.on.doc"))
                                .font(.subheadline)
                        }
                        .tint(Theme.accent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))

                        // Favorite all exercises toggle
                        Toggle(isOn: $favoriteAllToggle) {
                            Label("Favorite all exercises", systemImage: sym("star"))
                                .font(.subheadline)
                        }
                        .tint(Theme.fatYellow)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))

                        if saveAsTemplateToggle {
                            TextField("Template name", text: $templateName)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                                .padding(12)
                                .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
                        }

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
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    }  // ScrollView
                    .background(Theme.background)
                    // Same Android focus-starvation reason as the main ScrollView
                    // above — this sheet holds the template-name TextField.
                    #if !os(Android)
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { showingFinishOptions = false }
                        }
                    }
                }
                .presentationDetents([.fraction(0.75), .large])
            }
            .sheet(isPresented: $showingCompletionSheet) {
                // Dismiss everything when completion sheet closes
                onComplete(); dismiss()
            } content: {
                completionSheet()
            }
            .onAppear {
                // The workout is on screen — hide the root minimized pill (#1167).
                LiveWorkoutMonitor.shared.setPresented(true)
                if let pd = pastDate {
                    workoutDate = pd
                    workoutName = "Workout"
                }
                // Live workouts: restore session + start timer
                if pastDate == nil {
                    let restored = restoreSession()
                    startWorkoutTimer()
                    if restored {
                        // A restored session's notes are already whatever they
                        // were last saved as — and anything edited before the
                        // kill has already synced on a persist tick. Baseline
                        // from here so a resume never re-writes the template.
                        captureNotesBaseline()
                        return
                    }
                }
                if let t = template {
                    workoutName = t.name
                    // Smart sessions (no DB id) — use coach reasoning as workout notes
                    if t.id == nil, let reasoning = ExerciseService.lastSessionReasoning {
                        workoutNotes = reasoning
                    }
                    let warmups = t.exercises.filter(\.isWarmup)
                    let working = t.exercises.filter { !$0.isWarmup }
                    // Add warmup exercises
                    for ex in warmups {
                        addExercise(name: ex.name, setCount: ex.sets, restTime: ex.restSeconds, isWarmup: true, notes: ex.notes, trackByTime: ex.isDuration)
                    }
                    // Add working exercises
                    for ex in working {
                        addExercise(name: ex.name, setCount: ex.sets, restTime: ex.restSeconds, notes: ex.notes, trackByTime: ex.isDuration)
                    }
                    captureNotesBaseline()
                }
            }
            .onDisappear {
                stopTimers()
                // Only persist if workout wasn't finished or cancelled
                if !workoutEnded && !exercises.isEmpty { persistSession() }
                // Sheet is gone: if a session was just persisted (minimize), the
                // root pill appears; if it was finished/cancelled (session
                // cleared), it stays hidden. setPresented re-reads which (#1167).
                LiveWorkoutMonitor.shared.setPresented(false)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && !workoutEnded {
                    // Restart workout timer — elapsed recalculates from
                    // startTime. Past-date logging has NO live timer, so
                    // don't start one on foregrounding (it silently ticked
                    // a phantom clock for backdated workouts).
                    if pastDate == nil {
                        workoutTimer.invalidate()
                        startWorkoutTimer()
                    }
                    // Update rest timer from wall-clock end time — the bar's
                    // display re-syncs itself on foreground (RestTimerBar
                    // watches scenePhase too).
                    if restTimerActive, let endTime = restEndTime {
                        let remaining = Int(endTime.timeIntervalSince(Date()))
                        if remaining > 0 {
                            restTimer.invalidate()
                            startRestTimerTick()
                        } else {
                            // Rest finished while in background —
                            // background notification already fired the
                            // alert + sound; no extra vibration here or
                            // the user gets buzzed twice.
                            restTimer.invalidate()
                            restTimerActive = false
                            cancelRestEndNotification()
                        }
                    }
                } else if newPhase == .background && !workoutEnded && !exercises.isEmpty {
                    // Persist immediately on background so a mid-workout app
                    // termination is recoverable — restoreSession() restores
                    // startTime and the overall timer continues from real
                    // elapsed instead of restarting at 0. (Was only persisted
                    // every 30s / on the in-app Minimize button, so a quick
                    // minimize-then-kill lost the start time.)
                    persistSession()
                }
            }
        }
    }

    // MARK: - Exercise Section

    // Both platforms scroll, with different detents. Compose's `.medium` is
    // shorter than iOS's, and when the content overflows it compresses the
    // trailing child rather than growing the sheet — which collapsed "Done"
    // to an unreadable pink sliver (#1076). A long share text (many
    // exercises) or a long recipient list overflows any fixed detent.
    private func completionSheet() -> some View {
        let card = VStack(spacing: 20) {
            if let milestone = completionMilestone {
                Text("🎉").font(.system(size: Theme.FontSize.display4))
                Text(milestone).font(.title2.weight(.bold))
            } else {
                Text("💪").font(.system(size: Theme.FontSize.display4))
                Text("Workout Complete").font(.title2.weight(.bold))
            }

            Text(completionShareText)
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            #if canImport(UIKit)
            Button {
                // ShareLink(item:) snapshots the @State at render time (#967) —
                // UIActivityViewController reads the text at tap time so it's
                // always populated (mirrors WorkoutDetailView's ShareSheet pattern).
                let vc = UIActivityViewController(
                    activityItems: [completionShareText], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes
                       .compactMap({ $0 as? UIWindowScene }).first,
                   let root = (scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first)?.rootViewController {
                    // #1023: the completion sheet is already presented from `root`, so
                    // presenting the share sheet from root silently no-ops. Walk to the
                    // top-most presented controller and present from there.
                    var top = root
                    while let presented = top.presentedViewController { top = presented }
                    top.present(vc, animated: true)
                }
            } label: {
                Label("Share", systemImage: sym("square.and.arrow.up")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #else
            // Android: the text is final before this sheet presents, so
            // ShareLink's render-time snapshot (#967) can't bite here.
            ShareLink(item: completionShareText) {
                Label("Share", systemImage: sym("square.and.arrow.up")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #endif

            friendShareSection

            Button("Done") { showingCompletionSheet = false }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)

        #if os(Android)
        return ScrollView { card }
            .presentationDetents([.fraction(0.75), .large])
            .background(Theme.background)
        #else
        // iOS scrolls too since the friend picker joined the sheet — a long
        // recipient list overflows any fixed detent. `.medium` stays the
        // resting height; `.large` gives the list room.
        return ScrollView { card }
            .presentationDetents([.medium, .large])
            .background(Theme.background)
        #endif
    }

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
                    // Ink, not coral (calorieBlue aliases the brand coral) —
                    // five coral titles per screen drowned the real CTAs
                    // (design pass 2026-07-10). Warmups keep the amber cue.
                    Text(exercises[ei].name).font(.subheadline.weight(.bold))
                        .foregroundStyle(exercises[ei].isWarmupExercise ? Theme.fatYellow : Theme.textPrimary)
                }
                Text(guessGroup(exercises[ei].name)).font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()
                // Rest time customizer
                Menu {
                    ForEach([30, 60, 90, 120, 150, 180], id: \.self) { sec in
                        Button("\(sec / 60):\(String(format: "%02d", sec % 60))") {
                            exercises[ei].restTime = sec
                        }
                    }
                } label: {
                    // Quiet gray rest chip — the coral pill read as a CTA.
                    Text("\(exercises[ei].restTime / 60):\(String(format: "%02d", exercises[ei].restTime % 60))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 4))
                }
                Menu {
                    let name = exercises[ei].name
                    let isFav = WorkoutService.exerciseFavorites.contains(name)
                    Button {
                        WorkoutService.toggleExerciseFavorite(name)
                    } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: sym(isFav ? "star.slash" : "star"))
                    }
                    // Flip between rep counting and a seconds timer — planks,
                    // farmer carries, or any exercise the name classifier got
                    // wrong (operator 2026-07-14).
                    Button {
                        exercises[ei].trackByTime.toggle()
                    } label: {
                        #if os(Android)
                        // Material's mapped set has no timer — the calendar
                        // stand-in read as a DATE, right under the header's
                        // real calendar glyph. Drawn face instead (#1076).
                        if exercises[ei].trackByTime {
                            Label("Track by Reps", systemImage: sym("number"))
                        } else {
                            Label { Text("Track by Time") } icon: {
                                ClockFaceShape().fill(Theme.textSecondary)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        #else
                        Label(exercises[ei].trackByTime ? "Track by Reps" : "Track by Time",
                              systemImage: sym(exercises[ei].trackByTime ? "number" : "timer"))
                        #endif
                    }
                    Divider()
                    Button(role: .destructive) {
                        exercises.remove(at: ei)
                        stopRestIfAnchorMissing()
                    } label: {
                        Label("Remove Exercise", systemImage: sym("trash"))
                    }
                } label: {
                    Image(systemName: sym("xmark.circle.fill")).font(.subheadline).foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("Exercise options")
            }

            // Notes (editable - pre-filled from template). Android renders this
            // as a tap-to-edit surface (ExerciseNotesField) so no always-live
            // TextField exists for a sibling set-DONE tap to steal focus (#1103);
            // iOS keeps the live inline field — byte-identical converting binding.
            ExerciseNotesField(text: Binding(
                get: { exercises[ei].notes ?? "" },
                set: { exercises[ei].notes = $0.isEmpty ? nil : $0 }
            ))

            // Column headers
            let assisted = isAssistedExercise(exercises[ei].name)
            let isDuration = exercises[ei].trackByTime
            HStack(spacing: 0) {
                Text("Set").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 28, alignment: .leading)
                Text("Previous").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 85, alignment: .leading)
                // Tappable unit OPTION per exercise — kg lifters pick kg here
                // instead of converting in their head (stored as lbs).
                Menu {
                    Button("lbs") { exercises[ei].weighInKg = false }
                    Button("kg") { exercises[ei].weighInKg = true }
                } label: {
                    Text("\(assisted ? "-" : "")\(exercises[ei].weighInKg ? "kg" : "lbs") ▾")
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: setWeightColumnWidth)
                }
                .accessibilityLabel("Weight unit, currently \(exercises[ei].weighInKg ? "kilograms" : "pounds")")
                Text(isDuration ? "Time (s)" : "Reps").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: setRepsColumnWidth)
                Spacer()
                // A WORD, not a ✓ glyph (operator 2026-08-02: "what is this
                // check sign doing... it's confusing that people try to click
                // on it"). Every other header here is a word — Set, Previous,
                // lbs, Reps — so a lone checkmark read as the odd one out, and
                // it was the SAME glyph as the done-state control sitting
                // directly beneath it. A check above a column of tappable
                // circles looks like the button that ticks them all.
                Text("Done").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).frame(width: 30)
            }

            // Sets — index-based bindings, not `ForEach($exercises[ei].sets)`:
            // SkipUI renders TextFields bound through a binding-ForEach
            // projection as dead Text (typed input never lands). `si` was
            // already recomputed per render in the binding form, so the
            // semantics are unchanged; row identity stays the set's UUID.
            ForEach(Array(exercises[ei].sets.enumerated()), id: \.element.id) { si, set in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Button {
                            exercises[ei].sets[si].isWarmup.toggle()
                        } label: {
                            Text(set.isWarmup || exercises[ei].isWarmupExercise ? "W" : "\(si + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(set.isWarmup || exercises[ei].isWarmupExercise ? Theme.fatYellow : .secondary)
                        }.buttonStyle(.plain).frame(width: 28, alignment: .leading)

                        // Previous
                        Text(si < exercises[ei].previousSets.count ? exercises[ei].previousSets[si] : "—")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary).frame(width: 85, alignment: .leading)

                        // Weight
                        SetCellField(placeholder: si < exercises[ei].previousSets.count ? prevWeight(exercises[ei].previousSets[si]) : "0",
                                     text: $exercises[ei].sets[si].weight,
                                     decimal: true, width: setWeightColumnWidth, leadingPad: 0, done: set.done)

                        // Reps or Time
                        SetCellField(placeholder: isDuration ? "sec" : (si < exercises[ei].previousSets.count ? prevReps(exercises[ei].previousSets[si]) : "0"),
                                     text: $exercises[ei].sets[si].reps,
                                     decimal: false, width: setRepsColumnWidth, leadingPad: 4, done: set.done)

                        Spacer()

                        // Done button
                        Button {
                            // Un-checking never needs a guard; only committing does.
                            guard !exercises[ei].sets[si].done else {
                                exercises[ei].sets[si].done = false
                                return
                            }
                            // Soft typo guard: a fat-finger weight/reps entry
                            // (98 → 980) asks "sure?" before it's logged.
                            let s = exercises[ei].sets[si]
                            if let message = SetEntrySanity.warning(
                                weightLbs: exercises[ei].enteredWeightLbs(s.weight),
                                reps: Int(s.reps),
                                isDuration: exercises[ei].trackByTime,
                                previousTopWeightLbs: exercises[ei].lastMaxWeight,
                                unit: exercises[ei].weightUnit) {
                                sanityPrompt = SanityPrompt(exerciseID: exercises[ei].id, setID: set.id, message: message)
                            } else {
                                markSetDone(exerciseID: exercises[ei].id, setID: set.id)
                            }
                        } label: {
                            #if os(Android)
                            // Same fallback trap as the picker row: Material has
                            // no outline "circle", so sym() landed on
                            // `checkmark.circle` and every UN-DONE set drew a
                            // check — the one glyph that must not read as "done".
                            if set.done {
                                Image(systemName: sym("checkmark.circle.fill"))
                                    .font(.title3)
                                    .foregroundStyle(Theme.deficit)
                            } else {
                                // `.stroke` not `.strokeBorder` — SkipUI's
                                // strokeBorder overload set is ambiguous here.
                                Circle()
                                    .stroke(Color.secondary, lineWidth: 1.5)
                                    .frame(width: 21, height: 21)
                            }
                            #else
                            Image(systemName: set.done ? sym("checkmark.circle.fill") : sym("circle"))
                                .font(.title3)
                                .foregroundStyle(set.done ? Theme.deficit : .secondary)
                            #endif
                        }.frame(width: 30)

                        // Inline delete button.
                        //
                        // Separated from the done checkbox and given a hit area
                        // several times the glyph (#1168): at width 20 with zero
                        // spacing in a `spacing: 0` HStack, the two sat flush and
                        // reaching ✕ kept toggling the set done instead — the
                        // worst possible miss, since it logs a set you were
                        // trying to delete. The glyph stays small and tertiary;
                        // only the tappable rectangle grew.
                        Button {
                            exercises[ei].sets.removeAll(where: { $0.id == set.id })
                            if exercises[ei].sets.isEmpty { exercises.remove(at: ei) }
                            stopRestIfAnchorMissing()
                        } label: {
                            Image(systemName: sym("xmark"))
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 32, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .accessibilityLabel("Delete set")
                    }
                    .padding(.vertical, 2)
                    #if !os(Android)
                    // Long-press delete duplicates the inline ✕. Darwin-only:
                    // SkipUI's contextMenu wrapper (pointer-input long-press
                    // container) keeps child Buttons alive but starves the
                    // row's TextFields of focus taps — with it attached the
                    // weight/reps fields never become editable on Android.
                    .contextMenu {
                        Button(role: .destructive) {
                            exercises[ei].sets.removeAll(where: { $0.id == set.id })
                            if exercises[ei].sets.isEmpty { exercises.remove(at: ei) }
                            stopRestIfAnchorMissing()
                        } label: {
                            Label("Delete Set", systemImage: sym("trash"))
                        }
                    }
                    #endif

                    // Inline rest timer bar (shows after this set if active)
                    if restTimerActive, let restEnd = restEndTime,
                       activeRestExerciseID == exercises[ei].id && activeRestSetID == set.id {
                        RestTimerBar(endTime: restEnd, totalSeconds: restTotalSeconds)
                    }
                }
            }

            // Add set button — prefills from last set
            Button {
                let last = exercises[ei].sets.last
                exercises[ei].sets.append(ActiveSet(weight: last?.weight ?? "", reps: last?.reps ?? ""))
            } label: {
                Text("+ Set")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
        }
        .card().padding(.horizontal, 12)
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
        // The visible clock ticks inside WorkoutClockLabel's own @State
        // (#1074) — this timer only drives the 30s session auto-save, so its
        // per-second tick writes no view state and recomposes nothing.
        workoutTimer.schedule { [self] in
            Task { @MainActor in
                if Int(Date().timeIntervalSince(startTime)) % 30 == 0 && !exercises.isEmpty {
                    persistSession()
                }
            }
        }
    }

    /// Cancel the rest countdown entirely — bar, tick, and the background
    /// notification. A timer whose row was deleted would otherwise keep
    /// running invisibly and vibrate/notify for a set that no longer exists.
    private func stopRest() {
        restTimer.invalidate()
        restTimerActive = false
        restEndTime = nil
        activeRestExerciseID = nil
        activeRestSetID = nil
        cancelRestEndNotification()
    }

    /// Call after ANY removal from `exercises` — if the resting row is gone
    /// (set deleted, exercise removed via card menu / chat "drop X" / chat
    /// add-undo), the countdown dies with it.
    private func stopRestIfAnchorMissing() {
        guard restTimerActive else { return }
        if !Self.restAnchorAlive(exercises: exercises,
                                 exerciseID: activeRestExerciseID,
                                 setID: activeRestSetID) {
            stopRest()
        }
    }

    /// Pure: does the (exercise, set) the rest bar is anchored to still
    /// exist? Static so the regression tests can drive it directly.
    nonisolated static func restAnchorAlive(exercises: [ActiveExercise], exerciseID: UUID?, setID: UUID?) -> Bool {
        exercises.first { $0.id == exerciseID }?
            .sets.contains { $0.id == setID } ?? false
    }

    private func startRest(exerciseID: UUID, setID: UUID, duration: Int) {
        restTotalSeconds = duration
        restEndTime = Date().addingTimeInterval(Double(duration))
        activeRestExerciseID = exerciseID
        activeRestSetID = setID
        restTimerActive = true
        restTimer.invalidate()
        startRestTimerTick()
        // Field bug 2026-05-24 (saketh): "the timer in the exercise part
        // of Drift doesn't go off unless I'm sitting on the page."
        // `Timer.scheduledTimer` runs on the main RunLoop which iOS
        // suspends in background — the haptic never fires when the user
        // puts the phone down between sets. Schedule a local notification
        // with the same delay so iOS fires it regardless of app state.
        // The in-app display timer stays as-is for foreground UX.
        scheduleRestEndNotification(after: duration)
    }

    private func startRestTimerTick() {
        // The countdown display ticks inside RestTimerBar's own @State
        // (#1074) — this watcher only fires the completion side effects.
        restTimer.schedule {
            Task { @MainActor in
                guard let endTime = restEndTime else { return }
                guard Int(ceil(endTime.timeIntervalSince(Date()))) <= 0 else { return }
                restTimer.invalidate()
                restTimerActive = false
                restEndTime = nil
                #if canImport(AudioToolbox)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                #endif
                // Foreground completion — clear the backup
                // notification so it doesn't fire a moment later.
                cancelRestEndNotification()
            }
        }
    }

    private func stopTimers() {
        workoutTimer.invalidate()
        restTimer.invalidate()
        cancelRestEndNotification()
    }

    // MARK: - Rest-end notification (background fallback)

    #if canImport(UserNotifications) && !os(Android)
    /// Identifier used so we can replace / cancel the pending request
    /// without touching any other Drift notification.
    private static let restEndNotificationID = "drift.workout.rest.end"

    /// Schedules a local notification that fires after `seconds`. iOS
    /// delivers it whether or not the app is foregrounded — fixes the
    /// "timer doesn't go off when phone is down" report.
    private func scheduleRestEndNotification(after seconds: Int) {
        guard seconds > 0 else { return }
        let center = UNUserNotificationCenter.current()
        // Always remove any prior pending request before scheduling a
        // new one — the user may have started a new set before the
        // previous rest completed.
        center.removePendingNotificationRequests(withIdentifiers: [Self.restEndNotificationID])

        let content = UNMutableNotificationContent()
        content.title = "Rest finished"
        content.body = "Time to start your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: Self.restEndNotificationID, content: content, trigger: trigger)

        // Request auth lazily — first set finishes ⇒ user sees prompt.
        // If they decline, scheduling no-ops; the in-app timer still
        // works when they're on the page.
        // #943 audit: explicit @Sendable — these callbacks arrive on
        // background queues; an inferred-@MainActor literal asserts at entry.
        center.getNotificationSettings { @Sendable settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, _ in
                    if granted { center.add(request, withCompletionHandler: nil) }
                }
            case .authorized, .provisional, .ephemeral:
                center.add(request, withCompletionHandler: nil)
            case .denied: break
            @unknown default: break
            }
        }
    }

    private func cancelRestEndNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.restEndNotificationID])
    }
    #else
    // Android: no local-notification seam yet (#1064 residual → notification
    // adapter). The in-app countdown + bar still run; rest-end is visual-only.
    private func scheduleRestEndNotification(after seconds: Int) {}
    private func cancelRestEndNotification() {}
    #endif

    // MARK: - Session Persistence

    /// Snapshot the current exercise notes as "untouched". First occurrence
    /// wins so a template with the same exercise twice keys consistently with
    /// `templateExercisesApplyingNoteEdits`.
    private func captureNotesBaseline() {
        notesAtOpen = Dictionary(exercises.map { ($0.name, $0.notes ?? "") },
                                 uniquingKeysWith: { first, _ in first })
    }

    /// Write notes the user edited mid-workout back to the source template
    /// (#1169). Cheap no-op when nothing changed, so the 30s persist tick and
    /// the finish path can both call it.
    private func syncNotesToTemplate() {
        guard let t = template, let tid = t.id else { return }
        let edited = Dictionary(exercises.map { ($0.name, $0.notes ?? "") },
                                uniquingKeysWith: { first, _ in first })
        guard let merged = WorkoutService.templateExercisesApplyingNoteEdits(
                t.exercises, edited: edited, baseline: notesAtOpen),
              let json = try? JSONEncoder().encode(merged),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        WorkoutService.updateTemplate(id: tid, name: t.name, exercisesJson: jsonStr)
        // Re-baseline, or every later tick re-writes the same edit.
        notesAtOpen = edited
    }

    private func persistSession() {
        // A finished/discarded workout must never re-persist. The 30s
        // auto-save tick hops through an async Task, so one enqueued just
        // before Finish would otherwise run AFTER clearSession() and
        // resurrect the session (2026-07-13 double-save field bug —
        // WorkoutService.saveSession also tombstones this at the service
        // level; this guard is the cheap first line).
        guard !workoutEnded else { return }
        syncNotesToTemplate()
        let sessionExercises = exercises.map { ex in
            WorkoutService.SavedSession.SessionExercise(
                name: ex.name, isWarmup: ex.isWarmupExercise,
                notes: ex.notes, restTime: ex.restTime,
                sets: ex.sets.map { s in
                    WorkoutService.SavedSession.SessionSet(
                        weight: s.weight, reps: s.reps, done: s.done, isWarmup: s.isWarmup)
                },
                trackByTime: ex.trackByTime,
                weighInKg: ex.weighInKg)
        }
        WorkoutService.saveSession(.init(workoutName: workoutName, startTime: startTime, exercises: sessionExercises))
    }

    private func restoreSession() -> Bool {
        guard let session = WorkoutService.loadSession() else { return false }
        workoutName = session.workoutName
        // Resume the clock at the duration actually TRAINED, not wall-clock
        // since the original start — resuming a session from hours ago used
        // to start the timer at those hours (field report 2026-07-16).
        // Rebasing startTime keeps every downstream `now − startTime`
        // computation (tick, scenePhase recalc, finish-save duration)
        // correct without touching them.
        startTime = Date().addingTimeInterval(-session.trainedSeconds())
        exercises = session.exercises.map { ex in
            ActiveExercise(
                name: ex.name, restTime: ex.restTime, isWarmupExercise: ex.isWarmup,
                notes: ex.notes,
                sets: ex.sets.map { s in ActiveSet(weight: s.weight, reps: s.reps, done: s.done, isWarmup: s.isWarmup) },
                previousSets: [],
                trackByTime: ex.trackByTime,
                weighInKg: ex.weighInKg)
        }
        return true
    }

    // MARK: - Add Exercise (with prefill)

    private func addExercise(name: String, setCount: Int? = nil, restTime: Int = 90, isWarmup: Bool = false, notes: String? = nil, trackByTime: Bool? = nil) {
        let allHistory = (try? WorkoutService.fetchExerciseHistory(name: name)) ?? []

        // Get the most recent workout's sets for this exercise (in set_order)
        // History is ordered by id DESC, so first entry is from most recent workout
        let lastWorkoutId = allHistory.first?.workoutId
        let lastSession = lastWorkoutId.map { wid in
            allHistory.filter { $0.workoutId == wid }.sorted { $0.setOrder < $1.setOrder }
        } ?? []

        // The unit this exercise's fields will be typed in. Prefilled text and
        // the `Previous` line must BOTH be rendered in it — history is stored
        // in lbs, and writing those raw lbs into a kg field made every save
        // re-multiply the weight by 2.20462 (#1084).
        let unit = Preferences.weightUnit

        let previous = lastSession.prefix(5).map { s in
            "\(unit.entryText(fromLbs: s.weightLbs ?? 0)) \(unit.displayName) \u{00D7} \(s.reps ?? 0)"
        }

        let count = setCount ?? (lastSession.isEmpty ? 3 : max(lastSession.count, 3))
        var sets: [ActiveSet] = []
        for i in 0..<count {
            if i < lastSession.count {
                let s = lastSession[i]
                sets.append(ActiveSet(weight: s.weightLbs.map { unit.entryText(fromLbs: $0) } ?? "",
                                      reps: s.reps.map { String($0) } ?? "", isWarmup: isWarmup))
            } else {
                sets.append(ActiveSet(weight: "", reps: "", isWarmup: isWarmup))
            }
        }

        // Auto-add form tip if no notes provided
        let finalNotes = notes ?? ExerciseService.formTip(for: name).map { "Tip: \($0)" }
        exercises.append(ActiveExercise(name: name, restTime: restTime, isWarmupExercise: isWarmup,
                                         notes: finalNotes, sets: sets, previousSets: Array(previous),
                                         lastMaxWeight: lastSession.compactMap(\.weightLbs).max(),
                                         trackByTime: trackByTime,
                                         // Explicit, not defaulted: the sets above were rendered in
                                         // `unit`, so the exercise must read them back in `unit`.
                                         weighInKg: unit == .kg))
    }

    // MARK: - Coach toast (transient encouragement on milestones)

    /// Pick and show the coach line for a just-completed set. Priority:
    /// beat-last-time > exercise/workout complete > plain set-done. Warmup
    /// sets stay quiet — cheering a warmup reads as sarcasm.
    private func celebrateSetDone(exerciseIndex ei: Int, setIndex si: Int) {
        let ex = exercises[ei]
        guard !ex.isWarmupExercise, !ex.sets[si].isWarmup else { return }
        encouragementTick += 1

        let weight = ex.enteredWeightLbs(ex.sets[si].weight)
        if let weight, let lastMax = ex.lastMaxWeight, weight > lastMax + 0.09 {
            showCoachToast(WorkoutEncouragement.line(for: .beatLastTime, tick: encouragementTick))
            return
        }
        if ex.sets.allSatisfy(\.done) {
            let remaining = exercises.filter { $0.id != ex.id && !$0.sets.allSatisfy(\.done) }.count
            let event: WorkoutEncouragement.Event =
                remaining == 0 ? .workoutComplete : .exerciseComplete(remaining: remaining)
            showCoachToast(WorkoutEncouragement.line(for: event, tick: encouragementTick))
            return
        }
        showCoachToast(WorkoutEncouragement.line(for: .setDone, tick: encouragementTick))
    }

    /// Float the line in, hold ~2.5s, fade out — unless a newer toast
    /// superseded it (token guard).
    private func showCoachToast(_ text: String) {
        coachToastToken += 1
        let token = coachToastToken
        withAnimation(.spring(duration: 0.3)) { coachToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard token == coachToastToken else { return }
            withAnimation(.easeOut(duration: 0.4)) { coachToast = nil }
        }
    }

    // MARK: - Command strip ("add face pulls" / "drop curls" / "last bench?")

    private var commandStrip: some View {
        VStack(spacing: 6) {
            if let feedback = commandFeedback {
                HStack(spacing: 8) {
                    Text(feedback.text)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(6)
                    Spacer(minLength: 4)
                    if let undo = feedback.undo {
                        Button("Undo") {
                            undo()
                            commandFeedback = nil
                        }
                        .font(.caption.weight(.semibold)).tint(Theme.accent)
                    }
                    Button {
                        commandFeedback = nil
                    } label: {
                        Image(systemName: sym("xmark.circle.fill"))
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
            HStack(spacing: 8) {
                #if os(Android)
                // No Material sparkle exists — see Symbols.swift. Sized to sit
                // on the .caption cap-height the iOS glyph occupies.
                SparkleShape()
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 13, height: 13)
                #else
                Image(systemName: sym("sparkles"))
                    .font(.caption).foregroundStyle(Theme.accent.opacity(0.6))
                #endif
                TextField("what's next · form tips for squat · ask anything", text: $commandText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($commandFocused)
                    .submitLabel(.send)
                    .onSubmit { runCommand() }
                    .accessibilityIdentifier("workout-command-input")
                if !commandText.isEmpty {
                    Button { runCommand() } label: {
                        #if os(Android)
                        // sym("arrow.up.circle.fill") used to return the
                        // paperplane — a different object from iOS's circled
                        // up-arrow (#1210). 20pt matches .title3.
                        SendUpShape().fill(Theme.ink).frame(width: 24, height: 24)
                        #else
                        Image(systemName: sym("arrow.up.circle.fill"))
                            .font(.title3).foregroundStyle(Theme.ink)
                        #endif
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Run command")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.pillBackground))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.background.opacity(0.97))
        .animation(.easeInOut(duration: 0.2), value: commandFeedback?.text)
    }

    private func runCommand() {
        let raw = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        commandText = ""
        #if os(Android)
        // SkipUI's KeyboardActions runs clearFocus() before *every* onSubmit
        // trigger (skip-ui TextField.swift), so the send key drops the keyboard
        // no matter what we do here. Re-assert on the next tick: a synchronous
        // write lands in the same recomposition SkipUI just cleared and is
        // swallowed.
        //
        // Android-only enhancement, NOT parity: iPhone drops the keyboard on
        // send too — SwiftUI resigns first responder on .onSubmit by default,
        // driven on the iPhone 17 sim with both a mutating ("add bench press")
        // and a non-mutating ("what's next") command. Not writing commandFocused
        // is why iOS *loses* focus, not why it keeps it. We deliberately diverge
        // because the strip is built for chaining ("add face pulls" → "add
        // curls") and re-tapping between each one is the gap. If iPhone should
        // chain too that is a separate iOS-gated change — do not read this as a
        // description of iPhone behaviour.
        Task { @MainActor in commandFocused = true }
        #endif
        switch WorkoutCommandParser.parse(raw) {
        case .remove(let query):
            removeExercise(matching: query)
        case .replace(let old, let new, let sets):
            replaceExercise(matching: old, with: new, sets: sets)
        case .history(let query):
            showHistory(for: query)
        case .next:
            showNextExercise()
        case .formTip(let query):
            showFormTip(for: query)
        case .ask(let question):
            askCoach(question)
        case .add(let query, let sets):
            addFromCommand(query, sets: sets, original: raw)
        }
    }

    /// The exercise the user is on right now: the one the rest bar is anchored
    /// to (just finished a set), else the first with unfinished sets, else the
    /// last in the list. Nil only for an empty workout.
    private func currentExerciseName() -> String? {
        if let restID = activeRestExerciseID,
           let ex = exercises.first(where: { $0.id == restID }) {
            return ex.name
        }
        return exercises.first(where: { $0.sets.contains { !$0.done } })?.name
            ?? exercises.last?.name
    }

    /// Commit a set as done: celebrate, start the rest countdown, and auto-add
    /// the next set. Resolved by stable IDs so it survives the sanity-prompt
    /// round-trip (indices can shift between tap and confirm).
    private func markSetDone(exerciseID: UUID, setID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].done = true
        // Celebrate BEFORE the auto-add below — the bonus set would otherwise
        // hide "exercise complete".
        celebrateSetDone(exerciseIndex: ei, setIndex: si)
        // No rest countdown when backdating a past workout — nothing to rest for.
        if pastDate == nil {
            startRest(exerciseID: exerciseID, setID: setID, duration: exercises[ei].restTime)
        }
        // Auto-add next set prefilled with same weight/reps.
        let current = exercises[ei].sets[si]
        if si == exercises[ei].sets.count - 1 && (!current.weight.isEmpty || !current.reps.isEmpty) {
            exercises[ei].sets.append(ActiveSet(weight: current.weight, reps: current.reps))
        }
    }

    private func showNextExercise() {
        guard let next = exercises.first(where: { $0.sets.contains { !$0.done } }) else {
            commandFeedback = CommandFeedback(text: "Everything's done — hit Finish when you're ready 💪")
            return
        }
        let remaining = next.sets.filter { !$0.done }.count
        var text = "Next: \(next.name) — \(remaining) set\(remaining == 1 ? "" : "s") to go."
        if let previous = next.previousSets.first { text += " Last time: \(previous)." }
        commandFeedback = CommandFeedback(text: text)
    }

    private func showFormTip(for query: String) {
        // "form tips" with no exercise named → the one they're on right now
        // (rest-anchored, else first unfinished). Asking mid-workout means the
        // current lift; don't bounce them to "which exercise?".
        let name: String?
        if query.isEmpty {
            name = currentExerciseName()
        } else {
            name = exercises.first { $0.name.lowercased().contains(query) }?.name
                ?? ExerciseDatabase.match(name: query)?.name
                ?? ExerciseService.resolveExerciseName(query)
        }
        guard let name else {
            commandFeedback = CommandFeedback(text: "Which exercise? Try \"form tips for deadlift\".")
            return
        }
        var lines: [String] = []
        if let tip = ExerciseService.formTip(for: name) { lines.append(tip) }
        if let info = ExerciseDatabase.info(for: name) {
            if lines.isEmpty, let cues = info.instructions?.prefix(2) {
                lines.append(contentsOf: cues)
            }
            let muscles = info.primaryMuscles.joined(separator: ", ")
            if !muscles.isEmpty { lines.append("Works: \(muscles)") }
        }
        guard !lines.isEmpty else {
            // Nothing local for this movement — let the coach answer instead.
            askCoach("Quick form cues for \(name)?")
            return
        }
        commandFeedback = CommandFeedback(text: "\(name) — " + lines.joined(separator: " · "))
    }

    /// Open question → cloud coach, with the live session as context. The
    /// deterministic intents above never touch the network; this is the one
    /// path that does, and it says so ("Thinking…") instead of freezing.
    private func askCoach(_ question: String) {
        // Same cloud rung on both platforms (#1064) — Android used to answer
        // "needs the cloud connection" here while the key was sitting right there.
        guard CoachCloud.isConfigured else {
            commandFeedback = CommandFeedback(text: "Coach questions need the cloud connection — try from the chat.")
            return
        }
        commandFeedback = CommandFeedback(text: "Thinking…")
        let context = coachSessionContext()
        Task {
            CoachCloud.install()
            let reply = await LocalAIService.shared.respondDirect(
                systemPrompt: """
                You are Drift Coach answering DURING a live workout. Be a concise \
                gym buddy: 1-3 short sentences, concrete, no markdown, no greetings. \
                Use the session context when it's relevant; never invent numbers.
                """,
                message: "Session: \(context)\n\nQuestion: \(question)")
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            commandFeedback = CommandFeedback(
                text: trimmed.isEmpty ? "Didn't catch an answer — try that again." : trimmed)
        }
    }

    private func coachSessionContext() -> String {
        let elapsed = pastDate != nil ? 0 : Int(Date().timeIntervalSince(startTime))
        var parts = ["\(workoutName), \(formatWorkoutDuration(elapsed)) in"]
        for ex in exercises {
            let done = ex.sets.filter(\.done).count
            var line = "\(ex.name) \(done)/\(ex.sets.count) sets"
            if let previous = ex.previousSets.first { line += " (last time \(previous))" }
            parts.append(line)
        }
        if let profile = TrainingProfile.load(), !profile.summary.isEmpty {
            parts.append("profile: \(profile.summary)")
        }
        return parts.joined(separator: "; ")
    }

    private func removeExercise(matching query: String) {
        let idx = exercises.firstIndex { $0.name.lowercased().contains(query) }
            ?? ExerciseDatabase.match(name: query).flatMap { info in
                exercises.firstIndex { $0.name == info.name }
            }
        guard let idx else {
            commandFeedback = CommandFeedback(text: "No \"\(query)\" in this workout.")
            return
        }
        let removed = exercises.remove(at: idx)
        stopRestIfAnchorMissing()
        commandFeedback = CommandFeedback(text: "Removed \(removed.name).") {
            exercises.insert(removed, at: min(idx, exercises.count))
        }
    }

    /// Swap one exercise in the running session for another, in place.
    ///
    /// Mid-workout a swap is asked for because something is wrong — the rack is
    /// taken, a joint is complaining, the weight isn't there — so the important
    /// case is the one where they DON'T name a substitute ("swap the squats").
    /// Picking one that trains the same thing is the whole ask; making them
    /// think of the alternative themselves is what "not very smart" meant.
    ///
    /// Keeps the original's position and set count: a swap is a substitution,
    /// not a delete-then-append that buries the new lift at the bottom of a
    /// session someone is halfway through.
    private func replaceExercise(matching query: String, with replacement: String?, sets: Int?) {
        // "swap this" / "replace it" → whatever they're on right now.
        let target = query.isEmpty || ["this", "it", "that", "current"].contains(query)
            ? (currentExerciseName()?.lowercased() ?? "")
            : query

        let idx = exercises.firstIndex { $0.name.lowercased().contains(target) }
            ?? ExerciseDatabase.match(name: target).flatMap { info in
                exercises.firstIndex { $0.name == info.name }
            }
        guard let idx, !target.isEmpty else {
            commandFeedback = CommandFeedback(text: "No \"\(query)\" in this workout.")
            return
        }
        let old = exercises[idx]

        // Same equipment rule the rest of the app uses — a home profile must
        // not be offered a leg-press machine it doesn't have.
        let profile = TrainingProfile.load()
        let equipment: Set<String> = profile?.restrictsEquipment == true
            ? Set((profile?.equipment ?? []) + ["body only"]) : []
        let inSession = Set(exercises.map(\.name))

        let resolved: String?
        if let replacement, !replacement.isEmpty {
            resolved = ExerciseDatabase.match(name: replacement)?.name
                ?? ExerciseService.resolveExerciseName(replacement)
        } else {
            resolved = ExerciseAlternatives.best(for: old.name, excluding: inSession,
                                                 equipment: equipment)?.name
        }

        guard let newName = resolved else {
            commandFeedback = CommandFeedback(text: replacement.map {
                "Couldn't find \"\($0)\" in the exercise library."
            } ?? "Couldn't find a good swap for \(old.name).")
            return
        }

        // Build the replacement through the normal path so it gets its own
        // history ghosts, then move it into the old one's slot.
        addExercise(name: newName, setCount: sets ?? old.sets.count,
                    restTime: old.restTime, isWarmup: old.isWarmupExercise)
        guard let added = exercises.popLast() else { return }
        exercises[idx] = added
        stopRestIfAnchorMissing()

        let why = replacement == nil ? " — same muscles" : ""
        commandFeedback = CommandFeedback(text: "Swapped \(old.name) → \(newName)\(why).") {
            exercises[idx] = old
        }
    }

    private func showHistory(for query: String) {
        // Prefer an exercise already in this session, then the catalog.
        let name = exercises.first { $0.name.lowercased().contains(query) }?.name
            ?? ExerciseService.resolveExerciseName(query)
        guard let name, !query.isEmpty else {
            commandFeedback = CommandFeedback(text: "Which exercise? Try \"last bench press?\"")
            return
        }
        let history = (try? WorkoutService.fetchExerciseHistory(name: name)) ?? []
        guard let lastWorkoutId = history.first?.workoutId else {
            commandFeedback = CommandFeedback(text: "No history for \(name) yet.")
            return
        }
        let last = history.filter { $0.workoutId == lastWorkoutId }.sorted { $0.setOrder < $1.setOrder }
        let unit = Preferences.weightUnit
        let sets = last.prefix(5).map { s -> String in
            let weight = s.weightLbs.map { "\(WeightFormatter.plain(unit.convertFromLbs($0)))\(unit.displayName)" } ?? "bw"
            return "\(weight)×\(s.reps ?? s.durationSec ?? 0)"
        }.joined(separator: ", ")
        commandFeedback = CommandFeedback(text: "\(name) last time: \(sets)")
    }

    private func addFromCommand(_ query: String, sets: Int?, original: String) {
        guard !query.isEmpty,
              let name = ExerciseDatabase.match(name: query)?.name
                ?? ExerciseService.resolveExerciseName(query) else {
            commandFeedback = CommandFeedback(text: "Couldn't find \"\(original)\" in the exercise library.")
            return
        }
        addExercise(name: name, setCount: sets)
        let ghost = exercises.last?.previousSets.first.map { " — last: \($0)" } ?? ""
        let addedId = exercises.last?.id
        commandFeedback = CommandFeedback(text: "Added \(name)\(ghost).") {
            if let addedId {
                exercises.removeAll { $0.id == addedId }
                stopRestIfAnchorMissing()
            }
        }
    }

    /// Optional "send this finished workout to a friend" block inside the
    /// completion sheet. A mode flip (not a nested sheet) reveals the shared
    /// recipient picker; picking one pushes the workout so it appears in
    /// their app.
    @ViewBuilder
    private var friendShareSection: some View {
        if SharingService.shared.isSignedIn {
            Divider().overlay(Theme.separatorFaint)

            // Automatic, with an escape hatch (operator 2026-07-29): both ON by
            // default, flip either off for a session you're only testing. The
            // switches persist, so someone who always wants coach-only gets it
            // without touching this again.
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { shareToFriends },
                    set: { shareToFriends = $0; Preferences.shareWorkoutsWithFriends = $0 }
                )) {
                    Text("Share with friends").font(.caption)
                }
                .tint(Theme.accent)

                Toggle(isOn: Binding(
                    get: { shareToCoaches },
                    set: { shareToCoaches = $0; Preferences.shareWorkoutsWithCoaches = $0 }
                )) {
                    Text("Share with my coach").font(.caption)
                }
                .tint(Theme.accent)

                // Only when there IS a public profile — i.e. only once this
                // person publishes a global board. Showing it otherwise would
                // advertise strangers as an audience they never opted into
                // (operator 2026-07-30: "give people option to keep their rehab
                // session private... it's fine to share with coach").
                if Preferences.shareStatsWithFriends {
                    Toggle(isOn: Binding(
                        get: { showOnPublicProfile },
                        set: { showOnPublicProfile = $0
                               Preferences.showWorkoutsOnPublicProfile = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Show on my public profile").font(.caption)
                            Text(showOnPublicProfile
                                 ? "Strangers who find you on a leaderboard can see this"
                                 : "Friends and your coach only")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .tint(Theme.accent)
                }

                // Say where it went. Automatic sharing that stays silent about
                // its recipients is the kind of thing people resent finding out
                // about later.
                if let broadcast = broadcastResult {
                    Text(broadcast.summary)
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                } else if !shareToFriends && !shareToCoaches {
                    Text("This workout stays private.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            if !friendSendMode {
                Button {
                    friendSendMode = true
                } label: {
                    Label("Send to someone specific", systemImage: sym("paperplane.fill"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.chartTrend)
            } else {
                FriendSharePicker { c in
                    try await SharingService.shared.shareCompletedWorkout(
                        to: c.profile.id, workoutName: workoutName, sets: completedSets)
                } onSent: { _ in
                    FeatureUsage.record(TelemetryEvent.workoutShared)
                }
            }
        }
    }

    private func saveWorkout(andDismiss: Bool = true) {
        FeatureUsage.record(TelemetryEvent.workoutFinished)
        // Before `workoutEnded` shuts the persist path down (#1169).
        syncNotesToTemplate()
        workoutEnded = true
        stopTimers()
        WorkoutService.clearSession()
        let saveDate = pastDate != nil ? workoutDate : Date()
        var workout = Workout(name: workoutName, date: DateFormatters.dateOnly.string(from: saveDate),
                              durationSeconds: pastDate != nil ? nil : Int(Date().timeIntervalSince(startTime)),
                              notes: workoutNotes.isEmpty ? nil : workoutNotes,
                              createdAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try WorkoutService.saveWorkout(&workout)
            guard let wid = workout.id else {
                Log.app.error("Save workout: no ID after save")
                return
            }
            var allSets: [WorkoutSet] = []
            for (ei, ex) in exercises.enumerated() {
                let isDuration = ex.trackByTime
                for (si, s) in ex.sets.enumerated() where s.done {
                    let w = ex.enteredWeightLbs(s.weight) ?? 0   // per-exercise lbs/kg option; comma decimals (#1022)
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
                    let isDuration = ex.trackByTime
                    for (si, s) in ex.sets.enumerated() {
                        let w = ex.enteredWeightLbs(s.weight) ?? 0
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
            // Snapshot the finished sets for the optional "send to a friend"
            // action in the completion sheet (workouts you do show up to friends).
            completedSets = allSets.map {
                SharingService.SharedSet(exerciseName: $0.exerciseName,
                                         exerciseOrder: $0.exerciseOrder,
                                         setOrder: $0.setOrder,
                                         weightLbs: $0.weightLbs, reps: $0.reps,
                                         isWarmup: $0.isWarmup)
            }
            if andDismiss {
                // Share it without making the user pick recipients every session.
                // Fire-and-forget: the workout is already saved locally, so a
                // network failure here must not read as a failed save.
                let sharedName = workout.name
                let sharedSets = completedSets
                Task { @MainActor in
                    let result = await WorkoutBroadcast.send(
                        workoutName: sharedName, sets: sharedSets,
                        toFriends: shareToFriends, toCoaches: shareToCoaches,
                        publicVisible: showOnPublicProfile)
                    if result.sentAnything {
                        broadcastResult = result
                        FeatureUsage.record(TelemetryEvent.workoutShared)
                    }
                    // A new heaviest set is the change people expect on a board
                    // straight away, and the lift half reads only the local
                    // store — so this publishes past the daily gate. Shared
                    // path, so Android gets it without separate wiring.
                    await SocialSync.afterWorkoutSaved()
                }

                // #938: share the PERSISTED workout via the same builder History
                // uses — the old inline snapshot could render an empty summary
                // (e.g. when no set rows qualified) while History looked fine.
                completionShareText = (try? WorkoutService.shareText(forWorkoutId: wid, unit: Preferences.weightUnit))
                    ?? "\u{1F4AA} \(workout.name)"

                // Check milestone
                if let count = try? WorkoutService.totalWorkoutCount() {
                    let milestones = [1, 5, 10, 25, 50, 100, 150, 200, 250, 300, 500]
                    if milestones.contains(count) {
                        completionMilestone = count == 1 ? "First workout!" : "Workout #\(count)!"
                    }
                }
                #if DRIFT_IOS_APP
                // #premium-polish: finishing a workout was a silent moment.
                Haptics.celebrate()
                #endif
                showingCompletionSheet = true
            }
        } catch { Log.app.error("Save workout: \(error.localizedDescription)") }
    }

    private func saveAsTemplate(name: String) {
        let templateExercises = exercises.map { ex in
            WorkoutTemplate.TemplateExercise(name: ex.name, sets: ex.sets.count,
                                             isWarmup: ex.isWarmupExercise,
                                             restSeconds: ex.restTime, notes: ex.notes,
                                             isDuration: ex.trackByTime)
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

}

/// Shared by ActiveWorkoutView's coach context and the ticking clock views.
private func formatWorkoutDuration(_ s: Int) -> String {
    let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

// MARK: - Ticking clocks (isolated @State — #1074)
//
// The 1s ticks write ONLY these views' @State, so recomposition stops at one
// small Text/Label. Ticking the parent's @State re-evaluated the entire
// ActiveWorkoutView body every second — a full JNI-bridged pass on Android
// for the length of the workout, and wasted work on iOS too.

/// Elapsed workout clock. Re-syncs from the wall clock on appear, on
/// foregrounding, and when the parent rebases `startTime` (session restore).
struct WorkoutClockLabel: View {
    enum Style { case headerLabel, summaryStat }
    @Environment(\.scenePhase) var scenePhase
    let startTime: Date
    let style: Style
    @State var ticker = SecondTicker()
    @State var elapsed = 0

    var body: some View {
        content
            .onAppear { resync() }
            .onChange(of: startTime) { _, _ in resync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { resync() }
            }
            .onDisappear { ticker.invalidate() }
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .headerLabel:
            #if os(Android)
            // Material's mapped set has no clock — the calendar stand-in sat
            // next to the real calendar label above. Drawn face instead.
            Label { Text(formatWorkoutDuration(elapsed)) } icon: {
                ClockFaceShape().fill(Theme.textSecondary).frame(width: 12, height: 12)
            }
            #else
            Label(formatWorkoutDuration(elapsed), systemImage: sym("clock"))
            #endif
        case .summaryStat:
            Text(formatWorkoutDuration(elapsed)).font(.title3.weight(.bold).monospacedDigit())
        }
    }

    private func resync() {
        let start = startTime
        elapsed = Int(Date().timeIntervalSince(start))
        ticker.schedule {
            Task { @MainActor in
                elapsed = Int(Date().timeIntervalSince(start))
            }
        }
    }
}

/// Inline rest countdown bar (shows after the resting set — like Strong).
/// Owns its own 1s tick; ActiveWorkoutView decides when the bar exists and
/// fires the completion side effects (vibrate/notification) from its own
/// watcher in `startRestTimerTick`.
struct RestTimerBar: View {
    @Environment(\.scenePhase) var scenePhase
    let endTime: Date
    let totalSeconds: Int
    @State var ticker = SecondTicker()
    @State var remaining = 0

    var body: some View {
        // Clamp at 1: the parent's completion watcher removes the bar within
        // a tick, and the pre-split single-timer bar never displayed 0:00 —
        // this keeps that true during the hand-off.
        let shown = max(1, remaining)
        let progress = totalSeconds > 0 ? Double(shown) / Double(totalSeconds) : 0

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
                Text(formatRestTime(shown))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    // Was .white — invisible over the light-grey unfilled
                    // half of the progress bar (Theme.cardBackgroundElevated)
                    // until rest had >50% elapsed. Theme.textPrimary reads
                    // on both the unfilled and filled (calorieBlue) halves.
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.vertical, 4)
        .onAppear { resync() }
        .onChange(of: endTime) { _, _ in resync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resync() }
        }
        .onDisappear { ticker.invalidate() }
    }

    private func formatRestTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func resync() {
        let end = endTime
        remaining = max(0, Int(ceil(end.timeIntervalSince(Date()))))
        ticker.schedule {
            Task { @MainActor in
                remaining = max(0, Int(ceil(end.timeIntervalSince(Date()))))
            }
        }
    }
}

// MARK: - Field structs (one TextField per View scope)
//
// skip-fuse-ui binds only the FIRST TextField evaluated in a ViewBuilder
// scope (HStack/VStack/ForEach content flattens into the caller's scope);
// later fields render as read-only text on Android. A struct body is its own
// scope, so every extracted field binds. Identical render on iOS.

// Compose wraps every TextField in a Material decoration box that reserves
// horizontal padding on EACH side. At iOS's 55pt that leaves roughly three
// digits of usable text, so a four-character entry ("1234", "137.5") silently
// scrolls out of view — the stored value stays correct but the row DISPLAYS
// "234", and a prefilled 2255 lbs reads as "255" (#1076). iOS has no such
// inset and lays 55pt out fine, so the extra width is Android-only; the column
// HEADERS use the same constants so the columns stay aligned.
#if os(Android)
let setWeightColumnWidth: CGFloat = 80
let setRepsColumnWidth: CGFloat = 68
#else
let setWeightColumnWidth: CGFloat = 55
let setRepsColumnWidth: CGFloat = 50
#endif

extension View {
    /// SkipUI renders every `TextField` as Material's `OutlinedTextField`, which
    /// carries a 56dp `defaultMinSize`. That floor made the set cells ~2x their
    /// iPhone height, inflating the exercise card until Finish fell below the
    /// fold (measured 2026-07-20: 7.9% of screen height per set row vs iOS's
    /// 4.1%). Supplying a content padding switches SkipUI to its `BasicTextField`
    /// path (skip-ui `Text/TextField.swift:172`), which applies no minimum, so
    /// the cell hugs its text the way the iOS one already does.
    /// Identity on Darwin — iOS spacing is unchanged.
    ///
    /// Pass `vertical: 0` where the caller already applies its own
    /// `.padding(.vertical:)` outside the field (as `SetCellField` does, since
    /// that outer padding is what its rounded background is drawn around) —
    /// otherwise the two stack and the cell ends up double-padded.
    func compactTextFieldPadding(vertical: Double = 4, horizontal: Double = 4) -> some View {
        #if os(Android)
        return textFieldContentPadding(top: vertical, leading: horizontal,
                                       bottom: vertical, trailing: horizontal)
        #else
        return self
        #endif
    }
}

struct SetCellField: View {
    let placeholder: String
    @Binding var text: String
    let decimal: Bool
    let width: CGFloat
    let leadingPad: CGFloat
    let done: Bool

    var body: some View {
        NumericField(placeholder, text: $text, decimal: decimal)
            .textFieldStyle(.plain)
            .compactTextFieldPadding(vertical: 0)
            .font(.subheadline.monospacedDigit())
            .multilineTextAlignment(.center).frame(width: width)
            .padding(.vertical, 4).padding(.leading, leadingPad)
            .background(done ? Theme.deficit.opacity(0.1) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct WorkoutNotesField: View {
    @Binding var text: String

    var body: some View {
        #if os(Android)
        TextField("Workout notes...", text: $text)
            .textFieldStyle(.plain)
            .compactTextFieldPadding()
            .font(.caption).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
        #else
        TextField("Workout notes...", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.caption).foregroundStyle(Theme.textSecondary)
            .lineLimit(1...3)
            .padding(.horizontal, 16)
        #endif
    }
}

/// Exercise "Tip:/Notes" line inside an exercise card. On Android it is a
/// tap-to-edit surface, NOT a live TextField: an always-present TextField here
/// is the card's only inline field, so a sibling Button tap (the set DONE
/// circle ~180px below) steals its focus and pops the IME with a caret sitting
/// in the tip text (#1103). Rendering the note as plain Text until the user
/// taps it means there is no focusable field for the done-tap to grab. iOS
/// keeps the live inline TextField — byte-identical to the pre-#1103 call site.
/// (@State/@FocusState are non-private: SharedUI structs must be for the Skip
/// Fuse bridge; every other @State in this file is non-private too.)
struct ExerciseNotesField: View {
    @Binding var text: String            // "" == no note
    #if os(Android)
    @State var editing = false
    @FocusState var focused: Bool
    #endif

    var body: some View {
        #if os(Android)
        Group {
            if editing {
                TextField("Notes...", text: $text)
                    .textFieldStyle(.plain)
                    .compactTextFieldPadding()          // dodge Material's 56dp min-height
                    .font(.caption2).foregroundStyle(Theme.textSecondary).italic()
                    .focused($focused)
                    .onAppear { Task { @MainActor in focused = true } }   // deferred focus (cmd-strip precedent, L1200)
                    .onChange(of: focused) { _, f in if !f { editing = false } } // blur/onSubmit collapses back to Text
            } else {
                Text(text.isEmpty ? "Notes..." : text)
                    .font(.caption2)
                    .foregroundStyle(text.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())          // full-width tap target (SkipUICompat paints an α0.0001 surface)
                    .onTapGesture { editing = true }
            }
        }
        #else
        TextField("Notes...", text: $text)
            .textFieldStyle(.plain)
            .font(.caption2).foregroundStyle(Theme.textSecondary).italic()
        #endif
    }
}

// MARK: - SecondTicker (cross-platform 1s repeating tick)

/// Timer.scheduledTimer on Darwin; a Task sleep-loop on Android, where
/// swift-corelibs `Timer` needs a pumped RunLoop that Compose's main thread
/// doesn't provide. Class (not struct) so the ported call sites keep the
/// original `invalidate()`/re-`schedule` shape under `@State`.
final class SecondTicker {
    #if os(Android)
    private var task: Task<Void, Never>?
    #else
    private var timer: Timer?
    #endif

    func schedule(_ tick: @escaping @Sendable () -> Void) {
        invalidate()
        #if os(Android)
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                tick()
            }
        }
        #else
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
        #endif
    }

    func invalidate() {
        #if os(Android)
        task?.cancel(); task = nil
        #else
        timer?.invalidate(); timer = nil
        #endif
    }
}
