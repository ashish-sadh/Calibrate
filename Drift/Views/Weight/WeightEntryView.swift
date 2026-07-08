import SwiftUI
import DriftCore

/// Unified weight + body composition entry view.
/// Used by Dashboard "Tap to update" and Weight tab "+".
struct WeightEntryView: View {
    let unit: WeightUnit
    var initialWeight: Double? = nil
    var initialDate: String? = nil
    var lastBodyFat: Double? = nil
    var lastBMI: Double? = nil
    var lastWater: Double? = nil
    let onSave: (Double, Date) -> Void
    var onSaveBodyComp: ((BodyComposition) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var selectedDate = Date()
    // Body composition (optional, collapsed by default)
    @State private var showBodyComp = false
    @State private var bodyFatText = ""
    @State private var bmiText = ""
    @State private var waterText = ""
    @State private var showMore = false
    @State private var muscleMassText = ""
    @State private var boneMassText = ""
    @State private var visceralFatText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
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
                        fieldRow(icon: "figure.arms.open", label: "Body Fat", text: $bodyFatText, unit: "%",
                                 placeholder: lastBodyFat.map { String(format: "%.1f", $0) })
                        fieldRow(icon: "heart.text.clipboard", label: "BMI", text: $bmiText,
                                 placeholder: lastBMI.map { String(format: "%.1f", $0) })
                        fieldRow(icon: "drop", label: "Water", text: $waterText, unit: "%",
                                 placeholder: lastWater.map { String(format: "%.1f", $0) })

                        DisclosureGroup("More", isExpanded: $showMore) {
                            fieldRow(icon: "figure.strengthtraining.traditional", label: "Muscle", text: $muscleMassText, unit: unit.displayName)
                            fieldRow(icon: "bone", label: "Bone", text: $boneMassText, unit: unit.displayName)
                            fieldRow(icon: "circle.dotted.and.circle", label: "Visceral Fat", text: $visceralFatText)
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
                    .disabled((Double(weightText) ?? 0) <= 0)
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

    private func fieldRow(icon: String, label: String, text: Binding<String>, unit: String = "", placeholder: String? = nil) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            TextField(placeholder ?? "—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            if !unit.isEmpty {
                Text(unit).foregroundStyle(Theme.textSecondary).frame(width: 35, alignment: .leading)
            }
        }
    }
}
