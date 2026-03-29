import SwiftUI

struct AddSupplementView: View {
    @Bindable var viewModel: SupplementViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dosage = ""
    @State private var unit = "mg"

    let units = ["mg", "g", "ml", "capsule", "packet", "tablet"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplement") {
                    TextField("Name", text: $name)
                }

                Section("Dosage") {
                    TextField("Amount", text: $dosage)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $unit) {
                        ForEach(units, id: \.self) { u in
                            Text(u).tag(u)
                        }
                    }
                }
            }
            .navigationTitle("Add Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addCustomSupplement(name: name, dosage: dosage, unit: unit)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
