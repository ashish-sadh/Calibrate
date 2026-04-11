import SwiftUI

struct WeightEntryView: View {
    let unit: WeightUnit
    var initialWeight: Double? = nil
    var initialDate: String? = nil
    let onSave: (Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.title.monospacedDigit())
                        Text(unit.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                }
            }
            .navigationTitle(initialWeight != nil ? "Edit Weight" : "Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(weightText), value > 0 {
                            onSave(value, selectedDate)
                            dismiss()
                        }
                    }
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
}
