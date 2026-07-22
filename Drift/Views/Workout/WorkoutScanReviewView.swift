import SwiftUI
import DriftCore

/// Review what the scanner read before anything is saved. A page can yield a
/// reusable program AND dated sessions (a printed grid + handwritten columns),
/// so both are offered: templates open the familiar editor; sessions open a
/// per-set confirm screen. Nothing is written until the user confirms each.
struct WorkoutScanReviewView: View {
    let result: ScannedWorkoutResult
    let onSaved: () -> Void

    @State private var pendingTemplates: [Identified<ScannedTemplate>]
    @State private var pendingSessions: [Identified<ScannedSession>]
    @State private var savedCount = 0
    @State private var editingTemplate: Identified<ScannedTemplate>?
    @State private var editingSession: Identified<ScannedSession>?
    @Environment(\.dismiss) private var dismiss

    init(result: ScannedWorkoutResult, onSaved: @escaping () -> Void) {
        self.result = result
        self.onSaved = onSaved
        _pendingTemplates = State(initialValue: result.templates.map(Identified.init))
        _pendingSessions = State(initialValue: result.sessions.map(Identified.init))
    }

    var body: some View {
        List {
            Section {
                Text(summary).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }

            if !pendingTemplates.isEmpty {
                Section("Programs → Templates") {
                    ForEach(pendingTemplates) { item in
                        Button { editingTemplate = item } label: {
                            scanRow(title: item.value.name,
                                    subtitle: "\(item.value.exercises.count) exercises · tap to review & save",
                                    icon: "square.stack.3d.up")
                        }
                    }
                }
            }

            if !pendingSessions.isEmpty {
                Section("Logged Sessions") {
                    ForEach(pendingSessions) { item in
                        Button { editingSession = item } label: {
                            scanRow(title: sessionTitle(item.value),
                                    subtitle: sessionSubtitle(item.value),
                                    icon: "checkmark.rectangle.stack")
                        }
                    }
                }
            }

            if pendingTemplates.isEmpty && pendingSessions.isEmpty {
                Section {
                    Label("All set — \(savedCount) saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.deficit)
                }
            }
        }
        .navigationTitle("Review Scan").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onSaved() }
            }
        }
        .sheet(item: $editingTemplate) { item in
            CreateTemplateView(prefill: (name: item.value.name, exercises: item.value.templateExercises)) {
                // Any scanned movement the catalog doesn't know becomes a custom
                // exercise so the template's rows resolve in the library
                // (browse, tracking type, anatomy) — same as CSV import.
                WorkoutService.autoRegisterUnknownExercises(item.value.templateExercises.map(\.name))
                pendingTemplates.removeAll { $0.id == item.id }
                savedCount += 1
                onSaved()
            }
        }
        .sheet(item: $editingSession) { item in
            WorkoutScanSessionReview(session: item.value) {
                pendingSessions.removeAll { $0.id == item.id }
                savedCount += 1
                onSaved()
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if !result.templates.isEmpty { parts.append("\(result.templates.count) program\(result.templates.count == 1 ? "" : "s")") }
        if !result.sessions.isEmpty { parts.append("\(result.sessions.count) logged session\(result.sessions.count == 1 ? "" : "s")") }
        return "Found " + parts.joined(separator: " and ") + ". Review each below, then save."
    }

    private func sessionTitle(_ s: ScannedSession) -> String {
        guard let date = s.date else { return s.name }
        return "\(s.name) · \(DateFormatters.shortDisplay.string(from: date))"
    }

    private func sessionSubtitle(_ s: ScannedSession) -> String {
        let names = s.exercises.prefix(3).map(\.name).joined(separator: ", ")
        let more = s.exercises.count > 3 ? " +\(s.exercises.count - 3)" : ""
        return names + more
    }

    private func scanRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }
}

/// Stable identity wrapper so scanned values (which aren't Identifiable) work in
/// ForEach / `.sheet(item:)` without mutating the domain models.
struct Identified<T>: Identifiable {
    let id = UUID()
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Per-session confirm

/// Confirm one scanned session before logging: edit the name + date, drop any
/// exercise or set that was misread, then log. Per-set weights/reps stay
/// editable so the ascending-weight reality of the notebook is preserved.
struct WorkoutScanSessionReview: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var date: Date
    @State private var exercises: [EditableExercise]
    @State private var saveError = false

    init(session: ScannedSession, onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        _name = State(initialValue: session.name)
        _date = State(initialValue: session.date ?? Date())
        _exercises = State(initialValue: session.exercises.map(EditableExercise.init))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $name)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                ForEach($exercises) { $ex in
                    Section {
                        HStack {
                            TextField("Exercise", text: $ex.name)
                                .font(.subheadline.weight(.semibold))
                            if ExerciseDatabase.match(name: ex.name) == nil {
                                Text("NEW").font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.fatYellow)
                            }
                        }
                        if ex.isDuration {
                            HStack {
                                Text("Duration").font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                TextField("min", text: $ex.durationText)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("min").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        } else {
                            ForEach($ex.sets) { $set in
                                HStack(spacing: 8) {
                                    Text("Set \(setNumber(for: set, in: ex))")
                                        .font(.caption).foregroundStyle(Theme.textTertiary).frame(width: 44, alignment: .leading)
                                    TextField("reps", text: $set.reps)
                                        .keyboardType(.numberPad).multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                    Text("×").foregroundStyle(Theme.textTertiary)
                                    TextField("lb", text: $set.weight)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                    Text("lb").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .onDelete { ex.sets.remove(atOffsets: $0) }
                            Button { ex.sets.append(EditableSet(reps: "", weight: "")) } label: {
                                Label("Add Set", systemImage: "plus.circle").font(.caption)
                            }
                        }
                    } header: {
                        HStack {
                            Text(ex.name.isEmpty ? "Exercise" : ex.name)
                            Spacer()
                            Button(role: .destructive) {
                                exercises.removeAll { $0.id == ex.id }
                            } label: { Image(systemName: "trash").font(.caption) }
                        }
                    }
                }

                Section {
                    Button { save() } label: {
                        Label("Log This Session", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(exercises.isEmpty)
                }
            }
            .navigationTitle("Confirm Session").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Couldn't log that", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Something went wrong saving. Try again.") }
        }
    }

    private func setNumber(for set: EditableSet, in ex: EditableExercise) -> Int {
        (ex.sets.firstIndex { $0.id == set.id } ?? 0) + 1
    }

    private func save() {
        let mapped = exercises.map { $0.toScanned() }
        do {
            let workout = try WorkoutService.saveScannedSession(
                name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Workout" : name,
                date: date, exercises: mapped)
            if workout == nil { saveError = true; return }
            onSaved(); dismiss()
        } catch {
            saveError = true
        }
    }
}

// MARK: - Editable models

struct EditableExercise: Identifiable {
    let id = UUID()
    var name: String
    var isDuration: Bool
    var durationText: String
    var sets: [EditableSet]

    init(_ e: ScannedSessionExercise) {
        name = e.name
        isDuration = e.isDuration
        durationText = e.durationMinutes.map(String.init) ?? ""
        sets = e.sets.map(EditableSet.init)
    }

    func toScanned() -> ScannedSessionExercise {
        ScannedSessionExercise(
            name: name.trimmingCharacters(in: .whitespaces),
            isDuration: isDuration,
            sets: isDuration ? [] : sets.compactMap { $0.toScanned() },
            durationMinutes: isDuration ? Int(durationText) : nil)
    }
}

struct EditableSet: Identifiable {
    let id = UUID()
    var reps: String
    var weight: String

    init(reps: String, weight: String) { self.reps = reps; self.weight = weight }
    init(_ s: ScannedSet) {
        reps = s.reps.map(String.init) ?? ""
        weight = s.weightLbs.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
    }

    /// nil when the row is blank (dropped on save).
    func toScanned() -> ScannedSet? {
        let r = Int(reps)
        let w = Double(weight)
        guard r != nil || w != nil else { return nil }
        return ScannedSet(reps: r, weightLbs: w)
    }
}
