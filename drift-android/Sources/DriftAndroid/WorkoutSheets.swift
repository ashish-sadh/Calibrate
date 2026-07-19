import SwiftUI
import DriftCore

// MARK: - Template preview (port of iOS TemplatePreviewSheet)

struct AndroidTemplatePreviewSheet: View {
    let template: WorkoutTemplate
    let onStartWorkout: (WorkoutTemplate) -> Void
    let onDismiss: () -> Void
    let onReload: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let warmups = template.exercises.filter(\.isWarmup)
                    let working = template.exercises.filter { !$0.isWarmup }

                    if !warmups.isEmpty {
                        Text("WARMUP").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                        ForEach(Array(warmups.enumerated()), id: \.offset) { _, ex in
                            templateRow(ex)
                        }
                        Divider().padding(.vertical, 4)
                    }

                    if !working.isEmpty {
                        Text("EXERCISES").font(.caption2.weight(.bold)).foregroundStyle(Theme.calorieBlue)
                        ForEach(Array(working.enumerated()), id: \.offset) { _, ex in
                            templateRow(ex)
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            onStartWorkout(template)
                        } label: {
                            Label("Start Workout", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        }.buttonStyle(.plain)

                        Button {
                            if let tid = template.id {
                                try? WorkoutService.toggleFavorite(id: tid)
                                onDismiss()
                                onReload()
                            }
                        } label: {
                            Label(template.isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: sym(template.isFavorite ? "star.slash" : "star"))
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }

                        Button(role: .destructive) {
                            if let tid = template.id {
                                WorkoutService.deleteTemplate(id: tid)
                                onDismiss()
                                onReload()
                            }
                        } label: {
                            Label("Delete Template", systemImage: "trash").font(.caption)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(template.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { onDismiss() } }
            }
        }
    }

    private func templateRow(_ ex: WorkoutTemplate.TemplateExercise) -> some View {
        NavigationLink {
            ExerciseDetailView(exerciseName: ex.name, info: ExerciseDatabase.info(for: ex.name))
        } label: {
            HStack(spacing: 8) {
                ExerciseThumbnail(info: ExerciseDatabase.info(for: ex.name), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ex.name).font(.subheadline)
                    HStack(spacing: 4) {
                        Text("\(ex.sets) sets").font(.caption2).foregroundStyle(Theme.textTertiary)
                        if let lastW = try? WorkoutService.lastWeight(for: ex.name) {
                            Text("\u{00B7}").font(.caption2).foregroundStyle(Theme.textTertiary)
                            Text("\(Int(Preferences.weightUnit.convertFromLbs(lastW))) \(Preferences.weightUnit.displayName)")
                                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        }
                        if let notes = ex.notes {
                            Text("\u{00B7}").font(.caption2).foregroundStyle(Theme.textTertiary)
                            Text(notes).font(.caption2).foregroundStyle(Theme.textSecondary).italic()
                        }
                    }
                }
                Spacer()
                Text("\(ex.restSeconds/60):\(String(format: "%02d", ex.restSeconds%60))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 3)
        }
        .tint(.primary)
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise browser (port of iOS ExerciseBrowserView, list level)

struct AndroidExerciseBrowser: View {
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var selectedBodyPart: String? = nil
    @State var results: [ExerciseDatabase.ExerciseInfo] = []

    // Residual vs iOS ExerciseBrowserView (#1064): custom-exercise CTA +
    // toolbar plus button await the CustomExerciseSheet port.
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                }
                .padding()
                .background(Theme.cardBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", selected: selectedBodyPart == nil) { selectedBodyPart = nil }
                        ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"], id: \.self) { p in
                            chip(p, selected: selectedBodyPart == p) { selectedBodyPart = p }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }

                List {
                    ForEach(results.prefix(100)) { ex in
                        NavigationLink {
                            ExerciseDetailView(exerciseName: ex.name, info: ex)
                        } label: {
                            HStack(spacing: 10) {
                                ExerciseThumbnail(info: ex, size: 52)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(ex.name).font(.subheadline)
                                    HStack(spacing: 4) {
                                        muscleChip(ex.bodyPart)
                                        if !ex.equipment.isEmpty && ex.equipment.lowercased() != "other" {
                                            equipmentChip(ex.equipment)
                                        }
                                        if !ex.primaryMuscles.isEmpty {
                                            Text(ex.primaryMuscles.prefix(2).map(\.capitalized).joined(separator: ", "))
                                                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }.tint(.primary)
                    }
                }.listStyle(.plain)
            }
            .background(Theme.background)
            .navigationTitle("Exercise Database").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await reload() }
            .onChange(of: query) { _, _ in Task { await reload() } }
            .onChange(of: selectedBodyPart) { _, _ in Task { await reload() } }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.ink : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        let q = query
        let part = selectedBodyPart
        results = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hits = q.trimmingCharacters(in: .whitespaces).isEmpty
                    ? ExerciseDatabase.allWithCustom
                    : ExerciseDatabase.search(query: q)
                if let part {
                    hits = hits.filter { $0.bodyPart.caseInsensitiveCompare(part) == .orderedSame }
                }
                let favs = WorkoutService.exerciseFavorites
                hits.sort { favs.contains($0.name) && !favs.contains($1.name) }
                continuation.resume(returning: hits)
            }
        }
    }
}

// MARK: - Text exercise logging (the iOS ExerciseVoiceLogSheet pipeline, text-first)

struct ExerciseTextLogSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSaved: () -> Void

    @State var input = ""
    @State var parsed: [AIActionParser.WorkoutExercise] = []
    @State var didParse = false
    @State var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Type your sets — e.g. \u{201C}3×10 bench at 135, 3×12 squats at 185\u{201D}")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                TextField("3x10 bench at 135", text: $input)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let text = input
                    Task {
                        parsed = await AIActionParser.parseWorkoutExercisesAsync(text)
                        didParse = true
                    }
                } label: {
                    Text("Parse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)

                if didParse {
                    if parsed.isEmpty {
                        Text("Couldn't read any exercises — try \u{201C}3x10 bench at 135\u{201D}")
                            .font(.caption)
                            .foregroundStyle(Theme.surplus)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(parsed.enumerated()), id: \.offset) { _, ex in
                                HStack {
                                    Text(ex.name).font(.subheadline)
                                    Spacer()
                                    Text("\(ex.sets)×\(ex.reps)\(ex.weight.map { " @ \(Int($0))" } ?? "")")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .card()

                        Button {
                            save()
                        } label: {
                            Text("Log Workout")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(Theme.surplus)
                }

                Spacer()
            }
            .padding(16)
            .background(Theme.background)
            .navigationTitle("Log by Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func save() {
        let exercises = parsed.map {
            WorkoutService.VoiceLoggedExercise(name: $0.name, isDuration: false,
                                               sets: $0.sets, reps: $0.reps, weightLbs: $0.weight)
        }
        do {
            _ = try WorkoutService.saveVoiceLoggedWorkout(name: "Logged Workout", exercises: exercises)
            onSaved()
            dismiss()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
