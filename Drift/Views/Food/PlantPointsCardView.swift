import SwiftUI

struct PlantPointsCardView: View {
    @Bindable var viewModel: FoodLogViewModel
    @State private var plantPeriod: PlantPeriod = .week
    @State private var periodPlantPoints: PlantPointsService.PlantPoints?
    @State private var showingPlantList = false

    enum PlantPeriod: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
    }

    /// "Today" when viewing today, otherwise "Apr 5" etc.
    private var dayLabel: String {
        Calendar.current.isDateInToday(viewModel.selectedDate)
            ? "Today"
            : DateFormatters.shortDisplay.string(from: viewModel.selectedDate)
    }

    var body: some View {
        let pp = plantPointsForPeriod
        let weeklyGoal: Double = 30
        let isWeekly = plantPeriod == .week
        let progress = isWeekly ? min(pp.total / weeklyGoal, 1.0) : 0

        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill").font(.subheadline).foregroundStyle(Theme.plantGreen)
                    Text("Plant Points").font(.subheadline.weight(.semibold))
                }
                Spacer()
                // Period picker
                HStack(spacing: 0) {
                    ForEach(PlantPeriod.allCases, id: \.self) { period in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { plantPeriod = period }
                            loadPlantPointsForPeriod()
                        } label: {
                            Text(period == .day ? dayLabel : period.rawValue)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(plantPeriod == period ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    plantPeriod == period ? Theme.plantGreen.opacity(0.3) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Score
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(pp.total == Double(Int(pp.total)) ? "\(Int(pp.total))" : String(format: "%.1f", pp.total))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.plantGreen)
                if isWeekly {
                    Text("/ 30").font(.subheadline.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Text(pp.plantCount == 1 ? "plant" : "plants")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if plantPeriod == .day && viewModel.dailyNewPlants > 0 {
                    Text("+\(viewModel.dailyNewPlants) new this week")
                        .font(.caption2.weight(.medium)).foregroundStyle(Theme.plantGreen)
                }
            }

            // Weekly progress bar
            if isWeekly {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.plantGreen.opacity(0.1)).frame(height: 6)
                        if progress > 0 {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.plantGreen)
                                .frame(width: max(0, geo.size.width * progress), height: 6)
                        }
                    }
                }.frame(height: 6)
            }

            // Breakdown chips
            HStack(spacing: 8) {
                if !pp.uniquePlants.isEmpty {
                    plantChip(
                        icon: "circle.fill",
                        label: "\(pp.uniquePlants.count) plants",
                        detail: "+\(Int(pp.fullPoints))pt",
                        color: Theme.plantGreen
                    )
                }
                if !pp.uniqueHerbsSpices.isEmpty {
                    plantChip(
                        icon: "sparkle",
                        label: "\(pp.uniqueHerbsSpices.count) herbs/spices",
                        detail: "+\(String(format: "%.1f", pp.quarterPoints))pt",
                        color: Theme.fatYellow
                    )
                }
                if pp.plantCount == 0 {
                    Text("No plant foods logged yet")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            // Tappable plant list
            if pp.plantCount > 0 {
                Button { showingPlantList.toggle() } label: {
                    HStack(spacing: 4) {
                        Text(showingPlantList ? "Hide plants" : "Show plants")
                            .font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: showingPlantList ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if showingPlantList {
                    plantListView(pp)
                }
            }
        }
        .card()
        .onAppear { loadPlantPointsForPeriod() }
    }

    private var plantPointsForPeriod: PlantPointsService.PlantPoints {
        if let cached = periodPlantPoints { return cached }
        return viewModel.weeklyPlantPoints
    }

    private func loadPlantPointsForPeriod() {
        let cal = Calendar.current
        let date = viewModel.selectedDate
        let startStr: String
        let endStr: String

        switch plantPeriod {
        case .day:
            let ds = DateFormatters.dateOnly.string(from: date)
            startStr = ds
            endStr = ds
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return }
            startStr = DateFormatters.dateOnly.string(from: interval.start)
            let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            endStr = DateFormatters.dateOnly.string(from: end)
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: date) else { return }
            startStr = DateFormatters.dateOnly.string(from: interval.start)
            let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            endStr = DateFormatters.dateOnly.string(from: end)
        }

        let items = FoodService.fetchFoodItemsForPlantPoints(from: startStr, to: endStr)
        guard !items.isEmpty else { return }
        periodPlantPoints = PlantPointsService.calculate(from: items)
    }

    private func plantChip(icon: String, label: String, detail: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 5)).foregroundStyle(color)
            Text(label).font(.caption2.weight(.medium))
            Text(detail).font(.caption2).foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func plantListView(_ pp: PlantPointsService.PlantPoints) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !pp.uniquePlants.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(pp.uniquePlants, id: \.self) { name in
                        Text(name.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.plantGreen.opacity(0.15), in: Capsule())
                    }
                }
            }
            if !pp.uniqueHerbsSpices.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(pp.uniqueHerbsSpices, id: \.self) { name in
                        Text(name.capitalized)
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.fatYellow.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }
}
