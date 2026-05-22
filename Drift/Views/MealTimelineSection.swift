import SwiftUI
import DriftCore

/// V7 Phase-2 vertical meal timeline. One row per `FoodEntry` logged today,
/// rendered as a dot-rail (filled circle on a hairline gutter) with the meal
/// time, name, and total kcal. Tapping a row toggles an expanded detail line
/// — per-serving macros + portion text — so the user can sanity-check a log
/// without leaving the Today tab.
///
/// Empty state surfaces the active CTA referencing the log-methods row above:
/// `"Log your first meal — try the Snap card above"`. The empty-state copy is
/// pinned by Done-When criterion 2 of #821; do not rephrase without updating
/// the spec.
struct MealTimelineSection: View {
    let entries: [FoodEntry]
    @State private var expandedRowID: String?

    private static let emptyStateText = "Log your first meal — try the Snap card above"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            let rows = MealTimelineSection.rows(from: entries)
            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        timelineRow(
                            row: row,
                            isFirst: idx == 0,
                            isLast: idx == rows.count - 1
                        )
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var sectionHeader: some View {
        Text("Today's meals")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "fork.knife.circle")
                .font(.title3)
                .foregroundStyle(Theme.textTertiary)
            Text(Self.emptyStateText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.emptyStateText)
        .accessibilityIdentifier("meal-timeline-empty")
    }

    @ViewBuilder
    private func timelineRow(row: MealTimelineRow, isFirst: Bool, isLast: Bool) -> some View {
        let isExpanded = expandedRowID == row.id
        HStack(alignment: .top, spacing: 12) {
            timelineGutter(isFirst: isFirst, isLast: isLast)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedRowID = isExpanded ? nil : row.id
                }
            } label: {
                rowBody(row: row, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint(isExpanded ? "Hide details" : "Show details")
            .accessibilityIdentifier("meal-timeline-row-\(row.id)")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func timelineGutter(isFirst: Bool, isLast: Bool) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.separator)
                    .frame(width: 1, height: 18)
                Rectangle()
                    .fill(isLast ? Color.clear : Theme.separator)
                    .frame(width: 1, height: 50)
            }
            Circle()
                .fill(Theme.textPrimary)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .fill(Theme.background)
                        .frame(width: 4, height: 4)
                )
                .padding(.top, 14)
        }
        .frame(width: 14)
    }

    @ViewBuilder
    private func rowBody(row: MealTimelineRow, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.timeText)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 56, alignment: .leading)
                Text(row.foodName)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(isExpanded ? 2 : 1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(row.kcal)")
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("kcal")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            if isExpanded {
                HStack(spacing: 6) {
                    if !row.portionText.isEmpty {
                        chip(row.portionText, color: Theme.textSecondary)
                    }
                    macroChip("P", grams: row.proteinG, color: Theme.proteinRed)
                    macroChip("C", grams: row.carbsG, color: Theme.macroCarbs)
                    macroChip("F", grams: row.fatG, color: Theme.macroFat)
                    if row.fiberG > 0.5 {
                        macroChip("Fiber", grams: row.fiberG, color: Theme.macroFiber)
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
    }

    private func macroChip(_ label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 9)
            Text("\(Int(grams.rounded()))g \(label)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// One row of the meal timeline. Pure value type — built by the
/// `MealTimelineSection.rows(from:)` factory so tests can pin the formatter
/// without instantiating a SwiftUI view, same discipline as the legacy V6
/// payload structs.
struct MealTimelineRow: Equatable, Identifiable {
    let entryId: Int64?
    let timeText: String
    let foodName: String
    let kcal: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let portionText: String

    /// Identity uses the entry id when present (DB-persisted) and falls back
    /// to `foodName + loggedAt` for in-flight entries so SwiftUI's ForEach
    /// keeps stable identity across the 3-min Dashboard refresh tick.
    var id: String {
        if let entryId { return "e\(entryId)" }
        return "\(foodName)-\(timeText)"
    }

    var accessibilityLabel: String {
        "\(foodName) at \(timeText), \(kcal) calories"
    }
}

extension MealTimelineSection {
    /// Build the row list from today's `[FoodEntry]`. Sorted by `loggedAt`
    /// ascending so the earliest meal sits at the top of the rail.
    /// Unparseable timestamps fall to the end of the list rather than crash —
    /// the dashboard never wants to render a partial row.
    static func rows(from entries: [FoodEntry]) -> [MealTimelineRow] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        let sorted = entries.sorted { a, b in
            let da = iso.date(from: a.loggedAt) ?? isoNoFrac.date(from: a.loggedAt) ?? .distantFuture
            let db = iso.date(from: b.loggedAt) ?? isoNoFrac.date(from: b.loggedAt) ?? .distantFuture
            return da < db
        }
        return sorted.map { entry in
            let dt = iso.date(from: entry.loggedAt) ?? isoNoFrac.date(from: entry.loggedAt)
            let timeText = dt.map { timeFmt.string(from: $0) } ?? "—"
            return MealTimelineRow(
                entryId: entry.id,
                timeText: timeText,
                foodName: entry.foodName,
                kcal: Int(entry.totalCalories.rounded()),
                proteinG: entry.totalProtein,
                carbsG: entry.totalCarbs,
                fatG: entry.totalFat,
                fiberG: entry.totalFiber,
                portionText: entry.portionText
            )
        }
    }
}

#if DEBUG
#Preview("MealTimelineSection — populated") {
    let now = Date()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let breakfast = FoodEntry(
        id: 1,
        foodName: "scrambled eggs",
        servingSizeG: 100, servings: 2, calories: 155,
        proteinG: 13, carbsG: 1, fatG: 11, fiberG: 0,
        loggedAt: iso.string(from: now.addingTimeInterval(-7200)),
        mealType: "breakfast"
    )
    let lunch = FoodEntry(
        id: 2,
        foodName: "chicken biryani",
        servingSizeG: 300, servings: 1, calories: 420,
        proteinG: 28, carbsG: 50, fatG: 12, fiberG: 3,
        loggedAt: iso.string(from: now),
        mealType: "lunch"
    )
    return MealTimelineSection(entries: [breakfast, lunch])
        .padding()
        .background(Theme.background)
}

#Preview("MealTimelineSection — empty") {
    MealTimelineSection(entries: [])
        .padding()
        .background(Theme.background)
}
#endif
