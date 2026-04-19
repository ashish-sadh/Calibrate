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
    @State private var showingGoalSetup = false
    @State private var editingEntry: FoodEntry?
    @State private var showingPlantPointsDetail = false
    @State private var copiedToTodayName: String? = nil
    @State private var foodSortMode: FoodSortMode = .time
    @State private var showingConfirmLog = false
    @State private var confirmPrefill: AIChatViewModel.ManualFoodPrefill?
    @State private var copyToTodayEntry: FoodEntry?
    @State private var showingCopyYesterdayAlert = false
    @State private var showingCopyAllAlert = false
    @State private var searchMealType: MealType? = nil
    @State private var showingCombos = false
    @State private var comboToLog: Food? = nil
    @AppStorage("foodDiaryMealGrouped") private var mealGrouped = true

    enum FoodSortMode: String, CaseIterable {
        case time, meal, protein, carbs, fat, fiber, plantPoints
        var label: String {
            switch self {
            case .time: "🕐"
            case .meal: "🍽"
            case .protein: "P"
            case .carbs: "C"
            case .fat: "F"
            case .fiber: "Fb"
            case .plantPoints: "🌱"
            }
        }
    }

    private var sortedEntries: [FoodEntry] {
        switch foodSortMode {
        case .time: viewModel.todayEntries
        case .meal: viewModel.todayEntries  // rendering splits into sections, not a flat sort
        case .protein: viewModel.todayEntries.sorted { $0.totalProtein > $1.totalProtein }
        case .carbs: viewModel.todayEntries.sorted { $0.totalCarbs > $1.totalCarbs }
        case .fat: viewModel.todayEntries.sorted { $0.totalFat > $1.totalFat }
        case .fiber: viewModel.todayEntries.sorted { $0.totalFiber > $1.totalFiber }
        case .plantPoints: viewModel.todayEntries.sorted {
            let a = PlantPointsService.classify($0.foodName) != .notPlant
            let b = PlantPointsService.classify($1.foodName) != .notPlant
            return a && !b
        }
        }
    }

    /// Entries grouped by meal type, ordered breakfast → lunch → dinner → snack.
    /// Only used when `mealGrouped == true`.
    private var mealGroups: [(mealType: MealType, entries: [FoodEntry])] {
        let buckets: [MealType: [FoodEntry]] = Dictionary(grouping: viewModel.todayEntries) { entry in
            MealType(rawValue: entry.mealType ?? "") ?? .snack
        }
        return MealType.allCases.compactMap { meal in
            guard let entries = buckets[meal], !entries.isEmpty else { return nil }
            return (meal, entries)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dateNav
                    dailyTotalsCard
                    // PlantPointsCardView moved to compact row in dailyTotalsCard
                    // Full detail available via sheet tap
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
                    .accessibilityLabel("Add food")
                }
            }
            .fullScreenCover(isPresented: $showingScanner) { BarcodeLookupView(viewModel: viewModel) }
            .overlay(alignment: .bottom) {
                if let name = copiedToTodayName {
                    Text("Added \(name) to today")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.deficit.opacity(0.9), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: copiedToTodayName)
            .sheet(isPresented: $showingSearch) { FoodSearchView(viewModel: viewModel, initialMealType: searchMealType) }
            .sheet(isPresented: $showingRecipeBuilder) { QuickAddView(viewModel: viewModel) }
            .sheet(isPresented: $showingCombos) { CombosView(viewModel: viewModel) }
            .sheet(item: $comboToLog) { combo in
                ComboLogSheet(combo: combo, viewModel: viewModel) {
                    copiedToTodayName = combo.name
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToTodayName = nil }
                    reload()
                }
            }
            .sheet(isPresented: $showingGoalSetup) {
                NavigationStack {
                    GoalSetupView(existingGoal: WeightGoal.load()) { goal in
                        goal.save()
                        reload()
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                EditFoodEntrySheet(entry: entry, viewModel: viewModel,
                    onCopiedToToday: { name in
                        copiedToTodayName = name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToTodayName = nil }
                    },
                    onDone: { reload() })
            }
            .sheet(isPresented: $showingPlantPointsDetail) {
                NavigationStack { PlantPointsCardView(viewModel: viewModel) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingConfirmLog) {
                ManualFoodEntrySheet(viewModel: viewModel, prefill: confirmPrefill) {
                    reload()
                }
            }
            .alert("Copy to Today?", isPresented: Binding(
                get: { copyToTodayEntry != nil },
                set: { if !$0 { copyToTodayEntry = nil } }
            )) {
                Button("Cancel", role: .cancel) { copyToTodayEntry = nil }
                Button("Copy") {
                    if let entry = copyToTodayEntry {
                        viewModel.copyEntryToToday(entry)
                        copiedToTodayName = entry.foodName
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToTodayName = nil }
                    }
                    copyToTodayEntry = nil
                }
            } message: {
                if let entry = copyToTodayEntry {
                    Text("\(entry.foodName) — \(Int(entry.totalCalories)) cal, \(Int(entry.totalProtein))g protein")
                }
            }
            .alert("Copy Previous Day?", isPresented: $showingCopyYesterdayAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Copy") {
                    viewModel.copyFromYesterday()
                    reload()
                }
            } message: {
                if let cal = viewModel.yesterdayCalories() {
                    Text("This will copy all \(Int(cal)) cal from yesterday to today.")
                }
            }
            .alert("Copy All to Today?", isPresented: $showingCopyAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Copy") {
                    viewModel.copyAllToToday(entries: viewModel.todayEntries)
                    copiedToTodayName = "all \(viewModel.todayEntries.count) items"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToTodayName = nil }
                }
            } message: {
                let totalCal = viewModel.todayEntries.reduce(0) { $0 + $1.totalCalories }
                Text("Copy \(viewModel.todayEntries.count) items (\(Int(totalCal)) cal) to today?")
            }
            .onAppear { AIScreenTracker.shared.currentScreen = .food; weekOffset = 0; reload() }
            .onChange(of: showingSearch) { _, showing in if !showing { searchMealType = nil; reload() } }
            .onChange(of: showingRecipeBuilder) { _, showing in if !showing { reload() } }
            .onChange(of: showingScanner) { _, showing in if !showing { reload() } }
            .onChange(of: showingConfirmLog) { _, showing in if !showing { reload() } }
            .onChange(of: viewModel.selectedDate) { _, _ in foodSortMode = .time }
        }
    }

    private func reload() {
        foodSortMode = .time
        viewModel.loadTodayMeals()
        viewModel.loadSuggestions()
        viewModel.loadPlantPoints()
        loggedDays = viewModel.loggedDays(last: 30)
    }

    // MARK: - Date Navigator

    @State private var weekOffset: Int = 0

    private var dateNav: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let selected = cal.startOfDay(for: viewModel.selectedDate)

        // Fixed week based on weekOffset from current week's Monday
        let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) ?? currentWeekStart
        let days: [Date] = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let dayFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "EEE"; return f
        }()

        return VStack(spacing: 8) {
            // Month label — tap to open calendar
            Button { showingDatePicker = true } label: {
                HStack(spacing: 4) {
                    Text(DateFormatters.monthYear.string(from: viewModel.selectedDate))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    DatePicker("Go to date", selection: Binding(
                        get: { viewModel.selectedDate },
                        set: { date in
                            viewModel.goToDate(date)
                            loggedDays = viewModel.loggedDays(last: 30)
                            // Update weekOffset to show the week containing the picked date
                            let pickedWeek = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                            weekOffset = cal.dateComponents([.weekOfYear], from: currentWeekStart, to: pickedWeek).weekOfYear ?? 0
                        }
                    ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select Date").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showingDatePicker = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Today") { viewModel.goToDate(Date()); loggedDays = viewModel.loggedDays(last: 30); weekOffset = 0; showingDatePicker = false }
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .presentationDetents([.medium])
            }

            // Scrollable day strip — fixed week, swipe to change weeks
            ScrollViewReader { proxy in
                HStack(spacing: 4) {
                    // Previous week arrow
                    Button {
                        weekOffset -= 1
                        if let first = days.first { viewModel.goToDate(cal.date(byAdding: .day, value: -7, to: first) ?? first) }
                        loggedDays = viewModel.loggedDays(last: 30)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                            .frame(width: 24, height: 44)
                    }
                    .accessibilityLabel("Previous week")

                    // Day pills — fixed positions, only highlight moves
                    ForEach(days, id: \.self) { day in
                        let isSelected = cal.isDate(day, inSameDayAs: selected)
                        let isToday = cal.isDate(day, inSameDayAs: today)
                        let dayStart = cal.startOfDay(for: day)
                        let hasFood = (loggedDays[dayStart] ?? 0) > 0

                        Button {
                            viewModel.goToDate(day)
                            loggedDays = viewModel.loggedDays(last: 30)
                        } label: {
                            VStack(spacing: 2) {
                                Text(dayFormatter.string(from: day))
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                Text("\(cal.component(.day, from: day))")
                                    .font(.callout.weight(isSelected ? .bold : .regular).monospacedDigit())
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Circle()
                                    .fill(isToday ? Theme.accent : hasFood ? .secondary.opacity(0.5) : Color.clear)
                                    .frame(width: isSelected ? 6 : 4, height: isSelected ? 6 : 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? Theme.accent.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(dayFormatter.string(from: day)) \(cal.component(.day, from: day))\(isToday ? ", today" : "")\(hasFood ? ", food logged" : "")\(isSelected ? ", selected" : "")")
                    }

                    // Next week arrow
                    Button {
                        weekOffset += 1
                        if let last = days.last { viewModel.goToDate(cal.date(byAdding: .day, value: 1, to: last) ?? last) }
                        loggedDays = viewModel.loggedDays(last: 30)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                            .frame(width: 24, height: 44)
                    }
                    .accessibilityLabel("Next week")
                }
            }

            // Past-date warning banner
            if !viewModel.isToday {
                Button {
                    viewModel.goToDate(Date())
                    weekOffset = 0
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

                if !viewModel.todayEntries.isEmpty {
                    Button {
                        showingCopyAllAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc").font(.caption2)
                            Text("Copy all to today").font(.caption.weight(.medium))
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Daily Totals

    private var dailyTotalsCard: some View {
        let n = viewModel.todayNutrition
        let targets = viewModel.macroTargets

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

            // Macro progress bars (show when goals exist) — tap to edit diet/goal
            if let t = targets {
                VStack(spacing: 6) {
                    macroProgressRow("P", eaten: n.proteinG, target: t.proteinG, color: Theme.proteinRed)
                    macroProgressRow("C", eaten: n.carbsG, target: t.carbsG, color: Theme.carbsGreen)
                    macroProgressRow("F", eaten: n.fatG, target: t.fatG, color: Theme.fatYellow)
                    macroProgressRow("Fb", eaten: n.fiberG, target: t.fiberG, color: Theme.fiberBrown)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingGoalSetup = true }
            } else {
                // No goal - show simple pills, tap to set up goal
                HStack(spacing: 8) {
                    macroPill("P", value: n.proteinG, color: Theme.proteinRed)
                    macroPill("C", value: n.carbsG, color: Theme.carbsGreen)
                    macroPill("F", value: n.fatG, color: Theme.fatYellow)
                    macroPill("Fb", value: n.fiberG, color: Theme.fiberBrown)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingGoalSetup = true }
            }
            // Compact plant points row
            let pp = viewModel.weeklyPlantPoints
            if pp.total > 0 {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").font(.caption2).foregroundStyle(Theme.plantGreen)
                    Text("\(String(format: pp.total == Double(Int(pp.total)) ? "%.0f" : "%.1f", pp.total))/30")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(viewModel.isToday ? "plants this week" : "plants that week")
                        .font(.caption2).foregroundStyle(.secondary)
                    if viewModel.dailyNewPlants > 0 && viewModel.isToday {
                        Text("+\(viewModel.dailyNewPlants) new today")
                            .font(.caption2.weight(.medium)).foregroundStyle(Theme.plantGreen)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingPlantPointsDetail = true }
            }
        }
        .card()
    }

    private func macroProgressRow(_ label: String, eaten: Double, target: Double, color: Color) -> some View {
        let fraction = target > 0 ? min(eaten / target, 1.0) : 0  // cap at 100%
        let isOver = eaten > target
        return HStack(spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).frame(width: 14)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.08)).frame(height: 6)
                    if fraction > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(color)
                            .frame(width: max(0, geo.size.width * fraction), height: 6)
                    }
                }
            }.frame(height: 6)
            Text("\(Int(eaten))/\(Int(target))g")
                .font(.caption2.monospacedDigit()).foregroundStyle(isOver ? Theme.surplus : .secondary)
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

    // MARK: - Plant Points

    // MARK: - Combos

    /// Entries in `sortedEntries` grouped into 25-min time windows (past days only).
    private var timeGroups: [[FoodEntry]] {
        let iso = ISO8601DateFormatter()
        let window: TimeInterval = 25 * 60
        var groups: [[FoodEntry]] = []
        var current: [FoodEntry] = []
        var start: Date? = nil
        for entry in sortedEntries {
            let ts = iso.date(from: entry.loggedAt)
            if let ts, let s = start, ts.timeIntervalSince(s) <= window {
                current.append(entry)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [entry]; start = ts
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // Combo chip: accent-tinted with fork icon — opens confirm/edit sheet
    private func comboChip(name: String, calories: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: "fork.knife").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(name).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.accent)
            }
            Text("\(calories) cal").font(.system(size: 10)).foregroundStyle(Theme.accent.opacity(0.6))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // Recent chip: ghost outline — opens quick-add confirm sheet
    private func recentChip(name: String, calories: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption.weight(.medium)).lineLimit(1)
            Text("\(calories) cal").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    private var quickAddStrips: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.combos.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    Text("Combos").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.combos) { combo in
                                let totalCal = combo.recipeItems?.reduce(0) { $0 + $1.calories } ?? combo.calories
                                Button { comboToLog = combo } label: {
                                    comboChip(name: combo.name, calories: Int(totalCal))
                                }
                                .buttonStyle(.plain)
                            }
                            Button { showingCombos = true } label: {
                                Text("···").font(.subheadline).foregroundStyle(Theme.accent.opacity(0.6))
                                    .frame(width: 28, height: 28)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !viewModel.recentFoods.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    Text("Recent").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.recentFoods.prefix(8)) { food in
                                Button {
                                    confirmPrefill = AIChatViewModel.ManualFoodPrefill(
                                        name: food.name, calories: Int(food.calories),
                                        proteinG: food.proteinG, carbsG: food.carbsG,
                                        fatG: food.fatG, fiberG: food.fiberG)
                                    showingConfirmLog = true
                                } label: {
                                    recentChip(name: food.name, calories: Int(food.calories))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func groupedEntryBlock(_ entries: [FoodEntry]) -> some View {
        let totalCal = entries.reduce(0) { $0 + $1.totalCalories }
        return VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                entryRow(entry)
                if idx < entries.count - 1 { Divider().padding(.leading, 12) }
            }
            Button {
                viewModel.copyGroupToToday(entries)
                copiedToTodayName = "\(entries.count) items"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToTodayName = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc").font(.caption2)
                    Text("Copy group to today · \(Int(totalCal)) cal")
                        .font(.caption2.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }

    // MARK: - Food Diary

    private var foodDiary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Food Diary").font(.subheadline.weight(.semibold))
                // Meal grouping toggle + sort chips
                if viewModel.todayEntries.count > 1 {
                    HStack(spacing: 2) {
                        // 🍽 persists via AppStorage — always visible, defaults ON
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mealGrouped.toggle()
                                if !mealGrouped { foodSortMode = .time }
                            }
                        } label: {
                            Text(FoodSortMode.meal.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(mealGrouped ? .white : .secondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(mealGrouped ? Theme.accent.opacity(0.4) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        // Flat-sort options — only when meal grouping is OFF
                        if !mealGrouped {
                            ForEach(FoodSortMode.allCases.filter { $0 != .meal }, id: \.self) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { foodSortMode = mode }
                                } label: {
                                    Text(mode.label)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(foodSortMode == mode ? .white : .secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(foodSortMode == mode ? Theme.accent.opacity(0.4) : Color.clear, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Spacer()
                if !viewModel.todayEntries.isEmpty {
                    Text("\(viewModel.todayEntries.count) items")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 10)

            // Quick add (combos + recent) — today only, consistently styled horizontal chips
            if viewModel.isToday && (!viewModel.combos.isEmpty || !viewModel.recentFoods.isEmpty) {
                quickAddStrips
                Divider().padding(.vertical, 6)
            }

            if viewModel.todayEntries.isEmpty {
                emptyDiaryView
            } else {
                // Small add food — only when entries exist
                Button { showingSearch = true } label: {
                    HStack {
                        Image(systemName: "plus.circle").font(.subheadline).foregroundStyle(Theme.accent)
                        Text("Add food").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }.buttonStyle(.plain)

                Divider().padding(.vertical, 2)

                if mealGrouped {
                    ForEach(Array(mealGroups.enumerated()), id: \.element.mealType) { groupIdx, group in
                        mealSectionHeader(group.mealType, entries: group.entries)
                        ForEach(Array(group.entries.enumerated()), id: \.offset) { idx, entry in
                            entryRow(entry)
                            if idx < group.entries.count - 1 { Divider() }
                        }
                        if groupIdx < mealGroups.count - 1 { Divider().padding(.vertical, 4) }
                    }
                } else if viewModel.isToday {
                    ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                        entryRow(entry)
                        if index < sortedEntries.count - 1 { Divider() }
                    }
                } else {
                    // Past day: group time-adjacent entries into copyable combo blocks
                    ForEach(Array(timeGroups.enumerated()), id: \.offset) { gi, group in
                        if group.count >= 2 {
                            groupedEntryBlock(group)
                        } else if let entry = group.first {
                            entryRow(entry)
                        }
                        if gi < timeGroups.count - 1 { Divider() }
                    }
                }
            }
        }
        .card()
    }

    private func mealSectionHeader(_ meal: MealType, entries: [FoodEntry]) -> some View {
        let totalCal = entries.reduce(0) { $0 + $1.totalCalories }
        let times = entries.compactMap { parseTimestamp($0.loggedAt) }
        let timeRange: String? = {
            guard let earliest = times.min(), let latest = times.max() else { return nil }
            let fmt = DateFormatters.shortTime
            return earliest == latest ? fmt.string(from: earliest) : "\(fmt.string(from: earliest))–\(fmt.string(from: latest))"
        }()
        return HStack(spacing: 6) {
            Image(systemName: meal.icon).font(.caption2).foregroundStyle(Theme.accent)
            Text(meal.displayName).font(.caption.weight(.semibold))
            if let timeRange {
                Text("· \(timeRange)").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("\(Int(totalCal)) cal").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Button {
                searchMealType = meal
                showingSearch = true
            } label: {
                Image(systemName: "plus").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to \(meal.displayName)")
        }
        .padding(.vertical, 6)
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        let dayTotal = max(viewModel.todayNutrition.calories, 1)
        let fraction = min(entry.totalCalories / dayTotal, 1.0)
        let showMealBadge = !mealGrouped
        let mealType = MealType(rawValue: entry.mealType ?? "")

        return HStack(alignment: .center, spacing: 8) {
            // Calorie proportion bar
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent.opacity(0.3 + fraction * 0.7))
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.foodName).font(.subheadline).lineLimit(1)
                    if showMealBadge, let mealType {
                        Image(systemName: mealType.icon)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent.opacity(0.7))
                            .accessibilityLabel(mealType.displayName)
                    }
                }
                HStack(spacing: 4) {
                    if let time = entryTimeString(entry) {
                        HStack(spacing: 3) {
                            Text(time).foregroundStyle(.quaternary)
                            if isCopiedEntry(entry) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.accent.opacity(0.5))
                            }
                        }
                        .font(.caption2)
                        Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                    }
                    if !entry.portionText.isEmpty {
                        Text(entry.portionText).font(.caption2).foregroundStyle(.tertiary)
                        Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                    }
                    Text("\(Int(entry.totalProtein))P \(Int(entry.totalCarbs))C \(Int(entry.totalFat))F \(Int(entry.totalFiber))Fb")
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
                }
                .accessibilityLabel("Delete entry")
                .buttonStyle(.plain).padding(.leading, 4)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.foodName), \(Int(entry.totalCalories)) calories, \(Int(entry.totalProtein)) protein, \(Int(entry.totalCarbs)) carbs, \(Int(entry.totalFat)) fat, \(Int(entry.totalFiber)) fiber")
        .onTapGesture {
            editingEntry = entry
        }
        .contextMenu {
            Button {
                viewModel.toggleFavorite(name: entry.foodName, foodId: entry.foodId)
                viewModel.loadSuggestions()
            } label: {
                let isFav = viewModel.isFavorite(name: entry.foodName)
                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
            }
            Button {
                confirmPrefill = AIChatViewModel.ManualFoodPrefill(
                    name: entry.foodName, calories: Int(entry.totalCalories),
                    proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                    fatG: entry.totalFat, fiberG: entry.totalFiber)
                showingConfirmLog = true
            } label: {
                Label("Log Again", systemImage: "arrow.counterclockwise")
            }
            if !viewModel.isToday {
                Button {
                    copyToTodayEntry = entry
                } label: {
                    Label("Copy to Today", systemImage: "doc.on.doc")
                }
            }
            // Reorder (only in flat time-sorted view — grouped view uses section ordering)
            if foodSortMode == .time && !mealGrouped {
                if let entryIndex = sortedEntries.firstIndex(where: { $0.id == entry.id }) {
                    if entryIndex > 0 {
                        Button {
                            viewModel.swapEntries(entryIndex, entryIndex - 1, in: sortedEntries)
                            reload()
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                    }
                    if entryIndex < sortedEntries.count - 1 {
                        Button {
                            viewModel.swapEntries(entryIndex, entryIndex + 1, in: sortedEntries)
                            reload()
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                    }
                }
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
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent.opacity(0.18))
            Spacer().frame(height: 10)
            Text("Nothing logged yet")
                .font(.subheadline.weight(.medium)).foregroundStyle(.tertiary)
            Spacer().frame(height: 4)
            Text("Use a combo above or tap + to start")
                .font(.caption2).foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            HStack(spacing: 10) {
                Button { showingSearch = true } label: {
                    Label("Add food", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.1), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                if let cal = viewModel.yesterdayCalories(), cal > 0 {
                    Button { showingCopyYesterdayAlert = true } label: {
                        Label("Copy yesterday", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.secondary.opacity(0.08), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            #if DEBUG
            Button {
                try? AppDatabase.shared.seedTestData()
                reload()
            } label: {
                Text("Seed sample data").font(.caption2).foregroundStyle(.quaternary)
            }
            .padding(.top, 12)
            #endif
            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
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

    private func parseTimestamp(_ str: String) -> Date? {
        DateFormatters.iso8601.date(from: str)
            ?? DateFormatters.sqliteDatetime.date(from: str)
    }

    private func isCopiedEntry(_ entry: FoodEntry) -> Bool {
        guard let logged = parseTimestamp(entry.loggedAt),
              let created = parseTimestamp(entry.createdAt) else { return false }
        return abs(logged.timeIntervalSince(created)) > 300
    }

    private func entryTimeString(_ entry: FoodEntry) -> String? {
        guard let date = parseTimestamp(entry.loggedAt) else { return nil }
        return DateFormatters.shortTime.string(from: date)
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        let sorted = loggedDays.sorted { $0.key < $1.key }
        let daysLogged = sorted.filter { $0.value > 0 }.count

        // Calculate current streak (consecutive days from today)
        let cal = Calendar.current
        var streak = 0
        for dayOffset in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dayStart = cal.startOfDay(for: date)
            if (loggedDays[dayStart] ?? 0) > 0 { streak += 1 } else { break }
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logging Consistency").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if streak > 1 {
                    Text("\(streak) day streak").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
                }
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
