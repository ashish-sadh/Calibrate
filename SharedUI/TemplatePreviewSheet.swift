import SwiftUI
import DriftCore

struct TemplatePreviewSheet: View {
    let template: WorkoutTemplate
    let onStartWorkout: (WorkoutTemplate) -> Void
    let onEditTemplate: (WorkoutTemplate) -> Void
    let onDismiss: () -> Void
    let onReload: () -> Void

    #if os(Android)
    // Synchronous per-row DB reads in a view body cross JNI on every body
    // evaluation (#1073) — batch the last weights once off-main instead.
    @State var lastWeights: [String: Double] = [:]
    #endif

    private func lastWeight(for name: String) -> Double? {
        #if os(Android)
        return lastWeights[name]
        #else
        if let w = try? WorkoutService.lastWeight(for: name) { return w }
        return nil
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let warmups = template.exercises.filter(\.isWarmup)
                    let working = template.exercises.filter { !$0.isWarmup }

                    if !warmups.isEmpty {
                        Text("WARMUP").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                        ForEach(Array(warmups.enumerated()), id: \.offset) { _, ex in
                            NavigationLink {
                                ExerciseDetailView(exerciseName: ex.name, info: ExerciseDatabase.info(for: ex.name))
                            } label: {
                                HStack(spacing: 8) {
                                    ExerciseThumbnail(info: ExerciseDatabase.info(for: ex.name), size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ex.name).font(.subheadline)
                                        if let notes = ex.notes { Text(notes).font(.caption2).foregroundStyle(Theme.textSecondary).italic() }
                                    }
                                    Spacer()
                                    Text("\(ex.sets) sets").font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                            }.tint(.primary)
                        }
                        Divider().padding(.vertical, 4)
                    }

                    if !working.isEmpty {
                        Text("EXERCISES").font(.caption2.weight(.bold)).foregroundStyle(Theme.calorieBlue)
                        ForEach(Array(working.enumerated()), id: \.offset) { i, ex in
                            NavigationLink {
                                ExerciseDetailView(exerciseName: ex.name, info: ExerciseDatabase.info(for: ex.name))
                            } label: {
                                HStack(spacing: 8) {
                                    ExerciseThumbnail(info: ExerciseDatabase.info(for: ex.name), size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ex.name).font(.subheadline)
                                        HStack(spacing: 4) {
                                            Text("\(ex.sets) sets").font(.caption2).foregroundStyle(Theme.textTertiary)
                                            if let lastW = lastWeight(for: ex.name) {
                                                Text("\u{00B7}").font(.caption2).foregroundStyle(Theme.textTertiary)
                                                Text("\(Int(Preferences.weightUnit.convertFromLbs(lastW))) \(Preferences.weightUnit.displayName)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
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
                            }.tint(.primary)
                        }
                    }

                    // Actions
                    VStack(spacing: 10) {
                        Button {
                            onStartWorkout(template)
                        } label: {
                            Label("Start Workout", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)

                        HStack(spacing: 12) {
                            Button {
                                onEditTemplate(template)
                            } label: {
                                Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered)
                            // iOS's tintless .bordered reads gray-fill/blue-text;
                            // SkipUI's default tonal tint reads near-black — pin
                            // it to blue so the hierarchy matches.
                            #if os(Android)
                            .tint(.blue)
                            #endif

                            Button {
                                if let tid = template.id {
                                    try? WorkoutService.toggleFavorite(id: tid)
                                    onDismiss()
                                    onReload()
                                }
                            } label: {
                                Label(template.isFavorite ? "Unfavorite" : "Favorite",
                                      systemImage: sym(template.isFavorite ? "star.slash" : "star"))
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered).tint(Theme.fatYellow)
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
            .navigationTitle(template.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { onDismiss() } }
            }
        }
        #if os(Android)
        .task {
            let names = template.exercises.filter { !$0.isWarmup }.map(\.name)
            lastWeights = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var weights: [String: Double] = [:]
                    for name in names {
                        if let w = try? WorkoutService.lastWeight(for: name) { weights[name] = w }
                    }
                    continuation.resume(returning: weights)
                }
            }
        }
        #endif
        .presentationDetents([.medium, .large])
    }
}
