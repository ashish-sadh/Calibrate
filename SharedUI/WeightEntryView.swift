import SwiftUI
import DriftCore

/// Unified weight + body composition entry view.
/// Used by Dashboard "Tap to update", the Weight tab "+" and the Weight tab's
/// edit-a-weigh-in affordance — on BOTH platforms since #1143 (Android's
/// weight-only `AddWeightSheet` is gone; this file is the single source).
struct WeightEntryView: View {
    let unit: WeightUnit
    var initialWeight: Double? = nil
    var initialDate: String? = nil
    var lastBodyFat: Double? = nil
    var lastBMI: Double? = nil
    var lastWater: Double? = nil
    let onSave: (Double, Date) -> Void
    var onSaveBodyComp: ((BodyComposition) -> Void)? = nil

    // Not `private`: Skip Fuse can't bridge private @State/@Environment, and the
    // Android compile error points at line 1 rather than the member.
    @Environment(\.dismiss) var dismiss
    @State var weightText = ""
    @State var selectedDate = Date()
    // Body composition (optional, collapsed by default)
    @State var showBodyComp = false
    @State var bodyFatText = ""
    @State var bmiText = ""
    @State var waterText = ""
    @State var showMore = false
    @State var muscleMassText = ""
    @State var boneMassText = ""
    @State var visceralFatText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        NumericField("0.0", text: $weightText)
                            .font(.title.monospacedDigit())
                        Text(unit.displayName)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                }

                // Body composition — expandable
                Section {
                    DisclosureGroup("Body Composition", isExpanded: $showBodyComp) {
                        BodyCompFieldRow(icon: "figure.arms.open", label: "Body Fat", text: $bodyFatText, unit: "%",
                                         placeholder: lastBodyFat.map { String(format: "%.1f", $0) })
                        BodyCompFieldRow(icon: "heart.text.clipboard", label: "BMI", text: $bmiText,
                                         placeholder: lastBMI.map { String(format: "%.1f", $0) })
                        BodyCompFieldRow(icon: "drop", label: "Water", text: $waterText, unit: "%",
                                         placeholder: lastWater.map { String(format: "%.1f", $0) })

                        DisclosureGroup("More", isExpanded: $showMore) {
                            BodyCompFieldRow(icon: "figure.strengthtraining.traditional", label: "Muscle", text: $muscleMassText, unit: unit.displayName)
                            BodyCompFieldRow(icon: "bone", label: "Bone", text: $boneMassText, unit: unit.displayName)
                            BodyCompFieldRow(icon: "circle.dotted.and.circle", label: "Visceral Fat", text: $visceralFatText)
                        }
                    }
                }
            }
            .navigationTitle(initialWeight != nil ? "Edit Weight" : "Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled((decimal(weightText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if let w = initialWeight {
                    weightText = String(format: "%.1f", unit.convert(fromKg: w))
                }
                if let d = initialDate, let parsed = DateFormatters.dateOnly.date(from: d) {
                    selectedDate = parsed
                }
            }
        }
    }

    /// #999: parse a decimal that may use ',' as the separator (comma-decimal locales),
    /// where `Double("72,5")` returns nil and the entry would silently fail to save.
    /// The Save gate reads through this too — `Double(weightText)` alone left Save
    /// greyed out for a comma-locale user who had typed a perfectly valid weight.
    private func decimal(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let value = decimal(weightText), value > 0 else { return }
        onSave(value, selectedDate)

        // Save body comp if any fields filled
        let comp = BodyComposition(
            date: DateFormatters.dateOnly.string(from: selectedDate),
            bodyFatPct: decimal(bodyFatText),
            bmi: decimal(bmiText),
            waterPct: decimal(waterText),
            // #1005: Muscle/Bone are entered in the user's unit (lbs for lbs users) but
            // stored as kg — convert instead of storing the raw lbs value.
            muscleMassKg: decimal(muscleMassText).map { unit.convertToKg($0) },
            boneMassKg: decimal(boneMassText).map { unit.convertToKg($0) },
            visceralFat: decimal(visceralFatText)
        )
        if comp.hasData {
            onSaveBodyComp?(comp)
        }
        dismiss()
    }
}

/// One body-composition input row. A `View` struct rather than the old
/// `fieldRow(...)` helper on purpose: Skip Fuse binds only the FIRST `TextField`
/// per ViewBuilder scope, so three rows built by one function inside the
/// DisclosureGroup would leave BMI and Water dead on Android (#1097 idiom, the
/// same reason `EditableMacroField` exists).
struct BodyCompFieldRow: View {
    let icon: String
    let label: String
    @Binding var text: String
    var unit: String = ""
    var placeholder: String? = nil

    var body: some View {
        HStack {
            // skip-ui 1.58 maps ~46 SF Symbols and none of these six. A `person`
            // stand-in for both "Body Fat" and "Muscle" would read as one glyph
            // repeated, and the other four have no near-meaning Material icon at
            // all — so Android shows the label alone. The row text carries the
            // meaning; iOS itself already draws "Bone" with no glyph (`bone`
            // isn't an SF Symbol on iOS 26 either).
            #if os(Android)
            Text(label)
            #else
            Label(label, systemImage: icon)
            #endif
            Spacer()
            NumericField(placeholder ?? "—", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            if !unit.isEmpty {
                Text(unit).foregroundStyle(Theme.textSecondary).frame(width: 35, alignment: .leading)
            }
        }
    }
}
