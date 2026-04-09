import SwiftUI

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

struct TemplateExerciseEditor: View {
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
