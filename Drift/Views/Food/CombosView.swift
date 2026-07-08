import SwiftUI
import DriftCore

struct CombosView: View {
    @State var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var editingCombo: Food? = nil
    @State private var showingBuilder = false
    @State private var comboToLog: Food? = nil

    private var filtered: [Food] {
        guard !searchQuery.isEmpty else { return viewModel.combos }
        return viewModel.combos.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.combos.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filtered) { combo in
                            comboRow(combo)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(combo) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { edit(combo) } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Theme.accent)
                                }
                                .swipeActions(edge: .leading) {
                                    Button { pin(combo) } label: {
                                        Label(isPinned(combo) ? "Unpin" : "Pin", systemImage: isPinned(combo) ? "pin.slash" : "pin")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchQuery, prompt: "Search combos")
                }
            }
            .navigationTitle("Combos & Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editingCombo = nil; showingBuilder = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add combo")
                }
            }
            .sheet(item: $comboToLog) { combo in
                ComboLogSheet(combo: combo, viewModel: viewModel) {
                    viewModel.loadSuggestions()
                }
            }
            .sheet(isPresented: $showingBuilder, onDismiss: { viewModel.loadSuggestions() }) {
                if let combo = editingCombo {
                    QuickAddView(viewModel: viewModel,
                                 initialItems: combo.recipeItems ?? [],
                                 initialName: combo.name,
                                 editingRecipeID: combo.id)
                } else {
                    QuickAddView(viewModel: viewModel)
                }
            }
        }
    }

    private func comboRow(_ combo: Food) -> some View {
        let items = combo.recipeItems ?? []
        let totalCal = items.reduce(0) { $0 + $1.calories }
        let totalP = items.reduce(0) { $0 + $1.proteinG }

        return HStack(spacing: 12) {
            // Tap the label area → edit. Keeps the iOS convention of row-tap =
            // detail/edit, trailing accessory = primary action. Swipe still
            // works for power users.
            Button { edit(combo) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if isPinned(combo) {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                        }
                        Text(combo.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                    Text(items.isEmpty ? combo.macroSummary : "\(items.count) items · \(Int(totalCal)) cal · \(Int(totalP))g P")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { edit(combo) } label: {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(8)
                    .background(Theme.cardBackgroundElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(combo.name)")

            Button {
                comboToLog = combo
            } label: {
                Text("+ Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle").font(.system(size: Theme.FontSize.display4)).foregroundStyle(Theme.textTertiary)
            Text("No combos yet").font(.headline)
            Text("Foods you log together often will appear here automatically, or create one with +")
                .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button { showingBuilder = true } label: {
                Label("Create Combo", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    private func isPinned(_ combo: Food) -> Bool {
        (try? AppDatabase.shared.isFoodFavorite(name: combo.name)) ?? false
    }

    private func pin(_ combo: Food) {
        try? AppDatabase.shared.toggleFoodFavorite(name: combo.name, foodId: combo.id)
        viewModel.loadSuggestions()
    }

    private func delete(_ combo: Food) {
        guard let id = combo.id else { return }
        try? AppDatabase.shared.writer.write { db in try Food.deleteOne(db, key: id) }
        viewModel.loadSuggestions()
    }

    private func edit(_ combo: Food) {
        editingCombo = combo
        showingBuilder = true
    }
}
