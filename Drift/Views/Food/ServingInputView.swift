import SwiftUI

/// Shared serving input component: amount field + unit picker + quick-amount buttons + conversion hint.
/// Used across food search, barcode scan, quick add, and food tab edit.
struct ServingInputView: View {
    @Binding var amount: String
    @Binding var selectedUnitIndex: Int
    let units: [FoodUnit]
    let servingSize: Double

    private var unit: FoodUnit {
        let idx = min(selectedUnitIndex, max(units.count - 1, 0))
        return units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[idx]
    }

    var body: some View {
        VStack(spacing: 12) {
            // Amount + unit picker
            HStack(spacing: 12) {
                TextField("1", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.medium).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 10)
                    .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))

                Picker("", selection: $selectedUnitIndex) {
                    ForEach(0..<units.count, id: \.self) { i in
                        Text(units[i].label).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: selectedUnitIndex) { oldIdx, newIdx in
                    guard oldIdx < units.count, newIdx < units.count else { return }
                    let oldUnit = units[oldIdx]
                    let newUnit = units[newIdx]
                    let currentAmount = Double(amount) ?? 0
                    let grams = currentAmount * oldUnit.gramsEquivalent
                    let converted = newUnit.gramsEquivalent > 0 ? grams / newUnit.gramsEquivalent : currentAmount
                    amount = converted == Double(Int(converted)) ? "\(Int(converted))" : String(format: "%.1f", converted)
                }
            }

            // Conversion hint
            if unit.label != "g" && unit.label != "ml" && unit.label != "serving" && unit.gramsEquivalent > 1 {
                Text("1 \(unit.label) = \(Int(unit.gramsEquivalent))g")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Quick amount buttons — standardized across all UIs
            HStack(spacing: 5) {
                ForEach(Array(zip([0.25, 1.0/3, 0.5, 1.0, 1.5, 2.0],
                                  ["\u{00BC}", "\u{2153}", "\u{00BD}", "1x", "1\u{00BD}", "2x"])), id: \.0) { mult, label in
                    Button {
                        if unit.label == "g" || unit.label == "ml" {
                            amount = String(format: "%.0f", servingSize * mult)
                        } else if mult < 1 {
                            amount = String(format: "%.2f", mult)
                        } else {
                            amount = mult == Double(Int(mult)) ? "\(Int(mult))" : String(format: "%.1f", mult)
                        }
                    } label: {
                        Text(label).font(.caption2.weight(.medium))
                    }.buttonStyle(.bordered)
                }
            }
        }
    }
}
