import WidgetKit
import SwiftUI

// MARK: - Entry

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let caloriesEaten: Int
    let calorieTarget: Int
    let caloriesRemaining: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let proteinTarget: Int
    let carbsTarget: Int
    let fatTarget: Int
    let dataDate: String  // "YYYY-MM-DD" of the data
    let isStale: Bool     // true if data is from a previous day

    var progress: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(Double(caloriesEaten) / Double(calorieTarget), 1.0)
    }

    static let placeholder = CaloriesEntry(
        date: Date(), caloriesEaten: 1200, calorieTarget: 2000,
        caloriesRemaining: 800, proteinG: 85, carbsG: 140, fatG: 45,
        proteinTarget: 140, carbsTarget: 200, fatTarget: 55,
        dataDate: "", isStale: false
    )
}

// MARK: - Provider

struct CaloriesProvider: TimelineProvider {
    private let suiteName = "group.com.drift.health"

    func placeholder(in context: Context) -> CaloriesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let entry = readEntry()
        // Refresh at midnight (new day) or in 15 minutes
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let fifteenMin = Date().addingTimeInterval(15 * 60)
        let nextRefresh = min(midnight, fifteenMin)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func readEntry() -> CaloriesEntry {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .placeholder
        }

        let eaten = defaults.integer(forKey: "widget_calories_eaten")
        let target = defaults.integer(forKey: "widget_calorie_target")
        let remaining = defaults.integer(forKey: "widget_calories_remaining")
        let proteinG = defaults.integer(forKey: "widget_protein_g")
        let carbsG = defaults.integer(forKey: "widget_carbs_g")
        let fatG = defaults.integer(forKey: "widget_fat_g")
        let proteinTarget = defaults.integer(forKey: "widget_protein_target")
        let carbsTarget = defaults.integer(forKey: "widget_carbs_target")
        let fatTarget = defaults.integer(forKey: "widget_fat_target")
        let dataDate = defaults.string(forKey: "widget_date") ?? ""

        // Check if data is from today
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())
        let isStale = !dataDate.isEmpty && dataDate != todayStr

        // If no target set, show a default
        let resolvedTarget = target > 0 ? target : 2000
        let resolvedRemaining = target > 0 ? remaining : resolvedTarget

        return CaloriesEntry(
            date: Date(),
            caloriesEaten: isStale ? 0 : eaten,
            calorieTarget: resolvedTarget,
            caloriesRemaining: isStale ? resolvedTarget : resolvedRemaining,
            proteinG: isStale ? 0 : proteinG,
            carbsG: isStale ? 0 : carbsG,
            fatG: isStale ? 0 : fatG,
            proteinTarget: proteinTarget > 0 ? proteinTarget : 140,
            carbsTarget: carbsTarget > 0 ? carbsTarget : 200,
            fatTarget: fatTarget > 0 ? fatTarget : 55,
            dataDate: dataDate,
            isStale: isStale
        )
    }
}

// MARK: - Colors (mirrors Theme.swift)

private enum WidgetColors {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.071)    // #0E0E12
    static let card = Color(red: 0.102, green: 0.106, blue: 0.141)          // #1A1B24
    static let accent = Color(red: 0.545, green: 0.486, blue: 0.965)        // #8B7CF6
    static let deficit = Color(red: 0.204, green: 0.827, blue: 0.600)       // #34D399
    static let surplus = Color(red: 0.937, green: 0.267, blue: 0.267)       // #EF4444
    static let proteinRed = Color(red: 0.937, green: 0.267, blue: 0.267)    // #EF4444
    static let carbsGreen = Color(red: 0.133, green: 0.773, blue: 0.369)    // #22C55E
    static let fatYellow = Color(red: 0.918, green: 0.702, blue: 0.031)     // #EAB308
    static let textSecondary = Color.white.opacity(0.6)
}

// MARK: - Small Widget

struct SmallCaloriesView: View {
    let entry: CaloriesEntry

    var body: some View {
        VStack(spacing: 6) {
            // Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        entry.caloriesRemaining >= 0 ? WidgetColors.deficit : WidgetColors.surplus,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(max(0, entry.caloriesRemaining))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetColors.textSecondary)
                }
            }
            .frame(width: 80, height: 80)

            // Label
            Text("\(entry.caloriesEaten) / \(entry.calorieTarget) cal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetColors.textSecondary)

            if entry.isStale {
                Text("Open app to refresh")
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetColors.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetColors.background, for: .widget)
    }
}

// MARK: - Medium Widget

struct MediumCaloriesView: View {
    let entry: CaloriesEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: Calorie ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        entry.caloriesRemaining >= 0 ? WidgetColors.deficit : WidgetColors.surplus,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(max(0, entry.caloriesRemaining))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("cal left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetColors.textSecondary)
                }
            }
            .frame(width: 90, height: 90)

            // Right: Macro breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("\(entry.caloriesEaten) / \(entry.calorieTarget) cal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                MacroBar(label: "P", value: entry.proteinG, target: entry.proteinTarget, color: WidgetColors.proteinRed)
                MacroBar(label: "C", value: entry.carbsG, target: entry.carbsTarget, color: WidgetColors.carbsGreen)
                MacroBar(label: "F", value: entry.fatG, target: entry.fatTarget, color: WidgetColors.fatYellow)

                if entry.isStale {
                    Text("Open app to refresh")
                        .font(.system(size: 9))
                        .foregroundStyle(WidgetColors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetColors.background, for: .widget)
    }
}

struct MacroBar: View {
    let label: String
    let value: Int
    let target: Int
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(value) / Double(target), 1.0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)

            Text("\(value)g")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetColors.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - Lock Screen (Accessory)

struct AccessoryCaloriesView: View {
    let entry: CaloriesEntry

    var body: some View {
        Gauge(value: entry.progress) {
            Text("Cal")
        } currentValueLabel: {
            Text("\(max(0, entry.caloriesRemaining))")
                .font(.system(size: 12, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Widget Configuration

struct CaloriesWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CaloriesEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumCaloriesView(entry: entry)
        case .accessoryCircular:
            AccessoryCaloriesView(entry: entry)
        default:
            SmallCaloriesView(entry: entry)
        }
    }
}

struct CaloriesRemainingWidget: Widget {
    let kind = "CaloriesRemaining"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesProvider()) { entry in
            CaloriesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Calories Remaining")
        .description("Track your daily calorie and macro progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: - Widget Bundle (Entry Point)

@main
struct DriftWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesRemainingWidget()
    }
}
