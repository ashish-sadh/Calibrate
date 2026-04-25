import SwiftUI
import DriftCore

struct AddSupplementView: View {
    @Bindable var viewModel: SupplementViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .popular
    @State private var name = ""
    @State private var dosage = ""
    @State private var unit = "mg"
    @State private var dailyDoses = 1

    enum AddMode: String, CaseIterable { case popular = "Popular"; case custom = "Custom" }

    static let popularSupplements: [(name: String, dosage: String, unit: String)] = [
        ("Creatine", "5", "g"),
        ("Omega 3 (Fish Oil)", "1000", "mg"),
        ("Vitamin D3", "5000", "IU"),
        ("Magnesium Glycinate", "400", "mg"),
        ("Electrolytes", "1 packet", "packet"),
        ("AG1", "1 scoop", "scoop"),
        ("Zinc", "30", "mg"),
        ("Ashwagandha", "600", "mg"),
        ("Collagen Peptides", "10", "g"),
        ("Multivitamin", "1", "tablet"),
        ("Vitamin C", "1000", "mg"),
        ("Probiotics", "1", "capsule"),
        ("Iron", "18", "mg"),
        ("B12", "1000", "mcg"),
        ("Melatonin", "3", "mg"),
        ("L-Theanine", "200", "mg"),
        ("Turmeric / Curcumin", "500", "mg"),
        ("CoQ10", "100", "mg"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(AddMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8)

                if mode == .popular {
                    List {
                        ForEach(Self.popularSupplements, id: \.name) { supp in
                            Button {
                                viewModel.addCustomSupplement(name: supp.name, dosage: supp.dosage, unit: supp.unit)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(supp.name).font(.subheadline)
                                        Text("\(supp.dosage) \(supp.unit)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Form {
                        Section("Supplement") {
                            TextField("Name", text: $name)
                        }
                        Section("Dosage") {
                            TextField("Amount", text: $dosage).keyboardType(.decimalPad)
                            Picker("Unit", selection: $unit) {
                                ForEach(["mg", "g", "ml", "mcg", "IU", "capsule", "packet", "tablet", "scoop"], id: \.self) { Text($0).tag($0) }
                            }
                            Stepper("Times per day: \(dailyDoses)", value: $dailyDoses, in: 1...5)
                        }
                        Section {
                            Button {
                                viewModel.addCustomSupplement(name: name, dosage: dosage, unit: unit, dailyDoses: dailyDoses)
                                dismiss()
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(name.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Add Supplement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
