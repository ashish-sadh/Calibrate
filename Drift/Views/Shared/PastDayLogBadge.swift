import SwiftUI
import DriftCore

/// Compact "you are logging to a PAST day" indicator for logging surfaces.
///
/// The Food diary's "Viewing <day>" banner is covered the moment any logging
/// sheet slides up — which is exactly the point of commitment where the
/// target day matters (field ask 2026-07-09: "make it obvious when someone
/// is logging for a past day — small but not intrusive"). Every surface that
/// writes to the diary shows this chip when its FoodLogViewModel targets a
/// day other than today. Derived from the VM's `selectedDate`, so it can
/// never drift out of sync with where the entry will actually land.
///
/// Same visual language as the diary's past-date banner (amber + triangle),
/// one caption-sized line, no interaction.
struct PastDayLogBadge: View {
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.caption2)
                .foregroundStyle(Theme.fatYellow)
            Text("Logging to \(DateFormatters.dayDisplay.string(from: date))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Theme.fatYellow.opacity(0.12), in: Capsule())
        .accessibilityLabel("Warning: logging to \(DateFormatters.dayDisplay.string(from: date)), not today")
    }
}

extension View {
    /// Overlay-style helper: shows the badge above this content only when
    /// `vm` targets a past (or future) day. Keeps call sites one-line.
    @ViewBuilder
    func pastDayLogBadge(for vm: FoodLogViewModel) -> some View {
        if !vm.isToday {
            VStack(spacing: 8) {
                PastDayLogBadge(date: vm.selectedDate)
                self
            }
        } else {
            self
        }
    }
}

#Preview {
    PastDayLogBadge(date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!)
}
