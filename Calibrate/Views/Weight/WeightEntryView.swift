import SwiftUI

struct WeightEntryView: View {
    let unit: WeightUnit
    let onSave: (Double) -> Void

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
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(weightText) {
                            onSave(value)
                            dismiss()
                        }
                    }
                    .disabled(Double(weightText) == nil)
                }
            }
        }
    }
}
