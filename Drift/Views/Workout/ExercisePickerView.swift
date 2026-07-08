import SwiftUI
import DriftCore

// MARK: - Exercise Picker (873 exercises + history + custom)

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showingCustom = false
    @State private var selectedBodyPartFilter: String? = nil
    @State private var favs: Set<String> = WorkoutService.exerciseFavorites
    @FocusState private var searchFocused: Bool
    /// Batch selection (2026-07-07 field ask): tapping a row used to add +
    /// dismiss immediately, so building a 4-exercise workout meant reopening
    /// this sheet 4 times. Rows now TOGGLE into this ordered list; one
    /// "Add N" button hands them all to `onSelect` and dismisses once.
    @State private var selected: [String] = []

    private var results: [ExerciseDatabase.ExerciseInfo] {
        var list = query.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: query)
        if let filter = selectedBodyPartFilter { list = list.filter { $0.bodyPart == filter } }
        // Rank favorites first
        let f = favs
        list.sort { f.contains($0.name) && !f.contains($1.name) }
        return Array(list.prefix(50))
    }

    private var favoriteExercises: [ExerciseDatabase.ExerciseInfo] {
        guard !favs.isEmpty, query.isEmpty else { return [] }
        let all = ExerciseDatabase.allWithCustom
        var matched = all.filter { favs.contains($0.name) }
        if let filter = selectedBodyPartFilter { matched = matched.filter { $0.bodyPart == filter } }
        return matched
    }

    private var recentExercises: [String] {
        let recents = (try? WorkoutService.recentExerciseNames(limit: 10)) ?? []
        let favNames = favs
        var filtered = recents.filter { !favNames.contains($0) }
        if !query.isEmpty { filtered = filtered.filter { $0.localizedCaseInsensitiveContains(query) } }
        if let filter = selectedBodyPartFilter {
            filtered = filtered.filter { ExerciseDatabase.bodyPart(for: $0) == filter }
        }
        return filtered
    }

    // Exercises from workout history that aren't in the database
    private var historyExtras: [String] {
        let allKnown = Set(ExerciseDatabase.allWithCustom.map { $0.name.lowercased() })
        let history = (try? WorkoutService.allExerciseNames()) ?? []
        let filtered = history.filter { !allKnown.contains($0.lowercased()) }
        if query.isEmpty { return filtered }
        return filtered.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) }
                    }
                }
                .padding()
                .background(Theme.cardBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                }

                // Body part filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip("All", selected: selectedBodyPartFilter == nil) { selectedBodyPartFilter = nil }
                        ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"], id: \.self) { part in
                            filterChip(part, selected: selectedBodyPartFilter == part) { selectedBodyPartFilter = part }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }

                List {
                    // Custom exercise option
                    Button { showingCustom = true } label: {
                        Label("Create Custom Exercise", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }

                    // Favorite exercises
                    if !favoriteExercises.isEmpty {
                        Section("Favorites") {
                            ForEach(favoriteExercises) { ex in
                                exerciseRow(name: ex.name, bodyPart: ex.bodyPart, equipment: ex.equipment)
                            }
                        }
                    }

                    // Recently used
                    if !recentExercises.isEmpty {
                        Section("Recent") {
                            ForEach(recentExercises, id: \.self) { name in
                                exerciseRow(name: name, bodyPart: ExerciseDatabase.bodyPart(for: name))
                            }
                        }
                    }

                    // History exercises (logged before but not in DB)
                    if !historyExtras.isEmpty {
                        Section("Your Exercises") {
                            ForEach(historyExtras, id: \.self) { name in
                                exerciseRow(name: name, bodyPart: ExerciseDatabase.bodyPart(for: name))
                            }
                        }
                    }

                    // Database exercises
                    Section(query.isEmpty ? "All Exercises (\(results.count))" : "\(results.count) results") {
                        ForEach(results) { ex in
                            exerciseRow(name: ex.name, bodyPart: ex.bodyPart, equipment: ex.equipment)
                        }
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            // One tap per exercise, one dismiss for the whole batch.
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    Button {
                        selected.forEach(onSelect)
                        dismiss()
                    } label: {
                        Text("Add \(selected.count) Exercise\(selected.count == 1 ? "" : "s")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .background(.thinMaterial)
                    .accessibilityIdentifier("exercise-picker-add-batch")
                }
            }
            .sheet(isPresented: $showingCustom) {
                // Custom exercise joins the batch (selected + visible in the
                // list) instead of add-and-dismiss, same as any other row.
                CustomExerciseSheet { name in
                    if !selected.contains(name) { selected.append(name) }
                }
            }
            .onAppear {
                favs = WorkoutService.exerciseFavorites
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
            }
        }
    }

    private func toggleSelection(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func exerciseRow(name: String, bodyPart: String, equipment: String? = nil) -> some View {
        let info = ExerciseDatabase.info(for: name)
        let isSelected = selected.contains(name)
        return Button { toggleSelection(name) } label: {
            HStack(spacing: 10) {
                ExerciseThumbnail(info: info, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if favs.contains(name) {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.fatYellow)
                        }
                        Text(name).font(.subheadline)
                        Spacer()
                        if let lastW = try? WorkoutService.lastWeight(for: name) {
                            Text("\(Int(Preferences.weightUnit.convertFromLbs(lastW))) \(Preferences.weightUnit.displayName)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary.opacity(0.5))
                            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                    }
                    HStack(spacing: 4) {
                        if !bodyPart.isEmpty {
                            muscleChip(bodyPart)
                        }
                        if let equipment, !equipment.isEmpty && equipment.lowercased() != "other" {
                            equipmentChip(equipment)
                        }
                    }
                }
            }
        }
        .tint(.primary)
        .swipeActions(edge: .leading) {
            Button {
                WorkoutService.toggleExerciseFavorite(name)
                favs = WorkoutService.exerciseFavorites
            } label: {
                Label(favs.contains(name) ? "Unfavorite" : "Favorite", systemImage: favs.contains(name) ? "star.slash" : "star")
            }.tint(Theme.fatYellow)
        }
    }

    private func muscleChip(_ bodyPart: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: muscleIcon(bodyPart)).font(.system(size: 8))
            Text(bodyPart).font(.system(size: Theme.FontSize.nano))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Theme.accent.opacity(0.1), in: Capsule())
        .foregroundStyle(Theme.accent)
    }

    private func equipmentChip(_ equipment: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: equipmentIcon(equipment)).font(.system(size: 8))
            Text(equipment.capitalized).font(.system(size: Theme.FontSize.nano))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
        .foregroundStyle(Theme.textSecondary)
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

    private func filterChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.ink : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
    }
}

// MARK: - Custom Exercise Sheet

struct CustomExerciseSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bodyPart = "Chest"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Targets", selection: $bodyPart) {
                    ForEach(["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body"], id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle("Custom Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        ExerciseDatabase.addCustomExercise(name: name, bodyPart: bodyPart)
                        onSave(name)
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
