import SwiftUI
import Charts

struct FoodTabView: View {
    @Binding var selectedTab: Int
    @State private var viewModel = FoodLogViewModel()
    @State private var showingSearch = false
    @State private var showingRecipeBuilder = false
    @State private var showingScanner = false
    @State private var loggedDays: [Date: Double] = [:]
    @State private var showingDatePicker = false
    @State private var editingEntry: FoodEntry?
    @State private var editAmount = "1"
    @State private var editUnitIndex = 0
    @State private var editEntryIsFav = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dateNav
                    dailyTotalsCard
                    foodDiary
                    if !loggedDays.isEmpty { consistencySection }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSearch = true } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) { BarcodeLookupView(viewModel: viewModel) }
            .sheet(isPresented: $showingSearch) { FoodSearchView(viewModel: viewModel) }
            .sheet(isPresented: $showingRecipeBuilder) { QuickAddView(viewModel: viewModel) }
            .sheet(item: $editingEntry) { entry in editEntrySheet(entry) }
            .onAppear { reload() }
            .onChange(of: showingSearch) { _, showing in if !showing { reload() } }
            .onChange(of: showingRecipeBuilder) { _, showing in if !showing { reload() } }
            .onChange(of: showingScanner) { _, showing in if !showing { reload() } }
        }
    }

    private func reload() {
        viewModel.loadTodayMeals()
        viewModel.loadSuggestions()
        loggedDays = viewModel.loggedDays(last: 30)
    }

    // MARK: - Date Navigator

    private var dateNav: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let selected = cal.startOfDay(for: viewModel.selectedDate)

        // Build 7 days centered on selected date (3 before, selected, 3 after)
        let days: [Date] = (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: selected) }
        let dayFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "EEE"; return f
        }()

        return VStack(spacing: 8) {
            // Month label — tap to open calendar
            Button { showingDatePicker = true } label: {
                Text(DateFormatters.monthYear.string(from: viewModel.selectedDate))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    DatePicker("Go to date", selection: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.goToDate($0); loggedDays = viewModel.loggedDays(last: 30) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select Date").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showingDatePicker = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Today") { viewModel.goToDate(Date()); loggedDays = viewModel.loggedDays(last: 30); showingDatePicker = false }
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .presentationDetents([.medium])
            }

            // Day strip — 7 pills
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let isSelected = cal.isDate(day, inSameDayAs: selected)
                    let isToday = cal.isDate(day, inSameDayAs: today)

                    Button {
                        viewModel.goToDate(day)
                        loggedDays = viewModel.loggedDays(last: 30)
                    } label: {
                        VStack(spacing: 3) {
                            Text(dayFormatter.string(from: day))
                                .font(.caption2)
                                .foregroundStyle(isSelected ? Color.white : Color.gray)
                            Text("\(cal.component(.day, from: day))")
                                .font(.subheadline.weight(isSelected ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(isSelected ? .white : .primary)
                            // Today dot indicator
                            Circle()
                                .fill(isToday ? Theme.accent : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Theme.accent.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Past-date warning banner
            if !viewModel.isToday {
                Button {
                    viewModel.goToDate(Date())
                    loggedDays = viewModel.loggedDays(last: 30)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(Theme.fatYellow)
                        Text("Viewing \(DateFormatters.dayDisplay.string(from: viewModel.selectedDate))")
                            .font(.caption.weight(.medium))
                        Text("· Tap to return to today")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.fatYellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Daily Totals

    private var dailyTotalsCard: some View {
        let n = viewModel.todayNutrition
        let targets = WeightGoal.load()?.macroTargets()

        return VStack(spacing: 10) {
            // Calories with target
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(n.calories))")
                    .font(.title.weight(.bold).monospacedDigit())
                if let t = targets {
                    Text("/ \(Int(t.calorieTarget))").font(.subheadline.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let t = targets {
                    let remaining = Int(t.calorieTarget - n.calories)
                    Text("\(remaining > 0 ? "\(remaining) left" : "\(abs(remaining)) over")")
                        .font(.caption.weight(.medium)).foregroundStyle(remaining >= 0 ? .secondary : Theme.surplus)
                }
            }

            // Macro progress bars (show when goals exist)
            if let t = targets {
                VStack(spacing: 6) {
                    macroProgressRow("P", eaten: n.proteinG, target: t.proteinG, color: Theme.proteinRed)
                    macroProgressRow("C", eaten: n.carbsG, target: t.carbsG, color: Theme.carbsGreen)
                    macroProgressRow("F", eaten: n.fatG, target: t.fatG, color: Theme.fatYellow)
                }
            } else {
                // No goal - show simple pills
                HStack(spacing: 8) {
                    macroPill("P", value: n.proteinG, color: Theme.proteinRed)
                    macroPill("C", value: n.carbsG, color: Theme.carbsGreen)
                    macroPill("F", value: n.fatG, color: Theme.fatYellow)
                    macroPill("Fiber", value: n.fiberG, color: Theme.fiberBrown)
                }
            }
        }
        .card()
    }

    private func macroProgressRow(_ label: String, eaten: Double, target: Double, color: Color) -> some View {
        let fraction = target > 0 ? min(eaten / target, 1.5) : 0
        return HStack(spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).frame(width: 14)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.15)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: min(geo.size.width, geo.size.width * fraction), height: 6)
                }
            }.frame(height: 6)
            Text("\(Int(eaten))/\(Int(target))g")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
    }

    private func macroPill(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 14)
            Text("\(Int(value))g \(label)").font(.caption.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6).padding(.horizontal, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Food Diary

    private var foodDiary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Food Diary").font(.subheadline.weight(.semibold))
                Spacer()
                if !viewModel.todayEntries.isEmpty {
                    Text("\(viewModel.todayEntries.count) items")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 10)

            if viewModel.todayEntries.isEmpty {
                emptyDiaryView
            } else {
                ForEach(Array(viewModel.todayEntries.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry)
                    if index < viewModel.todayEntries.count - 1 {
                        Divider().padding(.leading, 0)
                    }
                }

                Divider().padding(.vertical, 4)

                Button { showingSearch = true } label: {
                    HStack {
                        Image(systemName: "plus.circle").font(.subheadline).foregroundStyle(Theme.accent)
                        Text("Add food").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }.buttonStyle(.plain)
            }
        }
        .card()
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        let dayTotal = max(viewModel.todayNutrition.calories, 1)
        let fraction = min(entry.totalCalories / dayTotal, 1.0)

        return HStack(alignment: .center, spacing: 8) {
            // Calorie proportion bar
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent.opacity(0.3 + fraction * 0.7))
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName).font(.subheadline).lineLimit(1)
                HStack(spacing: 4) {
                    if !entry.portionText.isEmpty {
                        Text(entry.portionText).font(.caption2).foregroundStyle(.tertiary)
                        Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                    }
                    Text("\(Int(entry.totalProtein))P \(Int(entry.totalCarbs))C \(Int(entry.totalFat))F")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(Int(entry.totalCalories))").font(.subheadline.weight(.medium).monospacedDigit())
            Text("cal").font(.caption2).foregroundStyle(.tertiary)
            if let id = entry.id {
                Button {
                    viewModel.deleteEntry(id: id)
                    reload()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.quaternary)
                }.buttonStyle(.plain).padding(.leading, 4)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.foodName), \(Int(entry.totalCalories)) calories, \(Int(entry.totalProtein)) protein, \(Int(entry.totalCarbs)) carbs, \(Int(entry.totalFat)) fat")
        .onTapGesture {
            if entry.servingSizeG > 0 {
                let food = Food(name: entry.foodName, category: "", servingSize: entry.servingSizeG,
                                servingUnit: "g", calories: entry.calories)
                let units = FoodUnit.smartUnits(for: food)
                let primary = units.first ?? FoodUnit(label: "serving", gramsEquivalent: entry.servingSizeG)
                let totalG = entry.servingSizeG * entry.servings
                let amountInPrimary = primary.gramsEquivalent > 0 ? totalG / primary.gramsEquivalent : entry.servings
                editAmount = amountInPrimary == Double(Int(amountInPrimary))
                    ? "\(Int(amountInPrimary))" : String(format: "%.1f", amountInPrimary)
                editUnitIndex = 0
            } else {
                // Manual/recipe entry — use a simple multiplier
                editAmount = entry.servings == Double(Int(entry.servings))
                    ? "\(Int(entry.servings))" : String(format: "%.1f", entry.servings)
                editUnitIndex = 0
            }
            editEntryIsFav = (try? AppDatabase.shared.isFoodFavorite(name: entry.foodName)) ?? false
            editingEntry = entry
        }
        .contextMenu {
            Button {
                try? AppDatabase.shared.toggleFoodFavorite(name: entry.foodName, foodId: entry.foodId)
                viewModel.loadSuggestions()
            } label: {
                let isFav = (try? AppDatabase.shared.isFoodFavorite(name: entry.foodName)) ?? false
                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
            }
            Button {
                viewModel.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                                   proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                                   fatG: entry.totalFat, fiberG: entry.totalFiber,
                                   mealType: viewModel.autoMealType)
                reload()
            } label: {
                Label("Log Again", systemImage: "arrow.counterclockwise")
            }
            if let id = entry.id {
                Button(role: .destructive) {
                    viewModel.deleteEntry(id: id)
                    reload()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var emptyDiaryView: some View {
        VStack(spacing: 14) {
            Text("No food logged").font(.subheadline).foregroundStyle(.tertiary)

            Button { showingSearch = true } label: {
                Label("Add food", systemImage: "plus.circle")
                    .font(.subheadline).foregroundStyle(Theme.accent)
            }

            // Copy from yesterday
            if let yesterdayCal = yesterdayCalories(), yesterdayCal > 0 {
                Button {
                    copyFromYesterday()
                    reload()
                } label: {
                    HStack(spacing: 4) {
                        Label("Copy previous day", systemImage: "doc.on.doc")
                        Text("(\(Int(yesterdayCal)) cal)")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption).foregroundStyle(Theme.accent)
                }
                .padding(.top, 2)
            }

            if !viewModel.recentFoods.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECENT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(viewModel.recentFoods.prefix(5)) { food in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(food.name).font(.subheadline).lineLimit(1)
                                Text(food.macroSummary).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { viewModel.quickLogFood(food); reload() } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }.buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button {
                                try? AppDatabase.shared.toggleFoodFavorite(name: food.name, foodId: food.id)
                                viewModel.loadSuggestions()
                            } label: {
                                let isFav = (try? AppDatabase.shared.isFoodFavorite(name: food.name)) ?? false
                                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func quickAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.accent)
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    private func yesterdayCalories() -> Double? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate) else { return nil }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        return (try? AppDatabase.shared.fetchDailyNutrition(for: dateStr))?.calories
    }

    private func copyFromYesterday() {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate) else { return }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        guard let logs = try? AppDatabase.shared.fetchMealLogs(for: dateStr) else { return }
        for log in logs {
            guard let logId = log.id else { continue }
            guard let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: logId) else { continue }
            for entry in entries {
                viewModel.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                                   proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                                   fatG: entry.totalFat, fiberG: entry.totalFiber,
                                   mealType: viewModel.autoMealType)
            }
        }
    }

    // MARK: - Edit Entry Sheet

    private func editEntrySheet(_ entry: FoodEntry) -> some View {
        let hasServingSize = entry.servingSizeG > 0
        // For DB foods: reconstruct Food for smart units
        let food = hasServingSize
            ? Food(name: entry.foodName, category: "", servingSize: entry.servingSizeG,
                   servingUnit: "g", calories: entry.calories,
                   proteinG: entry.proteinG, carbsG: entry.carbsG,
                   fatG: entry.fatG, fiberG: entry.fiberG)
            : nil
        let units = food.map { FoodUnit.smartUnits(for: $0) } ?? []
        let safeIndex = min(editUnitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "serving", gramsEquivalent: max(entry.servingSizeG, 1)) : units[safeIndex]
        let amountNum = Double(editAmount) ?? 0
        let multiplier: Double = hasServingSize
            ? (entry.servingSizeG > 0 ? (amountNum * unit.gramsEquivalent) / entry.servingSizeG : amountNum)
            : amountNum  // manual/recipe: amount IS the multiplier

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(entry.foodName).font(.title3.weight(.semibold))
                        if hasServingSize {
                            let primaryLabel = units.first?.label ?? "serving"
                            let perText = primaryLabel == "g" || primaryLabel == "ml"
                                ? "\(Int(entry.calories))cal per \(Int(entry.servingSizeG))g"
                                : "\(Int(entry.calories))cal per 1 \(primaryLabel) (\(Int(entry.servingSizeG))g)"
                            Text(perText).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(entry.calories))cal per serving")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)

                    // Amount + unit picker
                    HStack(spacing: 12) {
                        TextField("1", text: $editAmount)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.medium).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                            .padding(.vertical, 10)
                            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))

                        if !units.isEmpty {
                            Picker("", selection: $editUnitIndex) {
                                ForEach(0..<units.count, id: \.self) { i in
                                    Text(units[i].label).tag(i)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .padding(.vertical, 10).padding(.horizontal, 16)
                            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))
                            .onChange(of: editUnitIndex) { oldIdx, newIdx in
                                guard oldIdx < units.count, newIdx < units.count else { return }
                                let oldU = units[oldIdx]
                                let newU = units[newIdx]
                                let cur = Double(editAmount) ?? 0
                                let g = cur * oldU.gramsEquivalent
                                let conv = newU.gramsEquivalent > 0 ? g / newU.gramsEquivalent : cur
                                editAmount = conv == Double(Int(conv)) ? "\(Int(conv))" : String(format: "%.1f", conv)
                            }
                        } else {
                            Text("servings").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { mult in
                            Button {
                                if hasServingSize && unit.label == "g" {
                                    editAmount = String(format: "%.0f", entry.servingSizeG * mult)
                                } else {
                                    editAmount = mult == Double(Int(mult)) ? "\(Int(mult))" : String(format: "%.1f", mult)
                                }
                            } label: {
                                Text(mult == 0.5 ? "\u{00BD}" : (mult == 1.5 ? "1\u{00BD}" : "\(Int(mult))x"))
                                    .font(.caption.weight(.medium))
                            }.buttonStyle(.bordered)
                        }
                    }

                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(entry.calories * multiplier))")
                                .font(.title.weight(.bold).monospacedDigit())
                            Text("cal").font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            editMacroChip("P", value: entry.proteinG * multiplier, color: Theme.proteinRed)
                            editMacroChip("C", value: entry.carbsG * multiplier, color: Theme.carbsGreen)
                            editMacroChip("F", value: entry.fatG * multiplier, color: Theme.fatYellow)
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingEntry = nil } }
                ToolbarItem(placement: .principal) {
                    Button {
                        try? AppDatabase.shared.toggleFoodFavorite(name: entry.foodName, foodId: entry.foodId)
                        editEntryIsFav.toggle()
                    } label: {
                        Image(systemName: editEntryIsFav ? "star.fill" : "star")
                            .foregroundStyle(editEntryIsFav ? Theme.fatYellow : .secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let id = entry.id {
                            viewModel.updateEntryServings(id: id, servings: multiplier)
                            reload()
                        }
                        editingEntry = nil
                    }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func editMacroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)").font(.caption2.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        let sorted = loggedDays.sorted { $0.key < $1.key }
        let daysLogged = sorted.filter { $0.value > 0 }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logging Consistency").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(daysLogged)/30 days").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 10)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(sorted, id: \.key) { date, cal in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cal > 0 ? Theme.accent.opacity(min(1, cal / 2000)) : Theme.cardBackgroundElevated)
                        .frame(height: 14)
                        .overlay {
                            if Calendar.current.isDateInToday(date) {
                                RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent, lineWidth: 1)
                            }
                        }
                }
            }

            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.tertiary)
                ForEach([0.0, 500.0, 1000.0, 2000.0], id: \.self) { cal in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cal > 0 ? Theme.accent.opacity(min(1, cal / 2000)) : Theme.cardBackgroundElevated)
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}
