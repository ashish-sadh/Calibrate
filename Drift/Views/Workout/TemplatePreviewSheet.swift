import SwiftUI

struct TemplatePreviewSheet: View {
    let template: WorkoutTemplate
    let onStartWorkout: (WorkoutTemplate) -> Void
    let onEditTemplate: (WorkoutTemplate) -> Void
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
                            NavigationLink {
                                ExerciseDetailView(exerciseName: ex.name, info: ExerciseDatabase.info(for: ex.name))
                            } label: {
                                HStack {
                                    Text("W").font(.caption2.weight(.bold)).foregroundStyle(Theme.fatYellow)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(Theme.fatYellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ex.name).font(.subheadline)
                                        if let notes = ex.notes { Text(notes).font(.caption2).foregroundStyle(.secondary).italic() }
                                    }
                                    Spacer()
                                    Text("\(ex.sets) sets").font(.caption2).foregroundStyle(.tertiary)
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
                                HStack {
                                    Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ex.name).font(.subheadline)
                                        HStack(spacing: 4) {
                                            Text("\(ex.sets) sets").font(.caption2).foregroundStyle(.tertiary)
                                            if let lastW = try? WorkoutService.lastWeight(for: ex.name) {
                                                Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                                                Text("\(Int(lastW)) lb").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                            }
                                            if let notes = ex.notes {
                                                Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                                                Text(notes).font(.caption2).foregroundStyle(.secondary).italic()
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text("\(ex.restSeconds/60):\(String(format: "%02d", ex.restSeconds%60))")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
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

                            Button {
                                if let tid = template.id {
                                    try? WorkoutService.toggleFavorite(id: tid)
                                    onDismiss()
                                    onReload()
                                }
                            } label: {
                                Label(template.isFavorite ? "Unfavorite" : "Favorite",
                                      systemImage: template.isFavorite ? "star.slash" : "star")
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
        .presentationDetents([.medium, .large])
    }
}
