import SwiftUI

/// Entry view for body composition + optional weight.
struct BodyCompEntryView: View {
    let unit: WeightUnit
    let onSave: (Double?, BodyComposition, Date) -> Void  // weight, bodyComp, date
    var lastBodyFat: Double? = nil
    var lastBMI: Double? = nil
    var lastWater: Double? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var bmiText = ""
    @State private var waterText = ""
    @State private var muscleMassText = ""
    @State private var boneMassText = ""
    @State private var visceralFatText = ""
    @State private var metabolicAgeText = ""
    @State private var showMore = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fieldRow(icon: "scalemass.fill", label: "Weight", text: $weightText, unit: unit.displayName)
                } header: {
                    Text("Weight (Optional)")
                }

                Section {
                    fieldRow(icon: "figure.arms.open", label: "Body Fat", text: $bodyFatText, unit: "%",
                             placeholder: lastBodyFat.map { String(format: "%.1f", $0) })
                    fieldRow(icon: "heart.text.clipboard", label: "BMI", text: $bmiText,
                             placeholder: lastBMI.map { String(format: "%.1f", $0) })
                    fieldRow(icon: "drop", label: "Water", text: $waterText, unit: "%",
                             placeholder: lastWater.map { String(format: "%.1f", $0) })
                } header: {
                    Text("Body Composition")
                }

                Section {
                    DisclosureGroup("More Measurements", isExpanded: $showMore) {
                        fieldRow(icon: "figure.strengthtraining.traditional", label: "Muscle Mass", text: $muscleMassText, unit: "kg")
                        fieldRow(icon: "bone", label: "Bone Mass", text: $boneMassText, unit: "kg")
                        fieldRow(icon: "circle.dotted.and.circle", label: "Visceral Fat", text: $visceralFatText, unit: "rating")
                        fieldRow(icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "Metabolic Age", text: $metabolicAgeText, unit: "years")
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Log Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(!hasAnyValue)
                }
            }
        }
    }

    private var hasAnyValue: Bool {
        !weightText.isEmpty || !bodyFatText.isEmpty || !bmiText.isEmpty || !waterText.isEmpty ||
        !muscleMassText.isEmpty || !boneMassText.isEmpty || !visceralFatText.isEmpty || !metabolicAgeText.isEmpty
    }

    private func save() {
        let weight = Double(weightText)
        let comp = BodyComposition(
            date: DateFormatters.dateOnly.string(from: selectedDate),
            bodyFatPct: Double(bodyFatText),
            bmi: Double(bmiText),
            waterPct: Double(waterText),
            muscleMassKg: Double(muscleMassText),
            boneMassKg: Double(boneMassText),
            visceralFat: Double(visceralFatText),
            metabolicAge: Int(metabolicAgeText)
        )
        guard weight != nil || comp.hasData else { return }
        onSave(weight, comp, selectedDate)
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
                Text(unit).foregroundStyle(.secondary).frame(width: 35, alignment: .leading)
            }
        }
    }
}
