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

    /// Commit the Edit Set fields to the store and to local state. Shared by the
    /// iOS alert and the Android sheet so the two editors can't drift apart.
    private func saveEditedSet(_ s: WorkoutSet) {
        guard let sid = s.id else { return }
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
                                    editSetWeight = s.weightLbs.map { WeightFormatter.plain($0) } ?? ""
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
        #if os(Android)
        // SkipUI extracts an alert's TextFields with `strip()` (skip-ui
        // Presentation.swift:480), which unwraps the ModifierView carrying
        // `.keyboardType` and composes the bare field — so both fields opened a
        // full QWERTY keyboard and accepted letters into weight/reps (#1077).
        // The type is read from `EnvironmentValues._keyboardOptions` at compose
        // time (skip-ui TextField.swift:118), so no call-site shim can reach it,
        // and one environment value can't give weight `.decimalPad` and reps
        // `.numberPad` anyway. Sheet content composes normally, so each field
        // keeps its own keypad. Title, message, field order, placeholders and
        // button roles mirror the iOS alert below exactly.
        .sheet(item: $editingSet) { s in
            EditSetSheet(set: s, weight: $editSetWeight, reps: $editSetReps,
                         onSave: { saveEditedSet(s) },
                         onCancel: { editingSet = nil })
        }
        #else
        .alert("Edit Set", isPresented: Binding(
            get: { editingSet != nil },
            set: { if !$0 { editingSet = nil } }
        )) {
            TextField("Weight (lbs)", text: $editSetWeight)
                .keyboardType(.decimalPad)
            TextField("Reps", text: $editSetReps)
                .keyboardType(.numberPad)
            Button("Save") {
                if let s = editingSet { saveEditedSet(s) }
            }
            Button("Cancel", role: .cancel) { editingSet = nil }
        } message: {
            if let s = editingSet {
                Text("\(s.exerciseName) — Set \(s.setOrder)")
            }
        }
        #endif
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
        // Shared pinned formatters on both sides — an ad-hoc DateFormatter
        // parses (and formats) as UTC on Android, shifting the header a day (#1076).
        guard let date = DateFormatters.dateOnly.date(from: String(d.prefix(10))) else { return d }
        return DateFormatters.longDayDisplay.string(from: date)
    }
}

// MARK: - Edit Set (Android)

#if os(Android)
/// Android stand-in for the iOS "Edit Set" alert — see the `.sheet(item:)` call
/// site in `WorkoutDetailView` for why the alert can't carry a keyboard type.
/// Copy and field order match the alert one-for-one.
struct EditSetSheet: View {
    let set: WorkoutSet
    @Binding var weight: String
    @Binding var reps: String
    let onSave: () -> Void
    let onCancel: () -> Void

    // Detent height is load-bearing. The IME eats ~45% of the screen and a
    // .medium detent is only ~50%, so with a keypad up the content box
    // collapsed to a sliver — and SkipUI SQUASHES an overflowing sheet's
    // children instead of clipping or scrolling them. The weight value
    // rendered as a sliced band, and the reps field and Save/Cancel were
    // pushed off-screen entirely: you typed reps blind into a field you
    // couldn't see and had no way to reach Save without dismissing the
    // keyboard first (#1076 sweep #9). iPhone's alert keeps BOTH fields and
    // BOTH buttons above the keypad, so matching it needs the taller detent;
    // the ScrollView is the belt-and-braces for small screens and large
    // accessibility text. The trailing Spacer() is gone on purpose — an
    // infinite spacer inside a ScrollView fights the scroll metrics.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Set").font(.headline)
                Text("\(set.exerciseName) — Set \(set.setOrder)")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                // One TextField per view scope: Skip binds only the first field in a
                // given ViewBuilder scope, so a second inline field would render but
                // never commit (the SetCellField precedent, #1064).
                EditSetWeightField(text: $weight)
                EditSetRepsField(text: $reps)
                HStack(spacing: 20) {
                    Spacer()
                    Button("Cancel", role: .cancel) { onCancel() }
                    Button("Save") { onSave() }.font(.body.weight(.semibold))
                }.padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.large])
    }
}

// `.textFieldStyle(.plain)` is load-bearing, not cosmetic: without it Compose
// wraps the field in its Material decoration box, and stacking our own padding +
// background on top of that squeezed the glyphs to an unreadable horizontal
// sliver (the caret still moved, so the text was there — just clipped). This is
// the same decoration-box trap that made set rows show three characters of a
// weight (#1076), and the same shape `SetCellField` already uses.
//
// Height comes from vertical PADDING, never `.frame(height:)`. A fixed frame
// constrains the Compose text composable itself, so the glyphs get clipped from
// the top — visible even with the keyboard down (#1080 sweep). Padding lets the
// field size to its own line height and still lands at ~44pt.
struct EditSetWeightField: View {
    @Binding var text: String
    var body: some View {
        TextField("Weight (lbs)", text: $text)
            .textFieldStyle(.plain)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EditSetRepsField: View {
    @Binding var text: String
    var body: some View {
        TextField("Reps", text: $text)
            .textFieldStyle(.plain)
            .keyboardType(.numberPad)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif

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
