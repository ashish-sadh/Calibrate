import SwiftUI

// MARK: - Exercise Thumbnail

struct ExerciseThumbnail: View {
    let info: ExerciseDatabase.ExerciseInfo?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlStr = info?.imageUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    private var fallback: some View {
        Image(systemName: bodyPartIcon(info?.bodyPart ?? ""))
            .font(.system(size: size * 0.38))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accent.opacity(0.1))
    }

    private func bodyPartIcon(_ bodyPart: String) -> String {
        switch bodyPart.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.boxing"
        case "arms": return "figure.cooldown"
        case "core": return "figure.core.training"
        default: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Exercise Browser (873 exercises)

struct ExerciseBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedPart: String? = nil
    @State private var showingCustom = false

    private var results: [ExerciseDatabase.ExerciseInfo] {
        var list = query.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: query)
        if let part = selectedPart { list = list.filter { $0.bodyPart == part } }
        let favs = WorkoutService.exerciseFavorites
        list.sort { favs.contains($0.name) && !favs.contains($1.name) }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                }.padding().background(.ultraThinMaterial)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", selected: selectedPart == nil) { selectedPart = nil }
                        ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"], id: \.self) { p in
                            chip(p, selected: selectedPart == p) { selectedPart = p }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }

                List {
                    if !query.isEmpty && results.isEmpty {
                        Button { showingCustom = true } label: {
                            Label("Add \"\(query)\" as custom exercise", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }

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
                                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }.tint(.primary)
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Exercise Database").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCustom = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCustom) {
                CustomExerciseSheet { _ in }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.3) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
    }

    private func muscleChip(_ bodyPart: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: muscleIcon(bodyPart)).font(.system(size: 8))
            Text(bodyPart).font(.system(size: 9))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Theme.accent.opacity(0.1), in: Capsule())
        .foregroundStyle(Theme.accent)
    }

    private func equipmentChip(_ equipment: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: equipmentIcon(equipment)).font(.system(size: 8))
            Text(equipment.capitalized).font(.system(size: 9))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
        .foregroundStyle(.secondary)
    }

    private func muscleIcon(_ bodyPart: String) -> String {
        switch bodyPart.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.boxing"
        case "arms": return "figure.cooldown"
        case "core": return "figure.core.training"
        default: return "figure.mixed.cardio"
        }
    }

    private func equipmentIcon(_ equipment: String) -> String {
        switch equipment.lowercased() {
        case "barbell", "e-z curl bar": return "dumbbell.fill"
        case "dumbbell": return "dumbbell"
        case "cable": return "link"
        case "machine": return "gearshape"
        case "body only": return "figure.stand"
        case "kettlebells": return "circle.fill"
        case "bands": return "arrow.left.and.right"
        case "exercise ball", "medicine ball": return "circle.dotted"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Exercise Detail (history + PR)

struct ExerciseDetailView: View {
    let exerciseName: String
    let info: ExerciseDatabase.ExerciseInfo?
    @State private var history: [WorkoutSet] = []
    @State private var pr: Double?
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Hero image
                if let info, let urlStr = info.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exerciseName).font(.title3.weight(.bold))
                        Spacer()
                        Button {
                            WorkoutService.toggleExerciseFavorite(exerciseName)
                            isFavorite.toggle()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(isFavorite ? Theme.fatYellow : Color.gray.opacity(0.4))
                        }
                    }

                    if let info {
                        HStack(spacing: 6) {
                            detailTag(info.bodyPart, icon: "figure.strengthtraining.traditional", color: Theme.accent)
                            detailTag(info.equipment, icon: "wrench.and.screwdriver", color: .secondary)
                            detailTag(info.level.capitalized, icon: "chart.bar", color: .secondary)
                        }

                        if let youtubeUrl = info.youtubeUrl, let url = URL(string: youtubeUrl) {
                            Link(destination: url) {
                                Label("Form Tutorial", systemImage: "play.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.red)
                            }
                        }

                        if !info.primaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Primary muscles").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                Text(info.primaryMuscles.map(\.capitalized).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.primary)
                            }
                        }
                        if !info.secondaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Secondary muscles").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                Text(info.secondaryMuscles.map(\.capitalized).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if let pr {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Theme.fatYellow)
                            Text("PR: \(Int(Preferences.weightUnit.convertFromLbs(pr))) \(Preferences.weightUnit.displayName) (est. 1RM)")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.fatYellow)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                if history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock").font(.title2).foregroundStyle(.tertiary)
                        Text("No history yet").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(history.prefix(20), id: \.id) { s in
                            HStack {
                                Text(s.isWarmup ? "W" : "\(s.setOrder)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(s.isWarmup ? Theme.fatYellow : .secondary)
                                    .frame(width: 20)
                                Text(s.display).font(.subheadline.monospacedDigit())
                                Spacer()
                                if let rm = s.estimated1RM {
                                    Text("1RM: \(Int(rm))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
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
        .onAppear {
            isFavorite = WorkoutService.exerciseFavorites.contains(exerciseName)
            history = (try? WorkoutService.fetchExerciseHistory(name: exerciseName)) ?? []
            pr = try? WorkoutService.fetchPR(for: exerciseName)
        }
    }

    private func detailTag(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var text: String = ""
    var items: [Any]?
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items ?? [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
