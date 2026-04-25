import SwiftUI
import DriftCore
import AudioToolbox

// MARK: - Active Workout (with live timer, rest timer, prefilled weights)

struct ActiveWorkoutView: View {
    @Environment(\.scenePhase) private var scenePhase
    var template: WorkoutTemplate? = nil
    var pastDate: Date? = nil  // Non-nil = logging a past workout (no timer)
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workoutName = defaultWorkoutName()
    @State private var workoutDate = Date()
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
                        if pastDate != nil {
                            // Past workout: date picker
                            DatePicker("Date", selection: $workoutDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .font(.caption)
                        } else {
                            // Live workout: date + timer
                            HStack(spacing: 12) {
                                Label(DateFormatters.dayDisplay.string(from: Date()), systemImage: "calendar")
                                Label(formatDuration(elapsedSeconds), systemImage: "clock")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
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
                    ScrollView {
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
                    .padding(.bottom, 20)
                    }  // ScrollView
                    .background(Theme.background)
                    .scrollDismissesKeyboard(.interactively)
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

                    ShareLink(item: completionShareText) {
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
                if let pd = pastDate {
                    workoutDate = pd
                    workoutName = "Workout"
                }
                // Live workouts: restore session + start timer
                if pastDate == nil {
                    let restored = restoreSession()
                    startWorkoutTimer()
                    if restored { return }
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
                .accessibilityLabel("Exercise options")
            }

            // Notes (editable - pre-filled from template)
            TextField("Notes...", text: Binding(
                get: { exercises[ei].notes ?? "" },
                set: { exercises[ei].notes = $0.isEmpty ? nil : $0 }
            ))
            .font(.caption2).foregroundStyle(.secondary).italic()

            // Column headers
            let assisted = isAssistedExercise(exercises[ei].name)
            let isDuration = WorkoutSet.isDurationExercise(exercises[ei].name)
            HStack(spacing: 0) {
                Text("Set").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 28, alignment: .leading)
                Text("Previous").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 85, alignment: .leading)
                Text(assisted ? "-\(Preferences.weightUnit.displayName)" : Preferences.weightUnit.displayName).font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 55)
                Text(isDuration ? "Time (s)" : "Reps").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 50)
                Spacer()
                Text("✓").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).frame(width: 30)
            }

            // Sets
            ForEach($exercises[ei].sets) { $set in
                let si = exercises[ei].sets.firstIndex(where: { $0.id == set.id }) ?? 0
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Button {
                            $set.isWarmup.wrappedValue.toggle()
                        } label: {
                            Text(set.isWarmup || exercises[ei].isWarmupExercise ? "W" : "\(si + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(set.isWarmup || exercises[ei].isWarmupExercise ? Theme.fatYellow : .secondary)
                        }.buttonStyle(.plain).frame(width: 28, alignment: .leading)

                        // Previous
                        Text(si < exercises[ei].previousSets.count ? exercises[ei].previousSets[si] : "—")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 85, alignment: .leading)

                        // Weight
                        TextField(si < exercises[ei].previousSets.count ? prevWeight(exercises[ei].previousSets[si]) : "0",
                                  text: $set.weight)
                            .keyboardType(.decimalPad).font(.subheadline.monospacedDigit())
                            .multilineTextAlignment(.center).frame(width: 55)
                            .padding(.vertical, 4)
                            .background(set.done ? Theme.deficit.opacity(0.1) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 4))

                        // Reps or Time
                        TextField(isDuration ? "sec" : (si < exercises[ei].previousSets.count ? prevReps(exercises[ei].previousSets[si]) : "0"),
                                  text: $set.reps)
                            .keyboardType(.numberPad).font(.subheadline.monospacedDigit())
                            .multilineTextAlignment(.center).frame(width: 50)
                            .padding(.vertical, 4).padding(.leading, 4)
                            .background(set.done ? Theme.deficit.opacity(0.1) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 4))

                        Spacer()

                        // Done button
                        Button {
                            let nowDone = !set.done
                            $set.done.wrappedValue = nowDone
                            if nowDone {
                                startRest(exerciseIndex: ei, setIndex: si, duration: exercises[ei].restTime)
                                // Auto-add next set prefilled with same weight/reps
                                if si == exercises[ei].sets.count - 1 && (!set.weight.isEmpty || !set.reps.isEmpty) {
                                    exercises[ei].sets.append(ActiveSet(weight: set.weight, reps: set.reps))
                                }
                            }
                        } label: {
                            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(set.done ? Theme.deficit : .secondary)
                        }.frame(width: 30)

                        // Inline delete button
                        Button {
                            exercises[ei].sets.removeAll(where: { $0.id == set.id })
                            if exercises[ei].sets.isEmpty { exercises.remove(at: ei) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.quaternary)
                        }.frame(width: 20).accessibilityLabel("Delete set")
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button(role: .destructive) {
                            exercises[ei].sets.removeAll(where: { $0.id == set.id })
                            if exercises[ei].sets.isEmpty { exercises.remove(at: ei) }
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

        let wu = Preferences.weightUnit
        let previous = lastSession.prefix(5).map { s in
            "\(Int(wu.convertFromLbs(s.weightLbs ?? 0))) \(wu.displayName) \u{00D7} \(s.reps ?? 0)"
        }

        let count = setCount ?? (lastSession.isEmpty ? 3 : max(lastSession.count, 3))
        var sets: [ActiveSet] = []
        for i in 0..<count {
            if i < lastSession.count {
                let s = lastSession[i]
                sets.append(ActiveSet(weight: s.weightLbs.map { String(Int(wu.convertFromLbs($0))) } ?? "",
                                      reps: s.reps.map { String($0) } ?? "", isWarmup: isWarmup))
            } else {
                sets.append(ActiveSet(weight: "", reps: "", isWarmup: isWarmup))
            }
        }

        // Auto-add form tip if no notes provided
        let finalNotes = notes ?? ExerciseService.formTip(for: name).map { "Tip: \($0)" }
        exercises.append(ActiveExercise(name: name, restTime: restTime, isWarmupExercise: isWarmup,
                                         notes: finalNotes, sets: sets, previousSets: Array(previous)))
    }

    private func saveWorkout(andDismiss: Bool = true) {
        workoutEnded = true
        stopTimers()
        WorkoutService.clearSession()
        let saveDate = pastDate != nil ? workoutDate : Date()
        var workout = Workout(name: workoutName, date: DateFormatters.dateOnly.string(from: saveDate),
                              durationSeconds: pastDate != nil ? nil : elapsedSeconds,
                              notes: workoutNotes.isEmpty ? nil : workoutNotes,
                              createdAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try WorkoutService.saveWorkout(&workout)
            guard let wid = workout.id else {
                Log.app.error("Save workout: no ID after save")
                return
            }
            let saveUnit = Preferences.weightUnit
            var allSets: [WorkoutSet] = []
            for (ei, ex) in exercises.enumerated() {
                let isDuration = WorkoutSet.isDurationExercise(ex.name)
                for (si, s) in ex.sets.enumerated() where s.done {
                    let raw = Double(s.weight) ?? 0
                    let w = saveUnit.convertToLbs(raw)
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
                        let raw = Double(s.weight) ?? 0
                        let w = saveUnit.convertToLbs(raw)
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
                let totalVolLbs = allSets.reduce(0.0) { $0 + (($1.weightLbs ?? 0) * Double($1.reps ?? 0)) }
                let volUnit = Preferences.weightUnit
                let totalVol = volUnit.convertFromLbs(totalVolLbs)
                let exerciseNames = exercises.map(\.name).filter { !$0.isEmpty }
                let duration = workout.durationDisplay
                var shareLines = ["💪 \(workout.name)"]
                if !duration.isEmpty { shareLines.append("⏱ \(duration)") }
                shareLines.append("🏋️ \(Int(totalVol)) \(volUnit.displayName) total volume")
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
