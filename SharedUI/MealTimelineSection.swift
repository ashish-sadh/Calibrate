import SwiftUI
import DriftCore

/// V7 Phase-2 vertical meal timeline. One row per `FoodEntry` logged today —
/// meal time, name, and total kcal — inside a single bounded card with
/// hairline dividers. (The doc used to describe a dot-rail gutter; that was
/// deleted in the 2026-05-24 density pass, see the comment in `body`.)
/// Tapping a row toggles an expanded detail line — per-serving macros +
/// portion text — so the user can sanity-check a log without leaving Today.
///
/// Shared verbatim by iOS `DashboardView` and Android `TodayTab`; the only
/// Android deltas are the drawn empty-state glyph and the omitted swipe
/// container, both gated below.
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
    /// Deletes one entry. Reached two ways on iOS — the Remove button in the
    /// expanded row, and swipe-to-reveal ("Delete can be simple swipe") — and
    /// by the Remove button alone on Android. Only rows with a persisted entry
    /// id get either affordance.
    var onDelete: ((Int64) -> Void)?
    // Not `private`: Skip Fuse can't bridge a private @State, and the compile
    // error it produces points at line 1 rather than at this line.
    @State var expandedRowID: String?

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
        // The range form of dynamicTypeSize has no SharedUI precedent under
        // Skip; iOS keeps its cap, Android inherits the system scale.
        #if !os(Android)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        #endif
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
            // `fork.knife` is deliberately unmapped in Symbols.swift — routing
            // it through skip-ui would render a warning triangle. Same drawn
            // shape FoodTabView uses (FoodTabView.swift:708).
            #if os(Android)
            ForkKnifeShape()
                .fill(Theme.textTertiary)
                .frame(width: 20, height: 20)
            #else
            Image(systemName: "fork.knife.circle")
                .font(.title3)
                .foregroundStyle(Theme.textTertiary)
            #endif
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
        // skip-ui ships accessibilityElement as @available(*, unavailable) —
        // Android reads the two children separately instead of as one element.
        #if !os(Android)
        .accessibilityElement(children: .combine)
        #endif
        // Text(_:) rather than the bare String: SkipUI only bridges the
        // LocalizedStringKey overload, so a String *variable* (or a ternary of
        // literals, which types as String) fails to compile for Android.
        // Same overload on iOS, so nothing changes there.
        .accessibilityLabel(Text(Self.emptyStateText))
        .accessibilityIdentifier("meal-timeline-empty")
    }

    /// Wraps `compactRow` in the drag-to-reveal delete affordance when the
    /// row is DB-persisted and the section has a delete handler. The rows
    /// live in a plain VStack inside the Dashboard ScrollView — `.swipeActions`
    /// is List-only, hence the custom reveal.
    ///
    /// Android gets the row bare: deletion there runs through the visible
    /// Remove button in the expanded row (which is the affordance the operator
    /// actually asked for), and a hand-rolled `DragGesture` fighting Compose's
    /// vertical scroll is a runtime question no amount of source-reading
    /// settles. Shipping it unverified would risk breaking the scroll of the
    /// whole Today tab to add a second path to a function that already works.
    @ViewBuilder
    private func deletableRow(row: MealTimelineRow) -> some View {
        #if os(Android)
        compactRow(row: row)
        #else
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
        #endif
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
                        // Unavailable in skip-ui; Compose already ellipsises
                        // at the tail when lineLimit clips, so this is a
                        // no-op difference rather than a visual one.
                        #if !os(Android)
                        .truncationMode(.tail)
                        #endif
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
            .accessibilityLabel(Text(row.accessibilityLabel))
            // On a ModifiedContent chain the hint overload skip-ui exposes is
            // the unavailable accessibilityHint(_:isEnabled:) one.
            #if !os(Android)
            .accessibilityHint(Text(isExpanded ? "Hide details" : "Show details"))
            #endif
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
                    //
                    // ICON ONLY (operator 2026-08-04: "do we even need a
                    // label?"). No: what fixed discoverability was making the
                    // control VISIBLE on expand, not the word next to it — and
                    // the Food tab's diary already deletes with a bare icon per
                    // row, so a labelled pill was the odd one out. It was also
                    // the direct cause of the wrap: ~75pt of button competing
                    // with five chips. At ~28pt the width contention is gone
                    // structurally rather than held back by fixedSize.
                    if let entryId = row.entryId, let onDelete {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedRowID = nil
                            }
                            onDelete(entryId)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: Theme.FontSize.tiny, weight: .semibold))
                                .foregroundStyle(Theme.surplus)
                                // Tap target stays finger-sized even though the
                                // glyph shrank — the hit area is what a
                                // destructive control must not skimp on.
                                .frame(width: 28, height: 22)
                                .background(Theme.surplus.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
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

#if !os(Android)
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
#endif

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
        // Foundation's DateFormatter defaults to UTC on Android but to the
        // device zone on Apple, so an unpinned formatter renders meal times
        // hours off there. No-op on iOS; same pin as DateFormatters.swift.
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// `loggedAt` arrives in three shapes across the codebase: ISO with
    /// fractional seconds (the AI pipeline), ISO without (older writers), and
    /// SQLite's `datetime('now')` — "2026-08-10 19:40:00", UTC, which is what
    /// the column default produces. Every other reader of this field already
    /// defends against all three (FoodLogViewModel, FoodTabView, TodayTab);
    /// this one didn't, so a sqlite-shaped row rendered its time as "—".
    private static func parse(_ loggedAt: String) -> Date? {
        isoFrac.date(from: loggedAt)
            ?? isoNoFrac.date(from: loggedAt)
            ?? DateFormatters.sqliteDatetime.date(from: loggedAt)
    }

    /// Build the row list from today's `[FoodEntry]`. Sorted by `loggedAt`
    /// ascending so the earliest meal sits at the top of the rail.
    /// Unparseable timestamps fall to the end of the list rather than crash —
    /// the dashboard never wants to render a partial row.
    static func rows(from entries: [FoodEntry]) -> [MealTimelineRow] {
        let timeFmt = Self.timeFmt

        let sorted = entries.sorted { a, b in
            let da = Self.parse(a.loggedAt) ?? .distantFuture
            let db = Self.parse(b.loggedAt) ?? .distantFuture
            return da < db
        }
        return sorted.map { entry in
            let dt = Self.parse(entry.loggedAt)
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

// The #Preview macro exists in neither the Android Swift build nor Skip's
// Darwin bridging pass, so previews are iOS-app-only in SharedUI files.
#if DEBUG && DRIFT_IOS_APP
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
