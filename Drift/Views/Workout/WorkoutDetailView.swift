import SwiftUI

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var sets: [WorkoutSet] = []
    @State private var showingShare = false
    @State private var showingSaveTemplate = false
    @State private var showingDeleteConfirm = false
    @State private var saveTemplateName = ""

    private var shareText: String {
        var t = "💪 \(summary.workout.name)\n📅 \(formatDate(summary.workout.date))\n"
        if !summary.workout.durationDisplay.isEmpty { t += "⏱ \(summary.workout.durationDisplay)  " }
        t += "🏋️ \(Int(summary.totalVolume)) lb\n"
        if let notes = summary.workout.notes, !notes.isEmpty { t += "📝 \(notes)\n" }
        t += "\n"
        let grouped = Dictionary(grouping: sets.filter { !$0.isWarmup }) { $0.exerciseName }
        for ex in summary.exercises {
            if let exSets = grouped[ex] {
                t += "\(ex)\n"
                for s in exSets { t += "  \(s.setOrder). \(s.display)\n" }
                t += "\n"
            }
        }
        t += "Logged with Drift"; return t
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.workout.name).font(.headline)
                    Text(formatDate(summary.workout.date)).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if !summary.workout.durationDisplay.isEmpty { Label(summary.workout.durationDisplay, systemImage: "clock") }
                        Label("\(Int(summary.totalVolume)) lb", systemImage: "scalemass")
                        Label("\(summary.totalSets) sets", systemImage: "number")
                    }.font(.caption).foregroundStyle(.secondary)
                    if let notes = summary.workout.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(.tertiary).italic()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).card()

                let grouped = Dictionary(grouping: sets) { $0.exerciseName }
                ForEach(summary.exercises, id: \.self) { ex in
                    if let exSets = grouped[ex] {
                        let workingSets = exSets.filter { !$0.isWarmup }
                        let exVolume = workingSets.reduce(0.0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ex).font(.subheadline.weight(.semibold))
                                Spacer()
                                if exVolume > 0 {
                                    Text("\(Int(exVolume)) lb").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(muscleGroup(for: ex)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            ForEach(exSets, id: \.id) { s in
                                HStack {
                                    Text(s.isWarmup ? "W" : "\(s.setOrder)").font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(s.isWarmup ? Theme.fatYellow : .primary).frame(width: 20)
                                    Text(s.display).font(.subheadline.monospacedDigit())
                                    Spacer()
                                    if let rm = s.estimated1RM { Text("1RM: \(Int(rm))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                                }
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
                    Button { showingShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { saveTemplateName = summary.workout.name; showingSaveTemplate = true } label: { Label("Save as Template", systemImage: "doc.on.doc") }
                    if summary.workout.id != nil {
                        Divider()
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: { Label("Delete Workout", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.accent) }
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
        .sheet(isPresented: $showingShare) { ShareSheet(text: shareText) }
        .alert("Save as Template", isPresented: $showingSaveTemplate) {
            TextField("Template name", text: $saveTemplateName)
            Button("Save") { saveAsTemplate(name: saveTemplateName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this template")
        }
        .onAppear { if let wid = summary.workout.id { sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? [] } }
    }

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
