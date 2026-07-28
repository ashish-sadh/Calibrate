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
                            equipmentTag(info.equipment, color: .secondary)
                            #if os(Android)
                            levelTag(info.level.capitalized, color: .secondary)
                            #else
                            detailTag(info.level.capitalized, icon: sym("chart.bar"), color: .secondary)
                            #endif
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

    // Equipment can't route through `detailTag`'s `Label(_:systemImage:)` like
    // its bodyPart/level siblings: iOS hardcodes a generic wrench+screwdriver
    // here regardless of equipment type, while the browser/picker rows show
    // the SPECIFIC equipment glyph via `equipmentGlyph()` (dumbbell, kettlebell,
    // cable, ...). Routing through the same shared helper makes this the third
    // equipment surface and keeps the detail screen consistent with the rows
    // that lead to it, on both platforms (#1099).
    private func equipmentTag(_ equipment: String, color: Color) -> some View {
        HStack(spacing: 4) {
            equipmentGlyph(equipment, tint: color)
            Text(equipment.capitalized)
        }
        .font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(color)
    }

    #if os(Android)
    // Pinned skip-ui 1.58.0 (#1134) has no chart glyph at all — sym("chart.bar")
    // targets chart.bar.xaxis, which only exists in skip-ui ≥1.59, so this call
    // site rendered the warning triangle. Same drawn-shape precedent already
    // used at WorkoutView.overloadCard and ClientDetailView (ChartGlyph.swift);
    // iOS is untouched and keeps rendering the real SF Symbol via detailTag.
    private func levelTag(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            BarChartShape().fill(color).frame(width: 11, height: 11)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(color)
    }
    #endif
}
