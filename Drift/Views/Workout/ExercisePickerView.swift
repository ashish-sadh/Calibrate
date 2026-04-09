import SwiftUI

// MARK: - Exercise Picker (873 exercises + history + custom)

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showingCustom = false
    @State private var selectedBodyPartFilter: String? = nil
    @State private var favs: Set<String> = WorkoutService.exerciseFavorites
    @FocusState private var searchFocused: Bool

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
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }.padding().background(.ultraThinMaterial)

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
            .sheet(isPresented: $showingCustom) {
                CustomExerciseSheet { name in onSelect(name); dismiss() }
            }
            .onAppear {
                favs = WorkoutService.exerciseFavorites
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
            }
        }
    }

    private func exerciseRow(name: String, bodyPart: String, equipment: String? = nil) -> some View {
        Button { onSelect(name); dismiss() } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if favs.contains(name) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.fatYellow)
                    }
                    Text(name).font(.subheadline)
                    Spacer()
                    if let lastW = try? WorkoutService.lastWeight(for: name) {
                        Text("\(Int(lastW)) lb").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(bodyPart).font(.caption2).foregroundStyle(.tertiary)
                }
                if let equipment, !equipment.isEmpty {
                    Text(equipment).font(.caption).foregroundStyle(.quaternary)
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

    private func filterChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.3) : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
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
