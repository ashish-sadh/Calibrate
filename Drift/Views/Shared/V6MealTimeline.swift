import SwiftUI
import DriftCore

/// V6 Dashboard meals timeline — fixed 4-slot Breakfast / Lunch / Dinner /
/// Snacks list rendered as a vertical dot+line per
/// `Docs/design-references/v6-2026-05-14/v6/v6-today.jsx` (anatomy step 4).
///
/// Replaces the legacy "No food logged today" muted state inside
/// `calorieBalanceCard`. The 4 slots are always present so first-time users
/// see four explicit log entry points (one per meal), and every slot is a
/// stable, single-tap surface — filled slots open the Food tab to edit the
/// meal, empty slots route to the same tab to log into that slot. Tap
/// behavior is wired by the call site (`onSelect`) so this view stays
/// rendering-only.
struct V6MealTimeline: View {
    let slots: [V6MealSlotPayload]
    let onSelect: (V6MealSlotPayload) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                HStack(alignment: .top, spacing: 12) {
                    timelineGutter(isFilled: slot.isLogged,
                                   isFirst: idx == 0,
                                   isLast: idx == slots.count - 1)
                    Button { onSelect(slot) } label: {
                        slotBody(slot)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(slot.accessibilityLabel)
                    .accessibilityHint(slot.isLogged ? "Edit \(slot.name) in Food tab" : "Log a \(slot.name)")
                }
                .padding(.vertical, 4)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private func timelineGutter(isFilled: Bool, isFirst: Bool, isLast: Bool) -> some View {
        ZStack(alignment: .top) {
            // Vertical line — half-height on first/last so the dot doesn't sit
            // on a line that runs into thin air. The line lives in the gutter,
            // not behind the dot, so it never bleeds through the dot's center.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.separator)
                    .frame(width: 1, height: 22)
                Rectangle()
                    .fill(isLast ? Color.clear : Theme.separator)
                    .frame(width: 1, height: 50)
            }
            // Dot — filled = solid ink with a bg-color pip; empty = dashed
            // ring on bg so the row reads as "not yet logged".
            Circle()
                .fill(isFilled ? Theme.textPrimary : Theme.background)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .strokeBorder(isFilled ? Color.clear : Theme.separator,
                                      style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                )
                .overlay(
                    Circle()
                        .fill(Theme.background)
                        .frame(width: 5, height: 5)
                        .opacity(isFilled ? 1 : 0)
                )
                .padding(.top, 16)
        }
        .frame(width: 16)
    }

    @ViewBuilder
    private func slotBody(_ slot: V6MealSlotPayload) -> some View {
        if slot.isLogged {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(slot.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(slot.timeText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                    Text("\(slot.calories)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(slot.itemSummary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        } else {
            HStack(spacing: 10) {
                Text(slot.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(slot.timeText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                Text("Log")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

/// Pre-formatted payload for one slot. Pure value type — the
/// `V6MealTimeline.payloads(from:now:)` factory is static so tests can pin it
/// without instantiating a SwiftUI view, same discipline as `V6BodyTilePayload`.
struct V6MealSlotPayload: Equatable, Identifiable {
    let mealType: MealType
    let isLogged: Bool
    let calories: Int
    let itemSummary: String
    let timeText: String

    var id: String { mealType.rawValue }
    var name: String { mealType.displayName }

    var accessibilityLabel: String {
        if isLogged {
            return "\(name), \(calories) calories, \(itemSummary)"
        }
        return "\(name), not logged, around \(timeText)"
    }
}

extension V6MealTimeline {
    /// Default reference times shown in the empty-slot "~7:00 AM" affordance.
    /// Matches the JSX `ts` map (Breakfast 7:00 AM, Lunch 12:30 PM, Dinner
    /// 7:00 PM, Snacks Anytime). Returned as 24-hour `Date` components keyed
    /// by mealType so the formatter respects the user's locale time format.
    private static let defaultMealTimes: [MealType: (hour: Int, minute: Int)?] = [
        .breakfast: (7, 0),
        .lunch: (12, 30),
        .dinner: (19, 0),
        .snack: nil
    ]

    private static let fixedOrder: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    /// Build the 4-slot payload row from today's `[FoodEntry]`.
    ///
    /// Always returns exactly 4 slots in fixed order (Breakfast → Lunch →
    /// Dinner → Snacks) so the timeline shape is layout-stable across
    /// reloads. Entries with a missing or unparseable `mealType` fall back
    /// to `.snack` — the same fallback `MealType.resolve(...)` uses when
    /// nothing else is known.
    ///
    /// `now` is injected so tests can pin "Anytime" vs the empty-slot
    /// reference-time formatting deterministically; the production call
    /// site uses `Date()`.
    static func payloads(from entries: [FoodEntry], now: Date = Date()) -> [V6MealSlotPayload] {
        let grouped = Dictionary(grouping: entries) { entry -> MealType in
            if let raw = entry.mealType, let type = MealType(rawValue: raw.lowercased()) {
                return type
            }
            return .snack
        }
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        return fixedOrder.map { meal -> V6MealSlotPayload in
            let bucket = grouped[meal] ?? []
            if bucket.isEmpty {
                let defaultTime: String = {
                    guard let tuple = defaultMealTimes[meal] ?? nil else { return "Anytime" }
                    var comp = cal.dateComponents([.year, .month, .day], from: now)
                    comp.hour = tuple.hour
                    comp.minute = tuple.minute
                    let date = cal.date(from: comp) ?? now
                    return "~" + timeFmt.string(from: date)
                }()
                return V6MealSlotPayload(
                    mealType: meal,
                    isLogged: false,
                    calories: 0,
                    itemSummary: "",
                    timeText: defaultTime
                )
            }
            let totalKcal = bucket.reduce(0.0) { $0 + $1.totalCalories }
            let summary = Self.itemSummary(from: bucket)
            let firstTime: String = {
                let dates = bucket.compactMap { entry -> Date? in
                    iso.date(from: entry.loggedAt) ?? isoNoFrac.date(from: entry.loggedAt)
                }
                guard let earliest = dates.min() else { return "" }
                return timeFmt.string(from: earliest)
            }()
            return V6MealSlotPayload(
                mealType: meal,
                isLogged: true,
                calories: Int(totalKcal.rounded()),
                itemSummary: summary,
                timeText: firstTime
            )
        }
    }

    /// "eggs · paneer · toast · +2" — first 3 entry names by `loggedAt` asc,
    /// each truncated to the first 3 words to keep the row a single line.
    /// Matches the JSX `m.items.slice(0,3)...slice(0,3)` shape and adds the
    /// `+N` tail when more entries exist.
    private static func itemSummary(from entries: [FoodEntry]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        let sorted = entries.sorted { a, b in
            let da = iso.date(from: a.loggedAt) ?? isoNoFrac.date(from: a.loggedAt) ?? .distantPast
            let db = iso.date(from: b.loggedAt) ?? isoNoFrac.date(from: b.loggedAt) ?? .distantPast
            return da < db
        }
        let firstThree = sorted.prefix(3).map { entry -> String in
            entry.foodName
                .split(separator: " ")
                .prefix(3)
                .joined(separator: " ")
        }
        let tail = sorted.count > 3 ? " · +\(sorted.count - 3)" : ""
        return firstThree.joined(separator: " · ") + tail
    }
}

#if DEBUG
#Preview("V6MealTimeline filled + empty") {
    let breakfast = FoodEntry(
        foodName: "scrambled eggs",
        servingSizeG: 100, servings: 2, calories: 155,
        proteinG: 13, carbsG: 1, fatG: 11, fiberG: 0,
        loggedAt: ISO8601DateFormatter().string(from: Date()),
        date: nil, mealType: "breakfast"
    )
    let lunch = FoodEntry(
        foodName: "chicken biryani",
        servingSizeG: 300, servings: 1, calories: 420,
        proteinG: 28, carbsG: 50, fatG: 12, fiberG: 3,
        loggedAt: ISO8601DateFormatter().string(from: Date()),
        date: nil, mealType: "lunch"
    )
    let slots = V6MealTimeline.payloads(from: [breakfast, lunch])
    return V6MealTimeline(slots: slots) { _ in }
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("V6MealTimeline all empty") {
    V6MealTimeline(slots: V6MealTimeline.payloads(from: [])) { _ in }
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
#endif
