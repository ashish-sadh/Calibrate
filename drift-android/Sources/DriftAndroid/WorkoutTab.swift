import SwiftUI

// MARK: - Workout tab root

struct WorkoutTab: View {
    @State var store = WorkoutStore()

    var body: some View {
        NavigationStack {
            if store.sessionActive {
                ActiveWorkoutScreen(store: store)
            } else {
                WorkoutHomeScreen(store: store)
            }
        }
    }
}

// MARK: - Home

struct WorkoutHomeScreen: View {
    @Bindable var store: WorkoutStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    statTile("\(store.thisWeekCount)", "this week")
                    statTile("\(store.streak)", "day streak")
                    statTile("\(store.totalCount)", "total")
                }

                Button {
                    store.startWorkout()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Start Workout")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DriftTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Section("Recent") {
                if store.recent.isEmpty {
                    Text("No workouts yet — start your first one!")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.recent) { row in
                    NavigationLink(value: row.id) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.name).font(.headline)
                                Spacer()
                                Text(row.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(row.exercises)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                Text("\(row.totalSets) set\(row.totalSets == 1 ? "" : "s")")
                                    .foregroundStyle(DriftTheme.textSecondary)
                                if row.totalVolume > 0 {
                                    Text("\(row.totalVolume) lbs volume")
                                        .foregroundStyle(DriftTheme.textSecondary)
                                }
                                if row.prs > 0 {
                                    Text("🏆 \(row.prs) PR\(row.prs == 1 ? "" : "s")")
                                        .foregroundStyle(DriftTheme.deficit)
                                }
                            }
                            .font(.caption2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Exercise")
        .navigationDestination(for: Int64.self) { workoutId in
            WorkoutDetailScreen(store: store, workoutId: workoutId)
        }
        .onAppear { store.reloadHome() }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(DriftTheme.accent)
            Text(label).font(.caption2).foregroundStyle(DriftTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - History detail

struct WorkoutDetailScreen: View {
    @Bindable var store: WorkoutStore
    let workoutId: Int64

    var body: some View {
        List {
            let grouped = Dictionary(grouping: store.detail, by: { $0.exerciseName })
            ForEach(grouped.keys.sorted(), id: \.self) { exercise in
                Section(exercise) {
                    ForEach((grouped[exercise] ?? []).sorted { $0.setOrder < $1.setOrder }) { row in
                        HStack {
                            Text("Set \(row.setOrder)").foregroundStyle(.secondary)
                            Spacer()
                            Text(row.display)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Workout Detail")
        .onAppear { store.loadDetail(workoutId: workoutId) }
    }
}

// MARK: - Active workout

struct ActiveWorkoutScreen: View {
    @Bindable var store: WorkoutStore
    @State var showPicker = false
    @State var showCancelConfirm = false

    var body: some View {
        List {
            Section {
                TextField("Workout name", text: $store.workoutName)
                    .font(.headline)
                    .onSubmit { store.persistSession() }
            }

            ForEach(Array(store.exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                Section {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, _ in
                        HStack(spacing: 8) {
                            Text("\(setIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            TextField("lbs", text: $store.exercises[exerciseIndex].sets[setIndex].weight)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { store.persistSession() }
                            TextField("reps", text: $store.exercises[exerciseIndex].sets[setIndex].reps)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { store.persistSession() }
                            Button {
                                store.exercises[exerciseIndex].sets[setIndex].done.toggle()
                                store.persistSession()
                            } label: {
                                Image(systemName: store.exercises[exerciseIndex].sets[setIndex].done
                                      ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(store.exercises[exerciseIndex].sets[setIndex].done ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add Set") { store.addSet(exerciseIndex: exerciseIndex) }
                        .font(.subheadline)
                } header: {
                    HStack {
                        Text(exercise.name)
                        if let hint = exercise.lastWeightHint {
                            Text(hint).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") { store.removeExercise(at: exerciseIndex) }
                            .font(.caption2)
                    }
                }
            }

            Section {
                Button("Add Exercise") { showPicker = true }
                Button("Finish Workout") { store.finishWorkout() }
                    .font(.headline)
                    .disabled(store.exercises.isEmpty)
                Button("Cancel Workout", role: .destructive) { showCancelConfirm = true }
            }
        }
        .navigationTitle(store.workoutName)
        .sheet(isPresented: $showPicker) {
            ExercisePickerScreen(store: store)
        }
        .confirmationDialog("Discard this workout?", isPresented: $showCancelConfirm) {
            Button("Discard Workout", role: .destructive) { store.cancelWorkout() }
        }
    }
}

// MARK: - Exercise picker

struct ExercisePickerScreen: View {
    @Bindable var store: WorkoutStore
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var results: [ExerciseRow] = []

    var body: some View {
        NavigationStack {
            List(results) { row in
                Button {
                    store.addExercise(row.name)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                        Text("\(row.bodyPart) · \(row.equipment)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Add Exercise")
            .task { results = await store.searchExercises("") }
            .onChange(of: query) { _, newValue in
                Task { results = await store.searchExercises(newValue) }
            }
        }
    }
}
