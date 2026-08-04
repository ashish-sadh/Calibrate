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
    /// Header "+" — opens the Log-a-meal sheet. Field feedback 2026-07-13:
    /// "it's hard to edit food diary down here… add can be just simple plus".
    var onAdd: (() -> Void)?
    /// Row swipe-to-delete. Same feedback: "Delete can be simple swipe."
    /// Only rows with a persisted entry id get the swipe affordance.
    var onDelete: ((Int64) -> Void)?
    @State private var expandedRowID: String?

    private static let emptyStateText = "Log your first meal — try the Snap card above"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            let rows = MealTimelineSection.rows(from: entries)
            if rows.isEmpty {
                emptyState
            } else {
                // 2026-05-24 density pass — user feedback: "too spaced
                // out on Today." Was: one RoundedRectangle card *per*
                // row + a decorative timeline gutter (14px-wide rail
                // with dots and connectors), ~70px per row. Now: a
                // single bounded card containing all rows, with a
                // hairline divider between them — ~36px per row,
                // roughly half the footprint at 7 entries. The gutter
                // was visual noise that didn't earn its space; tap
                // target stays the row body.
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        deletableRow(row: row)
                        if idx < rows.count - 1 {
                            Divider()
                                .overlay(Theme.separator.opacity(0.6))
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                )
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text("Today's meals")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer(minLength: 0)
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        // Small glyph, honest tap target.
                        .frame(width: 32, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a meal")
                .accessibilityIdentifier("meal-timeline-add")
            }
        }
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
                .font(.system(size: Theme.FontSize.footnote))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.emptyStateText)
        .accessibilityIdentifier("meal-timeline-empty")
    }

    /// Wraps `compactRow` in the drag-to-reveal delete affordance when the
    /// row is DB-persisted and the section has a delete handler. The rows
    /// live in a plain VStack inside the Dashboard ScrollView — `.swipeActions`
    /// is List-only, hence the custom reveal.
    @ViewBuilder
    private func deletableRow(row: MealTimelineRow) -> some View {
        if let entryId = row.entryId, let onDelete {
            SwipeToDeleteContainer(
                accessibilityDeleteLabel: "Delete \(row.foodName)",
                onDelete: { onDelete(entryId) }
            ) {
                compactRow(row: row)
            }
        } else {
            compactRow(row: row)
        }
    }

    @ViewBuilder
    private func compactRow(row: MealTimelineRow) -> some View {
        let isExpanded = expandedRowID == row.id
        // The expanded detail is a SIBLING of the toggle button, not inside its
        // label. A button nested in another button's label has its taps
        // swallowed by the outer one, so Remove would look live and do nothing.
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedRowID = isExpanded ? nil : row.id
                }
            } label: {
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
                        .font(.system(size: Theme.FontSize.tiny))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .pressable()
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint(isExpanded ? "Hide details" : "Show details")
            .accessibilityIdentifier("meal-timeline-row-\(row.id)")

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
                    // Remove, in the open row itself (operator 2026-08-03:
                    // "when I expand add a way to remove from dashboard
                    // itself"). Deleting an entry was swipe-only — a gesture
                    // you have to already know is there, and the same class of
                    // hidden affordance behind the "misclicking is a lot"
                    // feedback. The swipe still works; this just stops being
                    // the only way.
                    if let entryId = row.entryId, let onDelete {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedRowID = nil
                            }
                            onDelete(entryId)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Remove")
                                    // Never wrap. With five macro chips beside
                                    // it the row runs out of width, and SwiftUI
                                    // compressed THIS button rather than the
                                    // chips — the label broke mid-word into
                                    // "Remov / e" and the button grew to two
                                    // lines, taller than everything next to it
                                    // (operator 2026-08-04: "Remove button looks
                                    // weird").
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .font(.system(size: Theme.FontSize.tiny, weight: .semibold))
                            .foregroundStyle(Theme.surplus)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.surplus.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        // Wins the width contest against the chips, which is
                        // the correct priority: a chip that truncates is still
                        // readable, a button that wraps is broken.
                        .layoutPriority(1)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(row.foodName)")
                        .accessibilityIdentifier("meal-timeline-remove-\(row.id)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Density pass: was .padding(.horizontal 14, .vertical 12)
        // — dropped to (14, 8) which is the comfortable lower bound
        // for tap-target while halving the per-row footprint.
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // `lineLimit(1)` on both chip kinds: they share the expanded row with the
    // Remove button, and a squeezed chip must truncate on one line rather than
    // wrap and drag the whole row taller.
    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: Theme.FontSize.tiny, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
    }

    private func macroChip(_ label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 9)
            Text("\(Int(grams.rounded()))g \(label)")
                .font(.system(size: Theme.FontSize.tiny, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Drag-to-reveal delete for card rows that live outside a `List`
/// (`.swipeActions` is List-only). Swipe left to reveal a trash button;
/// tap it to delete, tap the row or swipe right to close. The drag only
/// claims clearly-horizontal translations so it doesn't fight the
/// Dashboard ScrollView's vertical scroll.
private struct SwipeToDeleteContainer<Content: View>: View {
    let accessibilityDeleteLabel: String
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isRevealed = false

    private let revealWidth: CGFloat = 68

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                close()
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.surplus)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDeleteLabel)

            content()
                .background(Theme.cardBackground)
                .offset(x: offsetX)
                // Tap-catcher while revealed: a stray tap closes the reveal
                // instead of expanding the row underneath.
                .overlay {
                    if isRevealed {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base: CGFloat = isRevealed ? -revealWidth : 0
                            // Rubber-band a little past the reveal, never right of rest.
                            offsetX = min(0, max(-revealWidth - 20, base + value.translation.width))
                        }
                        .onEnded { value in
                            let opening = !isRevealed && value.translation.width < -revealWidth * 0.5
                            let staysOpen = isRevealed && value.translation.width < 20
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                isRevealed = opening || staysOpen
                                offsetX = isRevealed ? -revealWidth : 0
                            }
                        }
                )
        }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isRevealed = false
            offsetX = 0
        }
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
    // Hoisted to static — `rows(from:)` is called on every dashboard render and
    // was allocating three date formatters each time (formatter init is
    // surprisingly heavy). (#951)
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Build the row list from today's `[FoodEntry]`. Sorted by `loggedAt`
    /// ascending so the earliest meal sits at the top of the rail.
    /// Unparseable timestamps fall to the end of the list rather than crash —
    /// the dashboard never wants to render a partial row.
    static func rows(from entries: [FoodEntry]) -> [MealTimelineRow] {
        let iso = Self.isoFrac
        let isoNoFrac = Self.isoNoFrac
        let timeFmt = Self.timeFmt

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
