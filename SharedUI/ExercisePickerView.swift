import SwiftUI
import DriftCore

// MARK: - Exercise Picker (873 exercises + history + custom)
//
// SharedUI single-source (#1064 directive 1c) — verbatim iOS body. Deviations,
// each platform-forced: property wrappers lose `private` (Skip constraint),
// SF Symbols route through sym(), the selection haptic is UIKit-gated.

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var showingCustom = false
    @State var selectedBodyPartFilter: String? = nil
    @State var favs: Set<String> = WorkoutService.exerciseFavorites
    @FocusState var searchFocused: Bool
    /// Batch selection (2026-07-07 field ask): tapping a row used to add +
    /// dismiss immediately, so building a 4-exercise workout meant reopening
    /// this sheet 4 times. Rows now TOGGLE into this ordered list; one
    /// "Add N" button hands them all to `onSelect` and dismisses once.
    @State var selected: [String] = []

    #if os(Android)
    // Catalog + DB reads are sync JNI work — off the view body on Android
    // (#1073/#1074): every list loads once per input change into @State, and
    // per-row last weights batch into one dictionary (they were one SQLite
    // query per row per body evaluation).
    @State var results: [ExerciseDatabase.ExerciseInfo] = []
    @State var favoriteExercises: [ExerciseDatabase.ExerciseInfo] = []
    @State var recentExercises: [String] = []
    @State var historyExtras: [String] = []
    @State var lastWeights: [String: Double] = [:]
    /// Catalog entry per visible row, resolved during `reload()`. The row
    /// builder used to call `ExerciseDatabase.info(for:)` itself, which reads
    /// the custom-exercise blob out of UserDefaults — one JNI hop per row per
    /// recomposition, ~50 per frame while typing (#1074).
    @State var infoByName: [String: ExerciseDatabase.ExerciseInfo] = [:]

    private struct PickerLists: @unchecked Sendable {
        var results: [ExerciseDatabase.ExerciseInfo] = []
        var favorites: [ExerciseDatabase.ExerciseInfo] = []
        var recents: [String] = []
        var extras: [String] = []
        var weights: [String: Double] = [:]
        var info: [String: ExerciseDatabase.ExerciseInfo] = [:]
    }

    /// `debounced` is set for keystroke-driven reloads only. Typing "bench"
    /// used to fire five overlapping full reloads — catalog rebuild plus a
    /// weight query each — with nothing cancelling the stale ones (#1074).
    /// `.task(id:)` cancels the previous run, so the sleep collapses a burst of
    /// keystrokes into one reload; filter/favourite changes stay immediate.
    private func reload(debounced: Bool = false) async {
        if debounced {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
        }
        let q = query
        let filter = selectedBodyPartFilter
        let f = favs
        let lists: PickerLists = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var lists = PickerLists()
                var list = q.isEmpty ? ExerciseDatabase.allWithCustom : ExerciseDatabase.search(query: q)
                if let filter { list = list.filter { $0.bodyPart == filter } }
                list.sort { f.contains($0.name) && !f.contains($1.name) }
                lists.results = Array(list.prefix(50))
                if !f.isEmpty && q.isEmpty {
                    var matched = ExerciseDatabase.allWithCustom.filter { f.contains($0.name) }
                    if let filter { matched = matched.filter { $0.bodyPart == filter } }
                    lists.favorites = matched
                }
                let recents = (try? WorkoutService.recentExerciseNames(limit: 10)) ?? []
                var filteredRecents = recents.filter { !f.contains($0) }
                if !q.isEmpty { filteredRecents = filteredRecents.filter { $0.localizedCaseInsensitiveContains(q) } }
                if let filter { filteredRecents = filteredRecents.filter { ExerciseDatabase.bodyPart(for: $0) == filter } }
                lists.recents = filteredRecents
                let allKnown = Set(ExerciseDatabase.allWithCustom.map { $0.name.lowercased() })
                let history = (try? WorkoutService.allExerciseNames()) ?? []
                var extras = history.filter { !allKnown.contains($0.lowercased()) }
                if !q.isEmpty { extras = extras.filter { $0.localizedCaseInsensitiveContains(q) } }
                lists.extras = extras
                var names = Set(lists.results.map(\.name))
                names.formUnion(lists.favorites.map(\.name))
                names.formUnion(lists.recents)
                // ONE query for every visible row — this was 50-60 serial
                // round-trips, each crossing JNI (#1074).
                lists.weights = (try? WorkoutService.lastWeights(for: Array(names))) ?? [:]
                // Catalog lookups for the rows happen here, once, off the main
                // thread. results/favorites already carry their ExerciseInfo;
                // only the name-only sections need resolving.
                for exercise in lists.results { lists.info[exercise.name] = exercise }
                for exercise in lists.favorites { lists.info[exercise.name] = exercise }
                for name in lists.recents + lists.extras where lists.info[name] == nil {
                    lists.info[name] = ExerciseDatabase.info(for: name)
                }
                continuation.resume(returning: lists)
            }
        }
        // A cancelled reload must not publish its stale lists over a newer one.
        if Task.isCancelled { return }
        infoByName = lists.info
        results = lists.results
        favoriteExercises = lists.favorites
        recentExercises = lists.recents
        historyExtras = lists.extras
        lastWeights = lists.weights
    }
    #else
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
    #endif

    /// Row trailing weight — Android reads the batched dictionary; iOS keeps
    /// its inline query (unchanged behavior).
    private func rowLastWeight(_ name: String) -> Double? {
        #if os(Android)
        return lastWeights[name]
        #else
        return try? WorkoutService.lastWeight(for: name)
        #endif
    }

    /// Row catalog entry — Android reads the dictionary built in `reload()`;
    /// iOS keeps its inline lookup (unchanged behavior). Same shape as
    /// `rowLastWeight` above.
    private func rowInfo(_ name: String) -> ExerciseDatabase.ExerciseInfo? {
        #if os(Android)
        return infoByName[name]
        #else
        return ExerciseDatabase.info(for: name)
        #endif
    }

    /// `ExerciseDatabase.bodyPart(for:)` is `info(for:)?.bodyPart ?? guess(...)`,
    /// so the Android path resolves it from the prebuilt dictionary rather than
    /// re-reading the catalog per row. `guessBodyPart` is pure string logic.
    private func rowBodyPart(_ name: String) -> String {
        #if os(Android)
        return infoByName[name]?.bodyPart ?? ExerciseDatabase.guessBodyPart(name)
        #else
        return ExerciseDatabase.bodyPart(for: name)
        #endif
    }

    /// Row identity is scoped per section: the same exercise legitimately
    /// appears in Favorites AND All Exercises (or Recent AND Your Exercises),
    /// and Compose's LazyColumn hard-crashes on duplicate keys across the
    /// whole List where iOS merely tolerates them.
    private struct SectionEntry: Identifiable {
        let sectionKey: String
        let name: String
        let bodyPart: String
        var equipment: String? = nil
        var id: String { sectionKey + "|" + name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(Android)
                // SkipUI's inline nav bar does not reserve layout space inside a
                // sheet: Cancel and the title paint ON TOP of the VStack's first
                // child, so they landed across the search field. Draw the header
                // as real content and leave the nav bar empty — same two bands
                // as iPhone (nav row, then the search row).
                ZStack {
                    Text("Add Exercise").font(.headline)
                    HStack {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                #endif
                HStack {
                    Image(systemName: sym("magnifyingglass")).foregroundStyle(Theme.textSecondary)
                    TextField("Search exercises", text: $query).textFieldStyle(.plain).autocorrectionDisabled()
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: sym("xmark.circle.fill")).foregroundStyle(Theme.textSecondary) }
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
                #if os(Android)
                // Fuse measures a horizontal ScrollView's height as the text
                // line alone once the IME closes, silently dropping the chip
                // and row padding — the chips render clipped or, on short
                // screens, vanish (#1089). Pin the natural height.
                .frame(height: 38)
                #endif

                List {
                    // Custom exercise option
                    Button { showingCustom = true } label: {
                        Label("Create Custom Exercise", systemImage: sym("plus.circle.fill")).foregroundStyle(Theme.accent)
                    }

                    // Favorite exercises
                    if !favoriteExercises.isEmpty {
                        Section("Favorites") {
                            ForEach(favoriteExercises.map { SectionEntry(sectionKey: "fav", name: $0.name, bodyPart: $0.bodyPart, equipment: $0.equipment) }) { e in
                                exerciseRow(name: e.name, bodyPart: e.bodyPart, equipment: e.equipment)
                            }
                        }
                    }

                    // Recently used
                    if !recentExercises.isEmpty {
                        Section("Recent") {
                            ForEach(recentExercises.map { SectionEntry(sectionKey: "recent", name: $0, bodyPart: rowBodyPart($0)) }) { e in
                                exerciseRow(name: e.name, bodyPart: e.bodyPart)
                            }
                        }
                    }

                    // History exercises (logged before but not in DB)
                    if !historyExtras.isEmpty {
                        Section("Your Exercises") {
                            ForEach(historyExtras.map { SectionEntry(sectionKey: "extra", name: $0, bodyPart: rowBodyPart($0)) }) { e in
                                exerciseRow(name: e.name, bodyPart: e.bodyPart)
                            }
                        }
                    }

                    // Database exercises
                    Section(query.isEmpty ? "All Exercises (\(results.count))" : "\(results.count) results") {
                        ForEach(results.map { SectionEntry(sectionKey: "all", name: $0.name, bodyPart: $0.bodyPart, equipment: $0.equipment) }) { e in
                            exerciseRow(name: e.name, bodyPart: e.bodyPart, equipment: e.equipment)
                        }
                    }
                }.listStyle(.plain)
            }
            #if !os(Android)
            .navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            #endif
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
                    #if os(Android)
                    // iOS recomputes the lists on body invalidation; the
                    // Android @State copies must refresh to show the entry.
                    Task { await reload() }
                    #endif
                }
            }
            .onAppear {
                favs = WorkoutService.exerciseFavorites
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
            }
            #if os(Android)
            // `.task(id:)` doubles as the initial load (query starts empty, so
            // that first run skips the debounce) and as the cancel-on-keystroke
            // driver for typing.
            .task(id: query) { await reload(debounced: !query.isEmpty) }
            .onChange(of: selectedBodyPartFilter) { _, _ in Task { await reload() } }
            .onChange(of: favs) { _, _ in Task { await reload() } }
            #endif
        }
    }

    private func toggleSelection(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    private func exerciseRow(name: String, bodyPart: String, equipment: String? = nil) -> some View {
        let info = rowInfo(name)
        let isSelected = selected.contains(name)
        return Button { toggleSelection(name) } label: {
            HStack(spacing: 10) {
                ExerciseThumbnail(info: info, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if favs.contains(name) {
                            Image(systemName: sym("star.fill")).font(.caption2).foregroundStyle(Theme.fatYellow)
                        }
                        Text(name).font(.subheadline)
                        Spacer()
                        if let lastW = rowLastWeight(name) {
                            Text("\(WeightFormatter.plain(Preferences.weightUnit.convertFromLbs(lastW))) \(Preferences.weightUnit.displayName)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                        #if os(Android)
                        // Material has no outline "circle", so sym() falls back
                        // to `checkmark.circle` — which drew a faint CHECK on
                        // every UNSELECTED row, the one glyph that must not
                        // read as "already selected". Draw the ring instead;
                        // the selected state keeps the real filled checkmark.
                        if isSelected {
                            Image(systemName: sym("checkmark.circle.fill"))
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .accessibilityLabel("Selected")
                        } else {
                            // `.stroke` not `.strokeBorder` — SkipUI's
                            // strokeBorder overload set is ambiguous here.
                            Circle()
                                .stroke(Theme.textTertiary.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 21, height: 21)
                                .accessibilityLabel("Not selected")
                        }
                        #else
                        Image(systemName: isSelected ? sym("checkmark.circle.fill") : sym("circle"))
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary.opacity(0.5))
                            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                        #endif
                    }
                    HStack(spacing: 4) {
                        if !bodyPart.isEmpty {
                            pickerMuscleChip(bodyPart)
                        }
                        if let equipment, !equipment.isEmpty && equipment.lowercased() != "other" {
                            pickerEquipmentChip(equipment)
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
                Label(favs.contains(name) ? "Unfavorite" : "Favorite", systemImage: sym(favs.contains(name) ? "star.slash" : "star"))
            }.tint(Theme.fatYellow)
        }
    }

    // Picker chips keep the coral tint (the browser's shared muscleChip went
    // quiet-gray in the 2026-07-10 design pass; this screen didn't).
    private func pickerMuscleChip(_ bodyPart: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: sym(muscleIcon(bodyPart))).font(.system(size: 8))
            Text(bodyPart).font(.system(size: Theme.FontSize.nano))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Theme.accent.opacity(0.1), in: Capsule())
        .foregroundStyle(Theme.accent)
    }

    private func pickerEquipmentChip(_ equipment: String) -> some View {
        HStack(spacing: 2) {
            equipmentGlyph(equipment, tint: Theme.textSecondary)
            Text(equipment.capitalized).font(.system(size: Theme.FontSize.nano))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
        .foregroundStyle(Theme.textSecondary)
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
    @Environment(\.dismiss) var dismiss
    @State var name: String
    @State var bodyPart = "Chest"

    // `initialName` seeds the name field so the browser's `Add "squat" as
    // custom exercise` CTA opens with "squat" already typed (#1082) instead
    // of a blank field. Defaulted, so the picker's plain call is unchanged.
    init(initialName: String = "", onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

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
