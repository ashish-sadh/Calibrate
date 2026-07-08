import SwiftUI
import DriftCore

/// Compact, fully-editable serving-multiplier control: −  [type a value]×  +
///
/// Scales up AND down (step 0.5, floor 0.25, no upper cap) and lets you TYPE an
/// exact multiplier (e.g. 1.2×, 2.5×) — fixing the combo stepper that was stuck
/// at coarse 0.5 steps with a broken floor. Used wherever a food's macros scale
/// by a multiplier rather than grams (combo items). #serving-edit
struct ServingMultiplierStepper: View {
    @Binding var servings: Double
    var step: Double = 0.5
    var minValue: Double = 0.25
    var enabled: Bool = true

    @State private var text: String = "1"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button { commit(servings - step) } label: {
                Image(systemName: "minus").font(.caption2.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!enabled || servings <= minValue)

            HStack(spacing: 1) {
                TextField("1", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
                    .frame(minWidth: 18)
                    .focused($focused)
                    .disabled(!enabled)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .onChange(of: focused) { _, now in if !now { commitText() } }
                    .submitLabel(.done)
                    .onSubmit { commitText(); focused = false }
                Text("×").font(.caption2).foregroundStyle(Theme.textSecondary)
            }

            Button { commit(servings + step) } label: {
                Image(systemName: "plus").font(.caption2.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
        .foregroundStyle(enabled ? Color.primary : .secondary)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { text = Self.format(servings) }
        .onChange(of: servings) { _, v in if !focused { text = Self.format(v) } }
    }

    private func commit(_ raw: Double) {
        servings = Self.clamp(raw, min: minValue)
        text = Self.format(servings)
    }

    private func commitText() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(normalized), v > 0 {
            commit(v)
        } else {
            text = Self.format(servings)   // reject garbage, restore last good value
        }
    }

    /// Floor at `min`, round to 2 decimals (kills float drift like 1.4999999).
    static func clamp(_ raw: Double, min: Double) -> Double {
        Swift.max(min, (raw * 100).rounded() / 100)
    }

    /// "1", "1.5", "1.25" — integers without a trailing .0, fractions trimmed.
    static func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(v.safeInt)" : String(format: "%g", v)
    }
}
