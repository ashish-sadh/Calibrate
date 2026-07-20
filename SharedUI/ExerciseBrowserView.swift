import SwiftUI
import DriftCore

// ExerciseThumbnail, PoseCrossfadeView, ExerciseDetailView and the exercise
// chips live in SharedUI/ — single-sourced with the Android app (#1064).

// MARK: - Exercise Browser (873 exercises)

struct ExerciseBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var selectedPart: String? = nil
    @State var showingCustom = false

    #if os(Android)
    // Catalog + favorites reads are sync DB/JSON work — off the view body on
    // Android (#1073), loaded once per query/filter change into @State.
    @State var results: [ExerciseDatabase.ExerciseInfo] = []

    /// See `ExercisePickerView.reload(debounced:)` — same cancel-on-keystroke
    /// contract, driven by `.task(id: query)` (#1074).
    private func reload(debounced: Bool = false) async {
        if debounced {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
        }
        let q = query
        let part = selectedPart
        let loaded: [ExerciseDatabase.ExerciseInfo] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var list = q.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: q)
                if let part { list = list.filter { $0.bodyPart == part } }
                let favs = WorkoutService.exerciseFavorites
                list.sort { favs.contains($0.name) && !favs.contains($1.name) }
                continuation.resume(returning: list)
            }
        }
        // A cancelled reload must not publish its stale results over a newer one.
        if Task.isCancelled { return }
        results = loaded
    }
    #else
    private var results: [ExerciseDatabase.ExerciseInfo] {
        var list = query.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: query)
        if let part = selectedPart { list = list.filter { $0.bodyPart == part } }
        let favs = WorkoutService.exerciseFavorites
        list.sort { favs.contains($0.name) && !favs.contains($1.name) }
        return list
    }
    #endif

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
                                                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
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
                    .accessibilityLabel("Add custom exercise")
                }
            }
            .sheet(isPresented: $showingCustom) {
                CustomExerciseSheet { _ in
                    #if os(Android)
                    // iOS recomputes `results` on body invalidation; the
                    // Android @State copy must refresh to show the new entry.
                    Task { await reload() }
                    #endif
                }
            }
            #if os(Android)
            .task(id: query) { await reload(debounced: !query.isEmpty) }
            .onChange(of: selectedPart) { _, _ in Task { await reload() } }
            #endif
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Theme.ink : Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
    }

}

