import SwiftUI
import DriftCore

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    var onDelete: (() -> Void)? = nil
    // Not `private`: skipstone can't bridge private property wrappers to
    // Android (matches ActiveWorkoutView's @Environment declarations).
    @Environment(\.dismiss) var dismiss
    @State var sets: [WorkoutSet] = []
    @State var showingShare = false
    @State var showingSaveTemplate = false
    @State var showingDeleteConfirm = false
    @State var showingEditName = false
    @State var editName = ""
    @State var editNotes = ""
    @State var saveTemplateName = ""
    @State var editingSet: WorkoutSet?
    @State var editSetWeight = ""
    @State var editSetReps = ""

    // #938: one share builder for completion + History — lives in
    // WorkoutService so the two surfaces can never diverge.
    private var shareText: String {
        WorkoutService.shareText(for: summary, sets: sets)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.workout.name).font(.headline)
                    Text(formatDate(summary.workout.date)).font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 12) {
                        if !summary.workout.durationDisplay.isEmpty {
                            #if os(Android)
                            // "clock" is deliberately unmapped (Symbols.swift) — draw
                            // the face, matching the ActiveWorkoutView call site.
                            Label { Text(summary.workout.durationDisplay) } icon: {
                                ClockFaceShape().fill(Theme.textSecondary).frame(width: 12, height: 12)
                            }
                            #else
                            Label(summary.workout.durationDisplay, systemImage: sym("clock"))
                            #endif
                        }
                        Label("\(Int(summary.totalVolume)) lbs", systemImage: sym("scalemass"))
                        Label("\(summary.totalSets) sets", systemImage: sym("number"))
                    }.font(.caption).foregroundStyle(Theme.textSecondary)
                    if let notes = summary.workout.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(Theme.textTertiary).italic()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).card()

                let grouped = Dictionary(grouping: sets) { $0.exerciseName }
                ForEach(summary.exercises, id: \.self) { ex in
                    if let exSets = grouped[ex] {
                        let workingSets = exSets.filter { !$0.isWarmup }
                        let exVolumeLbs = workingSets.reduce(0.0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ex).font(.subheadline.weight(.semibold))
                                Spacer()
                                if exVolumeLbs > 0 {
                                    Text("\(Int(exVolumeLbs)) lbs").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                                Text(muscleGroup(for: ex)).font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            ForEach(exSets, id: \.id) { s in
                                HStack {
                                    Text(s.isWarmup ? "W" : "\(s.setOrder)").font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(s.isWarmup ? Theme.fatYellow : .primary).frame(width: 20)
                                    Text(s.display).font(.subheadline.monospacedDigit())
                                    Spacer()
                                    if let rm = s.estimated1RM { Text("1RM: \(Int(rm)) lbs").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary) }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingSet = s
                                    editSetWeight = s.weightLbs.map { "\(Int($0))" } ?? ""
                                    editSetReps = s.reps.map { "\($0)" } ?? (s.durationSec.map { "\($0)" } ?? "")
                                }
                                // No-op on both platforms (this is a ScrollView,
                                // not a List) — kept verbatim; tap-to-edit is
                                // the live path.
                                #if !os(Android)
                                .swipeActions(edge: .trailing) {
                                    if let sid = s.id {
                                        Button(role: .destructive) {
                                            try? WorkoutService.deleteSet(id: sid)
                                            sets.removeAll { $0.id == sid }
                                        } label: {
                                            Label("Delete", systemImage: sym("trash"))
                                        }
                                    }
                                }
                                #endif
                            }
                        }.card()
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Workout").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    #if canImport(UIKit)
                    Button { showingShare = true } label: { Label("Share", systemImage: sym("square.and.arrow.up")) }
                    #else
                    // Android: no UIActivityViewController. ShareLink is a real
                    // skip-ui component (ACTION_SEND intent). #967 caveat —
                    // it snapshots at render time, and `sets` loads before the
                    // menu can be opened, so the text is populated.
                    ShareLink(item: shareText) { Label("Share", systemImage: sym("square.and.arrow.up")) }
                    #endif
                    Button {
                        editName = summary.workout.name
                        editNotes = summary.workout.notes ?? ""
                        showingEditName = true
                    } label: { Label("Edit Name & Notes", systemImage: sym("pencil")) }
                    Button { saveTemplateName = summary.workout.name; showingSaveTemplate = true } label: { Label("Save as Template", systemImage: sym("doc.on.doc")) }
                    if summary.workout.id != nil {
                        Divider()
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: { Label("Delete Workout", systemImage: sym("trash")) }
                    }
                } label: { Image(systemName: sym("ellipsis.circle")).foregroundStyle(Theme.accent) }
                .accessibilityLabel("Workout options")
            }
        }
        .alert("Delete Workout?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let wid = summary.workout.id {
                    try? WorkoutService.deleteWorkout(id: wid)
                    onDelete?()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This workout and all its sets will be permanently deleted.") }
        #if canImport(UIKit)
        .sheet(isPresented: $showingShare) { ShareSheet(text: shareText) }
        #endif
        .alert("Save as Template", isPresented: $showingSaveTemplate) {
            TextField("Template name", text: $saveTemplateName)
            Button("Save") { saveAsTemplate(name: saveTemplateName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this template")
        }
        .alert("Edit Set", isPresented: Binding(
            get: { editingSet != nil },
            set: { if !$0 { editingSet = nil } }
        )) {
            TextField("Weight (lbs)", text: $editSetWeight)
                .keyboardType(.decimalPad)
            TextField("Reps", text: $editSetReps)
                .keyboardType(.numberPad)
            Button("Save") {
                if let s = editingSet, let sid = s.id {
                    let w = Double(editSetWeight)
                    let r = Int(editSetReps)
                    let dur = WorkoutSet.isDurationExercise(s.exerciseName) ? r : nil
                    try? WorkoutService.updateSet(id: sid, weightLbs: w, reps: dur != nil ? nil : r, durationSec: dur)
                    // Update local state (store in lbs)
                    if let idx = sets.firstIndex(where: { $0.id == sid }) {
                        sets[idx].weightLbs = w
                        if dur != nil { sets[idx].durationSec = dur } else { sets[idx].reps = r }
                    }
                    editingSet = nil
                }
            }
            Button("Cancel", role: .cancel) { editingSet = nil }
        } message: {
            if let s = editingSet {
                Text("\(s.exerciseName) — Set \(s.setOrder)")
            }
        }
        .alert("Edit Workout", isPresented: $showingEditName) {
            TextField("Workout name", text: $editName)
            TextField("Notes (optional)", text: $editNotes)
            Button("Save") {
                if let wid = summary.workout.id, !editName.isEmpty {
                    try? WorkoutService.updateWorkout(id: wid, name: editName, notes: editNotes.isEmpty ? nil : editNotes)
                    onDelete?() // triggers parent reload
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        #if os(Android)
        // Off the push animation: a synchronous fetch in onAppear runs during
        // the NavigationStack transition's first frames (directive 0e / the
        // #1074 "transitions are slow" class). Same single query, off-main.
        .task {
            guard let wid = summary.workout.id else { return }
            sets = await Self.fetchSetsOffMain(workoutId: wid)
        }
        #else
        .onAppear { if let wid = summary.workout.id { sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? [] } }
        #endif
    }

    #if os(Android)
    static func fetchSetsOffMain(workoutId: Int64) async -> [WorkoutSet] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: (try? WorkoutService.fetchSets(forWorkout: workoutId)) ?? [])
            }
        }
    }
    #endif

    private func muscleGroup(for exercise: String) -> String {
        let e = exercise.lowercased()
        if e.contains("bench") || e.contains("chest") || e.contains("fly") || e.contains("dip") { return "Chest" }
        if e.contains("squat") || e.contains("leg") || e.contains("calf") || e.contains("hip") || e.contains("deadlift") || e.contains("lunge") || e.contains("press") && e.contains("leg") { return "Legs" }
        if e.contains("lat") || e.contains("row") || e.contains("pull") || e.contains("back") { return "Back" }
        if e.contains("shoulder") || e.contains("lateral raise") || e.contains("overhead press") || e.contains("face pull") { return "Shoulders" }
        if e.contains("bicep") || e.contains("curl") || e.contains("tricep") || e.contains("hammer") { return "Arms" }
        if e.contains("crunch") || e.contains("plank") || e.contains("ab") || e.contains("leg raise") { return "Core" }
        if e.contains("farmer") { return "Full Body" }
        return ""
    }

    private func saveAsTemplate(name: String? = nil) {
        let warmupNames = Set(sets.filter(\.isWarmup).map(\.exerciseName))
        let exercises = summary.exercises.map { name in
            let isW = warmupNames.contains(name)
            let count = sets.filter { $0.exerciseName == name && !$0.isWarmup }.count
            return WorkoutTemplate.TemplateExercise(name: name, sets: max(count, isW ? 2 : 3), isWarmup: isW,
                                                    restSeconds: isW ? 30 : 90)
        }
        if let json = try? JSONEncoder().encode(exercises), let jsonStr = String(data: json, encoding: .utf8) {
            let templateName = (name?.isEmpty ?? true) ? summary.workout.name : name!
            var t = WorkoutTemplate(name: templateName, exercisesJson: jsonStr, createdAt: ISO8601DateFormatter().string(from: Date()))
            try? WorkoutService.saveTemplate(&t)
        }
    }

    private func formatDate(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; guard let date = f.date(from: String(d.prefix(10))) else { return d }
        f.dateFormat = "EEEE, MMM d, yyyy"; return f.string(from: date)
    }
}

// MARK: - Share Sheet

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    var text: String = ""
    var items: [Any]?
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items ?? [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
