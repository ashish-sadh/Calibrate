import SwiftUI
import DriftCore

// MARK: - Create Template

struct CreateTemplateView: View {
    var existingTemplate: WorkoutTemplate? = nil
    /// Seed a brand-new (unsaved) template — e.g. from a scanned workout page.
    /// Distinct from `existingTemplate` (which edits a persisted row): a prefill
    /// still saves as new. Ignored when `existingTemplate` is set.
    var prefill: (name: String, exercises: [WorkoutTemplate.TemplateExercise])? = nil
    /// When set, the built template is handed BACK instead of being written to
    /// the local library — the seam a coach needs to build a workout for one
    /// client without cluttering their own template list. The caller decides
    /// whether to persist it, share it, or both.
    var onBuild: ((WorkoutTemplate) -> Void)? = nil
    /// Names the primary action, so the button never claims to "Save Template"
    /// when the caller isn't going to save one.
    var saveButtonTitle: String? = nil
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State var name = ""
    @State var exercises: [WorkoutTemplate.TemplateExercise] = []
    @State var showingPicker = false
    @State var addingWarmup = false
    @State var editingIndex: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Name") {
                    TextField("e.g., Push Day", text: $name)
                        #if os(Android)
                        // Material's default TextField draws an outlined box
                        // inside the Form row; iPhone's is borderless and lets
                        // the row's own white fill be the field. Same remedy
                        // VoiceLogNumberField uses.
                        .textFieldStyle(.plain)
                        #endif
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
                            Label("Add Warmup", systemImage: sym("plus.circle")).foregroundStyle(Theme.fatYellow)
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
                        Label("Add Exercise", systemImage: sym("plus.circle")).foregroundStyle(Theme.accent)
                    }
                    if warmupIndices.isEmpty {
                        Button { addingWarmup = true; showingPicker = true } label: {
                            Label("Add Warmup Exercise", systemImage: sym("plus.circle")).foregroundStyle(Theme.fatYellow)
                        }
                    }
                }

                Section {
                    Button {
                        if let json = try? JSONEncoder().encode(exercises), let jsonStr = String(data: json, encoding: .utf8) {
                            let built = WorkoutTemplate(name: name.isEmpty ? "Template" : name,
                                                        exercisesJson: jsonStr,
                                                        createdAt: ISO8601DateFormatter().string(from: Date()))
                            if let onBuild {
                                // The caller owns persistence — nothing is
                                // written here.
                                onBuild(built)
                            } else if let existing = existingTemplate, let id = existing.id {
                                // Update existing template
                                WorkoutService.updateTemplate(id: id, name: name.isEmpty ? "Template" : name, exercisesJson: jsonStr)
                            } else {
                                // Create new
                                var t = built
                                try? WorkoutService.saveTemplate(&t)
                            }
                        }
                        onSave(); dismiss()
                    } label: {
                        Label(saveButtonTitle
                              ?? (existingTemplate != nil ? "Update Template" : "Save Template"),
                              systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
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
                } else if let prefill, exercises.isEmpty {
                    name = prefill.name
                    exercises = prefill.exercises
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exName in
                    exercises.append(.init(name: exName, sets: addingWarmup ? 2 : 3, isWarmup: addingWarmup,
                                           restSeconds: addingWarmup ? 30 : 90))
                }
            }
        }
        // On the NavigationStack, not chained under the picker sheet — SkipUI
        // honors one presentation modifier per view.
        .sheet(item: editingBinding) { idx in
            if idx.value < exercises.count {
                TemplateExerciseEditor(exercise: exercises[idx.value]) { updated in
                    if idx.value < exercises.count { exercises[idx.value] = updated }
                } onDelete: {
                    if idx.value < exercises.count { exercises.remove(at: idx.value) }
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
                        Text("\(ex.sets) sets").font(.caption2).foregroundStyle(Theme.textTertiary)
                        Text("\u{00B7}").font(.caption2).foregroundStyle(Theme.textTertiary)
                        Text("\(ex.restSeconds/60):\(String(format: "%02d", ex.restSeconds%60)) rest")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        if let notes = ex.notes, !notes.isEmpty {
                            Text("\u{00B7}").font(.caption2).foregroundStyle(Theme.textTertiary)
                            Text(notes).font(.caption2).foregroundStyle(Theme.textSecondary).italic()
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }.tint(.primary)
    }
}

struct IdentifiableInt: Identifiable {
    var id: Int { value }
    let value: Int
}

// MARK: - Template Exercise Editor

struct TemplateExerciseEditor: View {
    let exercise: WorkoutTemplate.TemplateExercise
    let onSave: (WorkoutTemplate.TemplateExercise) -> Void
    // Android-only: iPhone deletes via swipe on the parent list; this backs the
    // explicit "Remove Exercise" action the Android editor shows instead.
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    @State var sets: Int
    @State var restSeconds: Int
    @State var notes: String
    @State var isWarmup: Bool
    @State var trackByTime: Bool

    init(exercise: WorkoutTemplate.TemplateExercise, onSave: @escaping (WorkoutTemplate.TemplateExercise) -> Void, onDelete: (() -> Void)? = nil) {
        self.exercise = exercise
        self.onSave = onSave
        self.onDelete = onDelete
        _sets = State(initialValue: exercise.sets)
        _restSeconds = State(initialValue: exercise.restSeconds)
        _notes = State(initialValue: exercise.notes ?? "")
        _isWarmup = State(initialValue: exercise.isWarmup)
        _trackByTime = State(initialValue: exercise.isDuration ?? WorkoutSet.isDurationExercise(exercise.name))
    }

    // Standard rest presets, plus the exercise's own value when it isn't one of
    // them (the P5 seeded templates use 75s/105s) — otherwise the menu Picker
    // has no tag matching the selection and renders a BLANK value on both
    // platforms. For a standard rest this equals the base list → no visual change.
    private var restOptions: [Int] {
        let base = [15, 30, 45, 60, 90, 120, 150, 180]
        return base.contains(restSeconds) ? base : (base + [restSeconds]).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exercise.name).font(.headline)
                }

                Section("Configuration") {
                    // iOS draws the ± glyphs in the label color; SkipUI's Stepper falls
                    // back to Color.accentColor → Material blue on Android. Match iPhone by
                    // tinting the ± to the primary text color (Android only, #1078).
                    Stepper("\(sets) sets", value: $sets, in: 1...10)
                        #if os(Android)
                        .tint(Theme.textPrimary)
                        #endif

                    Picker("Rest", selection: $restSeconds) {
                        ForEach(restOptions, id: \.self) { sec in
                            Text("\(sec/60):\(String(format: "%02d", sec%60))").tag(sec)
                        }
                    }
                    #if os(Android)
                    // SkipUI paints the menu-Picker's value+chevron with the ambient tint
                    // (accent red here); iOS renders it in secondary gray. Match iPhone by
                    // pinning the value to secondary text (Android only, #1078).
                    .tint(Theme.textSecondary)
                    #endif

                    // An un-tinted SwiftUI Toggle is system-green when ON; SkipUI's Switch
                    // falls back to Material navy. Match iPhone's green (Android only; iOS
                    // keeps its untouched system default, #1078).
                    Toggle("Warmup exercise", isOn: $isWarmup)
                        #if os(Android)
                        .tint(Theme.deficit)
                        #endif

                    // Reps vs seconds timer — planks/carries or anything the
                    // name classifier got wrong (operator 2026-07-14).
                    Picker("Track by", selection: $trackByTime) {
                        Text("Reps").tag(false)
                        Text("Time").tag(true)
                    }
                    #if os(Android)
                    .tint(Theme.textSecondary)   // gray value like iPhone, not accent (#1078)
                    #endif
                }

                Section("Notes") {
                    TextField("e.g., 8-12 reps, slow eccentric", text: $notes)
                        #if os(Android)
                        // Match the Template-Name field: Material otherwise draws an
                        // outlined box inside the Form row; iPhone's is borderless.
                        .textFieldStyle(.plain)
                        #endif
                }

                #if os(Android)
                // iPhone removes a template exercise by swiping its row; SkipUI's
                // swipe-to-delete is a dead gesture on a Form Button row (it bubbles
                // up to the sheet-dismiss instead), so give Android an explicit
                // destructive action here (operator 0-INTERACTION-QA: no dead gestures).
                if let onDelete {
                    Section {
                        Button {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Remove Exercise", systemImage: sym("trash"))
                                .foregroundStyle(Theme.surplus)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Edit Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(.init(name: exercise.name, sets: sets, isWarmup: isWarmup,
                                     restSeconds: restSeconds, notes: notes.isEmpty ? nil : notes,
                                     isDuration: trackByTime))
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}
