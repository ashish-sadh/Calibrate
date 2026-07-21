import SwiftUI
import DriftCore

// MARK: - Exercise Detail (history + PR)

struct ExerciseDetailView: View {
    let exerciseName: String
    let info: ExerciseDatabase.ExerciseInfo?
    @State var history: [WorkoutSet] = []
    @State var pr: Double?
    @State var isFavorite = false

    // Storage is lbs; PR, history rows and 1RM all render through `unit` so a
    // kg user reads back what they logged (#1085).
    private var unit: WeightUnit { Preferences.weightUnit }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Hero (#929): pose crossfade demo (bundled, public-domain
                // free-exercise-db pack) + the anatomical muscle diagram.
                // Replaces the old remote imageUrl AsyncImage. Exercises
                // without pose assets show the diagram alone — never a
                // broken frame.
                if let info {
                    if let poses = PoseCrossfadeView(imageUrl: info.imageUrl) {
                        poses
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                    if !info.primaryMuscles.isEmpty || !info.secondaryMuscles.isEmpty {
                        MuscleHighlightCard(
                            primaryMuscles: info.primaryMuscles,
                            secondaryMuscles: info.secondaryMuscles
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exerciseName).font(.title3.weight(.bold))
                        Spacer()
                        Button {
                            WorkoutService.toggleExerciseFavorite(exerciseName)
                            isFavorite.toggle()
                        } label: {
                            #if os(Android)
                            // skip-ui #148: the "outlined" Material star is
                            // filled, so sym("star") makes the un-favorited
                            // state read as favorited. Draw the real outline
                            // (stroke) / filled star instead (StarGlyph.swift).
                            Group {
                                if isFavorite {
                                    StarShape().fill(Theme.fatYellow)
                                } else {
                                    StarShape().stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
                                }
                            }
                            .frame(width: 22, height: 22)
                            #else
                            Image(systemName: sym(isFavorite ? "star.fill" : "star"))
                                .font(.title3)
                                .foregroundStyle(isFavorite ? Theme.fatYellow : Color.gray.opacity(0.4))
                            #endif
                        }
                    }

                    if let info {
                        HStack(spacing: 6) {
                            detailTag(info.bodyPart, icon: sym("figure.strengthtraining.traditional"), color: .secondary)
                            detailTag(info.equipment, icon: sym("wrench.and.screwdriver"), color: .secondary)
                            detailTag(info.level.capitalized, icon: sym("chart.bar"), color: .secondary)
                        }

                        if let youtubeUrl = info.youtubeUrl, let url = URL(string: youtubeUrl) {
                            Link(destination: url) {
                                Label("Form Tutorial", systemImage: sym("play.circle.fill"))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.red)
                            }
                        }

                        if !info.primaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Primary muscles").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                Text(info.primaryMuscles.map(\.capitalized).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.primary)
                            }
                        }
                        if !info.secondaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Secondary muscles").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                Text(info.secondaryMuscles.map(\.capitalized).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                        }

                    }

                    if let pr {
                        HStack(spacing: 4) {
                            Image(systemName: sym("trophy.fill")).font(.caption).foregroundStyle(Theme.fatYellow)
                            Text("PR: \(Int(unit.convertFromLbs(pr))) \(unit.displayName) (est. 1RM)")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.fatYellow)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                if history.isEmpty {
                    VStack(spacing: 8) {
                        #if os(Android)
                        // No clock in skip-ui's Material map (ClockGlyph.swift).
                        ClockFaceShape().fill(Theme.textTertiary).frame(width: 22, height: 22)
                        #else
                        Image(systemName: sym("clock")).font(.title2).foregroundStyle(Theme.textTertiary)
                        #endif
                        Text("No history yet").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }.padding(.top, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        ForEach(history.prefix(20), id: \.id) { s in
                            HStack {
                                Text(s.isWarmup ? "W" : "\(s.setOrder)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(s.isWarmup ? Theme.fatYellow : .secondary)
                                    .frame(width: 20)
                                Text(s.display(in: unit)).font(.subheadline.monospacedDigit())
                                Spacer()
                                if let rm = s.estimated1RM {
                                    // Deliberately still unit-less here — the row is
                                    // tight and the set text beside it already carries
                                    // the unit. Only the NUMBER was wrong for kg users.
                                    Text("1RM: \(Int(unit.convertFromLbs(rm)))").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }.card()
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
        .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
        #if os(Android)
        // Same three reads, off the push animation (#1074). On iOS these are
        // cheap main-thread queries; on Android each crosses JNI and they ran
        // synchronously in `onAppear`, i.e. during the NavigationStack push —
        // the transition stutter the operator reported. `fetchPR` also re-ran
        // `fetchExerciseHistory` internally, so this folds two identical table
        // scans into one and derives the PR from the sets already fetched
        // (`fetchPR` is exactly `compactMap(\.estimated1RM).max()`).
        .task {
            let name = exerciseName
            let loaded: (favorite: Bool, sets: [WorkoutSet], pr: Double?) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let favorite = WorkoutService.exerciseFavorites.contains(name)
                    let sets = (try? WorkoutService.fetchExerciseHistory(name: name)) ?? []
                    continuation.resume(returning: (favorite, sets, sets.compactMap(\.estimated1RM).max()))
                }
            }
            if Task.isCancelled { return }
            isFavorite = loaded.favorite
            history = loaded.sets
            pr = loaded.pr
        }
        #else
        .onAppear {
            isFavorite = WorkoutService.exerciseFavorites.contains(exerciseName)
            history = (try? WorkoutService.fetchExerciseHistory(name: exerciseName)) ?? []
            pr = try? WorkoutService.fetchPR(for: exerciseName)
        }
        #endif
    }

    private func detailTag(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }
}
