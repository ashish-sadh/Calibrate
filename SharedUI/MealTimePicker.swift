import SwiftUI
import DriftCore

// Single-source (SharedUI): time + meal picker for the log/edit sheets on
// BOTH apps. 2026-07-27 field ask: horizontal meal chips instead of a
// dropdown, a time slider instead of the wheel, and the two coupled so
// dragging the slider to 10am flips the chip to Breakfast. Tapping a chip
// afterwards still pins the meal without moving the time.
struct MealTimePicker: View {
    @Binding var time: Date
    @Binding var mealType: MealType

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Time").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                #if os(Android)
                // Material's Slider can't be themed from Fuse (no
                // material3ColorScheme hook there), so its INACTIVE track
                // rendered in the device's dynamic-colour primary — a purple
                // half-bar next to the coral half (field report 2026-07-28).
                // The native time field is the platform-correct control and
                // was already proven here pre-#1097; the coupling below keeps
                // the operator's "pick 10am → Breakfast" behaviour identical.
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                #else
                Text(DateFormatters.shortTime.string(from: time))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                #endif
            }
            #if !os(Android)
            Slider(value: minutesBinding, in: 0...1435, step: 5)
                .tint(Theme.accent)
                .accessibilityLabel("Time of day")
            #endif
            MealChips(selection: $mealType)
        }
    }

    /// Android's time-field lens — same coupling as the slider: changing the
    /// time re-derives the meal chip from the new hour.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { time },
            set: { newValue in
                time = newValue
                mealType = MealType.defaultForHour(
                    Calendar.current.component(.hour, from: newValue))
            }
        )
    }

    /// Minutes-since-midnight lens over `time`. Setting snaps the bound
    /// date's hour/minute (day untouched) and re-derives the meal chip from
    /// the new hour — the slider→meal coupling.
    private var minutesBinding: Binding<Double> {
        Binding(
            get: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            },
            set: { raw in
                let total = Int(raw)
                if let updated = Calendar.current.date(
                    bySettingHour: total / 60, minute: total % 60, second: 0, of: time) {
                    time = updated
                }
                mealType = MealType.defaultForHour(total / 60)
            }
        )
    }
}

/// Horizontal meal-period chips — the capsule row EditFoodEntrySheet
/// introduced, extracted so every log surface shares one look. Internal,
/// not private — Skip cannot bridge private views.
struct MealChips: View {
    @Binding var selection: MealType

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MealType.allCases, id: \.self) { meal in
                Button {
                    selection = meal
                } label: {
                    HStack(spacing: 4) {
                        #if os(Android)
                        MealGlyph(meal: meal,
                                  color: selection == meal ? .white : Theme.textSecondary,
                                  size: 12)
                        #else
                        Image(systemName: meal.icon).font(.caption2)
                        #endif
                        Text(meal.displayName).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(selection == meal ? .white : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(selection == meal ? Theme.ink : Theme.cardBackgroundElevated,
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set meal to \(meal.displayName)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
