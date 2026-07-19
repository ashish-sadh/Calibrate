import SwiftUI
import DriftCore

// ExerciseThumbnail, PoseCrossfadeView, ExerciseDetailView and the exercise
// chips live in SharedUI/ — single-sourced with the Android app (#1064).

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
                CustomExerciseSheet { _ in }
            }
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var text: String = ""
    var items: [Any]?
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items ?? [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
