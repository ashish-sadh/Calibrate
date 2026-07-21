import SwiftUI
import DriftCore

/// Shared serving input component: amount field + unit pills + gram equivalence + quick-amount buttons.
/// Used across food search, barcode scan, quick add, and food tab edit.
/// Single-source (SharedUI): compiles for both apps — no symbols, one
/// TextField in its own scope (the Fuse first-TextField binding rule).
struct ServingInputView: View {
    @Binding var amount: String
    @Binding var selectedUnitIndex: Int
    let units: [FoodUnit]
    let servingSize: Double

    private var unit: FoodUnit {
        let idx = min(selectedUnitIndex, max(units.count - 1, 0))
        return units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[idx]
    }

    private var totalGrams: Double {
        (Double(amount) ?? 0) * unit.gramsEquivalent
    }

    var body: some View {
        VStack(spacing: 10) {
            // Amount field
            TextField("1", text: $amount)
                .keyboardType(.decimalPad)
                .font(.title2.weight(.medium).monospacedDigit())
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: Theme.radiusChip))

            // Unit pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<units.count, id: \.self) { i in
                        Button {
                            let oldIdx = selectedUnitIndex
                            selectedUnitIndex = i
                            // Auto-convert amount
                            if oldIdx < units.count, i < units.count {
                                let oldUnit = units[oldIdx]
                                let newUnit = units[i]
                                let currentAmount = Double(amount) ?? 0
                                let grams = currentAmount * oldUnit.gramsEquivalent
                                let converted = newUnit.gramsEquivalent > 0 ? grams / newUnit.gramsEquivalent : currentAmount
                                // #1006: Int(converted) traps on huge/NaN input; use format specifiers, which don't.
                                amount = converted.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", converted) : String(format: "%.1f", converted)
                            }
                        } label: {
                            Text(units[i].label)
                                .font(.caption.weight(i == selectedUnitIndex ? .semibold : .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    i == selectedUnitIndex
                                        ? Theme.ink
                                        : Theme.cardBackgroundElevated,
                                    in: Capsule()
                                )
                                .foregroundStyle(i == selectedUnitIndex ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            #if os(Android)
            // Fuse collapses a horizontal ScrollView to the text line's height
            // once the IME closes (see #1089) — pin the pills' natural height.
            .frame(height: 34)
            #endif

            // Gram equivalence — always visible unless unit is already g/ml.
            // Prefix "≈" for estimated units (spray, flat-constant tbsp) so the
            // UI doesn't advertise a guessed gram figure as ground truth.
            if unit.label != "g" && unit.label != "ml" && totalGrams > 0 {
                let gramPrefix = unit.isEstimate ? "≈ " : "= "
                Text("\(gramPrefix)\(totalGrams < 10 ? String(format: "%.1f", totalGrams) : String(format: "%.0f", totalGrams))g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            // Quick amount buttons
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
