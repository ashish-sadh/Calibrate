import SwiftUI
import DriftCore

// MARK: - Workout tab root

struct WorkoutTab: View {
    var body: some View {
        NavigationStack {
            DriftWorkoutView()
        }
    }
}

// MARK: - Active workout (sheet)

/// Sheet wrapper for the active-workout flow — owns its store instance,
/// prefills from a template when one is passed (Coach Me / template start),
/// resumes a persisted session otherwise.
struct AndroidActiveWorkoutSheet: View {
    let template: WorkoutTemplate?
    let onDone: () -> Void
    @Environment(\.dismiss) var dismiss
    @State var store = WorkoutStore()

    var body: some View {
        NavigationStack {
            ActiveWorkoutScreen(store: store) {
                onDone()
                dismiss()
            }
        }
        .onAppear {
            if let template {
                store.startWorkout(from: template)
            } else if !store.sessionActive {
                store.startWorkout()
            }
        }
    }
}

struct ActiveWorkoutScreen: View {
    @Bindable var store: WorkoutStore
    var onDone: () -> Void = {}
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
                                .foregroundStyle(Theme.textTertiary)
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
                                    .foregroundStyle(store.exercises[exerciseIndex].sets[setIndex].done ? Theme.deficit : Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add Set") { store.addSet(exerciseIndex: exerciseIndex) }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                } header: {
                    HStack {
                        Text(exercise.name)
                        if let hint = exercise.lastWeightHint {
                            Text(hint).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Remove") { store.removeExercise(at: exerciseIndex) }
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Section {
                Button {
                    showPicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                Button {
                    store.finishWorkout()
                    onDone()
                } label: {
                    Text("Finish Workout")
                        .font(.headline)
                        .foregroundStyle(store.exercises.isEmpty ? Theme.textTertiary : Theme.accent)
                }
                .disabled(store.exercises.isEmpty)
                Button("Cancel Workout", role: .destructive) { showCancelConfirm = true }
            }
        }
        .navigationTitle(store.workoutName)
        .sheet(isPresented: $showPicker) {
            ExercisePickerScreen(store: store)
        }
        .confirmationDialog("Discard this workout?", isPresented: $showCancelConfirm) {
            Button("Discard Workout", role: .destructive) {
                store.cancelWorkout()
                onDone()
            }
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
                    HStack(spacing: 10) {
                        ExerciseThumbnail(info: ExerciseDatabase.info(for: row.name), size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).foregroundStyle(Theme.textPrimary)
                            Text("\(row.bodyPart) · \(row.equipment)")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
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
