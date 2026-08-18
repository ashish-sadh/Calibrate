import SwiftUI
import DriftCore

/// Month-grid date picker for the Food diary. Replaces the native
/// `.graphical` DatePicker so each day that has calories logged can carry a
/// small dot underneath — the native picker offers no per-day decoration.
///
/// Selecting a day routes through `onSelect` (the sheet closes on tap);
/// month navigation re-queries the VM for that month's logged days so the
/// dots stay correct when the user scrolls back through history.
/// Single-source (SharedUI): pure SwiftUI + DriftCore, compiles for both apps.
struct MealCalendarPicker: View {
    /// Seed for the initially displayed month ONLY — never the selection.
    /// Which cell is highlighted is read live off `viewModel.selectedDate`
    /// (#1254): under Fuse the sheet's composition is retained across
    /// presents, so a value param captured at construction froze the
    /// highlight on whatever day was selected the first time the sheet
    /// opened.
    let selectedDate: Date
    let viewModel: FoodLogViewModel
    let onSelect: (Date) -> Void

    @State var displayedMonth: Date
    @State var loggedDays: [Date: Double] = [:]

    private let cal = Calendar.current

    init(selectedDate: Date, viewModel: FoodLogViewModel, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.viewModel = viewModel
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: selectedDate)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader
            grid
            legend
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear { reloadMonth() }
        // A retained composition (Fuse) presents this again without re-running
        // `init`, so the month + dots would still be seeded from the first
        // present. On iOS the content rebuilds per present and this never
        // fires. #1254.
        .onChange(of: viewModel.selectedDate) { _, new in
            displayedMonth = new
            reloadMonth()
        }
    }

    // MARK: - Header (month label + prev/next)

    private var header: some View {
        HStack {
            Text(DateFormatters.monthYear.string(from: displayedMonth))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { shiftMonth(-1) } label: {
                Image(systemName: sym("chevron.left")).font(.body.weight(.semibold))
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Previous month")
            Button { shiftMonth(1) } label: {
                Image(systemName: sym("chevron.right")).font(.body.weight(.semibold))
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let dayStart = cal.startOfDay(for: day)
        // Live read + plain startOfDay equality, matching the day strip
        // (FoodTabView) — Skip's Calendar.isDate(inSameDayAs:) misses on
        // Android, which is what killed the selected pill there.
        let isSelected = dayStart == cal.startOfDay(for: viewModel.selectedDate)
        let isToday = cal.isDateInToday(day)
        let hasFood = (loggedDays[dayStart] ?? 0) > 0
        let isFuture = dayStart > cal.startOfDay(for: Date())

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout.weight(isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(numberColor(isSelected: isSelected, isFuture: isFuture))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(fillColor(isSelected: isSelected)))
                    .overlay(todayRing(ringColor(isToday: isToday, isSelected: isSelected)))
                // Food-logged indicator — the whole point of this picker.
                Circle()
                    .fill(dotColor(hasFood: hasFood, isSelected: isSelected))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Text-wrapped: Fuse's String overload of accessibilityLabel requires
        // an explicit isEnabled argument, so a bare String has no match.
        .accessibilityLabel(Text(dayAccessibilityLabel(day, isToday: isToday, hasFood: hasFood, isSelected: isSelected)))
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5)
            Text("Days with food logged")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 4)
    }

    // MARK: - Colors
    // (Typed helpers, not inline ternaries — conditional Colors in
    // ShapeStyle-generic positions are ambiguous under Fuse's overloads.)

    private func fillColor(isSelected: Bool) -> Color {
        isSelected ? Theme.ink : Color.clear
    }

    private func ringColor(isToday: Bool, isSelected: Bool) -> Color {
        (isToday && !isSelected) ? Theme.accent : Color.clear
    }

    /// iOS keeps strokeBorder; Fuse's two strokeBorder overload families go
    /// ambiguous here, so Android draws a plain stroke (0.75pt of geometry
    /// difference on a 34pt ring — imperceptible; house precedent
    /// ActiveWorkoutView set-done ring).
    @ViewBuilder
    private func todayRing(_ color: Color) -> some View {
        #if os(Android)
        Circle().stroke(color, lineWidth: 1.5)
        #else
        Circle().strokeBorder(color, lineWidth: 1.5)
        #endif
    }

    private func numberColor(isSelected: Bool, isFuture: Bool) -> Color {
        if isSelected { return .white }
        return isFuture ? Theme.textTertiary : Theme.textPrimary
    }

    private func dotColor(hasFood: Bool, isSelected: Bool) -> Color {
        guard hasFood else { return .clear }
        // On the ink-filled selected cell an accent dot muddies; use white.
        return isSelected ? .white : Theme.accent
    }

    // MARK: - Month layout

    /// Very-short weekday symbols reordered to honor the locale's first
    /// weekday (Sunday-first in the US, Monday-first elsewhere).
    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The displayed month laid out as 7-column weeks. Leading `nil`s pad the
    /// first week to the correct weekday; trailing `nil`s complete the grid.
    private var monthDays: [Date?] {
        guard let monthInterval = cal.dateInterval(of: .month, for: displayedMonth),
              let range = cal.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - cal.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            cells.append(cal.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    // MARK: - Actions

    private func shiftMonth(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
        reloadMonth()
    }

    private func reloadMonth() {
        loggedDays = viewModel.loggedDays(inMonth: displayedMonth)
    }

    private func dayAccessibilityLabel(_ day: Date, isToday: Bool, hasFood: Bool, isSelected: Bool) -> String {
        var parts = [DateFormatters.dayDisplay.string(from: day)]
        if isToday { parts.append("today") }
        if hasFood { parts.append("food logged") }
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}
