import SwiftUI
import Charts

struct FoodTabView: View {
    @State private var viewModel = FoodLogViewModel()
    @State private var showingSearch = false
    @State private var showingQuickAdd = false
    @State private var showingScanner = false
    @State private var loggedDays: [Date: Double] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Date navigator
                    dateNav

                    // Daily totals
                    dailyTotalsCard

                    // Meal sections
                    ForEach(MealType.allCases, id: \.self) { mealType in
                        mealSection(mealType)
                    }

                    // Logging consistency (last 30 days)
                    if !loggedDays.isEmpty {
                        consistencySection
                    }
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
                    Menu {
                        Button { showingScanner = true } label: { Label("Scan Barcode", systemImage: "barcode.viewfinder") }
                        Button { showingSearch = true } label: { Label("Search Food", systemImage: "magnifyingglass") }
                        Button { showingQuickAdd = true } label: { Label("Quick Add", systemImage: "plus.circle") }
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) { BarcodeLookupView(viewModel: viewModel) }
            .sheet(isPresented: $showingSearch) { FoodSearchView(viewModel: viewModel) }
            .sheet(isPresented: $showingQuickAdd) { QuickAddView(viewModel: viewModel) }
            .onAppear {
                viewModel.loadTodayMeals()
                loggedDays = viewModel.loggedDays(last: 30)
            }
            .onChange(of: showingSearch) { _, showing in
                if !showing { viewModel.loadTodayMeals(); loggedDays = viewModel.loggedDays(last: 30) }
            }
            .onChange(of: showingQuickAdd) { _, showing in
                if !showing { viewModel.loadTodayMeals(); loggedDays = viewModel.loggedDays(last: 30) }
            }
            .onChange(of: showingScanner) { _, showing in
                if !showing { viewModel.loadTodayMeals(); loggedDays = viewModel.loggedDays(last: 30) }
            }
        }
    }

    @State private var showingDatePicker = false

    // MARK: - Date Navigator

    private var dateNav: some View {
        HStack {
            Button { viewModel.goToPreviousDay(); loggedDays = viewModel.loggedDays(last: 30) } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.bold))
            }

            Spacer()

            // Tappable date → date picker
            Button { showingDatePicker = true } label: {
                VStack(spacing: 1) {
                    if viewModel.isToday {
                        Text("Today").font(.subheadline.weight(.semibold))
                    } else {
                        Text(DateFormatters.dayDisplay.string(from: viewModel.selectedDate))
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(DateFormatters.dateOnly.string(from: viewModel.selectedDate))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
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

            Spacer()

            if viewModel.isToday {
                Color.clear.frame(width: 30)
            } else {
                HStack(spacing: 8) {
                    Button { viewModel.goToNextDay() } label: {
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    Button { viewModel.goToDate(Date()); loggedDays = viewModel.loggedDays(last: 30) } label: {
                        Text("Today").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Daily Totals

    private var dailyTotalsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(Int(viewModel.todayNutrition.calories))")
                    .font(.title.weight(.bold).monospacedDigit())
                Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                macroPill("P", value: viewModel.todayNutrition.proteinG, color: Theme.proteinRed)
                macroPill("C", value: viewModel.todayNutrition.carbsG, color: Theme.carbsGreen)
                macroPill("F", value: viewModel.todayNutrition.fatG, color: Theme.fatYellow)
                macroPill("Fiber", value: viewModel.todayNutrition.fiberG, color: Theme.fiberBrown)
            }
        }
        .card()
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

    // MARK: - Meal Section

    private func mealSection(_ mealType: MealType) -> some View {
        let entries = viewModel.todayMeals[mealType] ?? []
        let totalCal = entries.reduce(0) { $0 + $1.totalCalories }

        return VStack(alignment: .leading, spacing: 8) {
            Button { showingSearch = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: mealType.icon).font(.caption).foregroundStyle(Theme.accent)
                    Text(mealType.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    if totalCal > 0 {
                        Text("\(Int(totalCal)) cal").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Image(systemName: "plus").font(.caption).foregroundStyle(Theme.accent)
                }
            }.buttonStyle(.plain)

            if entries.isEmpty {
                Button { showingSearch = true } label: {
                    Text("Tap to add food").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 4)
                }.buttonStyle(.plain)
            } else {
                ForEach(entries, id: \.id) { entry in
                    HStack {
                        Text(entry.foodName).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("\(Int(entry.totalCalories)) \u{2022} \(Int(entry.totalProtein))P \(Int(entry.totalCarbs))C \(Int(entry.totalFat))F")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        if let id = entry.id {
                            Button { viewModel.deleteEntry(id: id) } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.tertiary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .card()
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

            // Heatmap grid
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
                Text("Less").font(.system(size: 8)).foregroundStyle(.tertiary)
                ForEach([0.0, 500.0, 1000.0, 2000.0], id: \.self) { cal in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cal > 0 ? Theme.accent.opacity(min(1, cal / 2000)) : Theme.cardBackgroundElevated)
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}
