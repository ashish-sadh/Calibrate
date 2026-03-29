import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class WeightViewModel {
    private let database: AppDatabase

    var entries: [WeightEntry] = []
    var trend: WeightTrendCalculator.WeightTrend?
    var selectedTimeRange: TimeRange = .threeMonths
    var weightUnit: WeightUnit = Preferences.weightUnit

    enum TimeRange: String, CaseIterable, Sendable {
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case all = "All"

        var days: Int? {
            switch self {
            case .oneWeek: 7
            case .oneMonth: 30
            case .threeMonths: 90
            case .sixMonths: 180
            case .oneYear: 365
            case .all: nil
            }
        }
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadEntries() {
        do {
            let startDate: String?
            if let days = selectedTimeRange.days {
                let date = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
                startDate = DateFormatters.dateOnly.string(from: date)
            } else {
                startDate = nil
            }

            entries = try database.fetchWeightEntries(from: startDate)
            calculateTrend()
        } catch {
            print("Failed to load weight entries: \(error)")
        }
    }

    func addWeight(value: Double, date: Date = Date()) {
        let kg = weightUnit.convertToKg(value)
        var entry = WeightEntry(
            date: DateFormatters.dateOnly.string(from: date),
            weightKg: kg,
            source: "manual"
        )
        do {
            try database.saveWeightEntry(&entry)
            loadEntries()
        } catch {
            print("Failed to save weight: \(error)")
        }
    }

    func deleteWeight(id: Int64) {
        do {
            try database.deleteWeightEntry(id: id)
            loadEntries()
        } catch {
            print("Failed to delete weight: \(error)")
        }
    }

    func displayWeight(_ kg: Double) -> Double {
        weightUnit.convert(fromKg: kg)
    }

    func formattedWeight(_ kg: Double) -> String {
        let value = displayWeight(kg)
        return String(format: "%.1f", value)
    }

    private func calculateTrend() {
        let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
        trend = WeightTrendCalculator.calculateTrend(entries: input)
    }
}
