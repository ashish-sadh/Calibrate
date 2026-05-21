import SwiftUI

/// Concentric macro rings with goal-aware fill color, tap-to-tooltip, and appear animation.
struct MacroRingsView: View {
    let calories: Double
    let calorieTarget: Double
    let protein: Double
    let proteinTarget: Double
    let carbs: Double
    let carbsTarget: Double
    let fat: Double
    let fatTarget: Double
    /// True when the user's goal direction is to lose weight (deficit = aligned).
    var isLosingWeight: Bool = true

    @State private var animationPhase: CGFloat = 0
    @State private var showTooltip = false

    private let lineWidth: CGFloat = 8
    private let ringGap: CGFloat = 3

    private struct RingSpec {
        let value: Double
        let target: Double
        let identityColor: Color
        let label: String
        let unit: String
        let kcalPerUnit: Double  // 4 for protein/carbs, 9 for fat, 0 for calories ring
    }

    private var rings: [RingSpec] {
        [
            RingSpec(value: calories, target: calorieTarget,
                     identityColor: Theme.calorieBlue, label: "Calories", unit: "kcal", kcalPerUnit: 0),
            RingSpec(value: protein, target: proteinTarget,
                     identityColor: Theme.proteinRed, label: "Protein", unit: "g", kcalPerUnit: 4),
            RingSpec(value: carbs, target: carbsTarget,
                     identityColor: Theme.carbsGreen, label: "Carbs", unit: "g", kcalPerUnit: 4),
            RingSpec(value: fat, target: fatTarget,
                     identityColor: Theme.fatYellow, label: "Fat", unit: "g", kcalPerUnit: 9),
        ]
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { idx, ring in
                ringLayer(ring: ring, index: idx)
            }

            // Center: remaining calories
            VStack(spacing: 1) {
                let remaining = Int(calorieTarget - calories)
                Text("\(abs(remaining))")
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                Text(remaining >= 0 ? "left" : "over")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if showTooltip {
                tooltipView
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { showTooltip.toggle() }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { animationPhase = 1 }
        }
    }

    private var diameter: CGFloat { 140 }

    private func ringRadius(index: Int) -> CGFloat {
        let outerRadius = diameter / 2 - lineWidth / 2
        return outerRadius - CGFloat(index) * (lineWidth + ringGap)
    }

    private func fillColor(for ring: RingSpec) -> Color {
        let ratio = ring.target > 0 ? ring.value / ring.target : 0
        if ratio > 1.0 { return Theme.surplus }
        if ring.kcalPerUnit == 0 && isLosingWeight { return Theme.deficit }
        return ring.identityColor
    }

    private func ringLayer(ring: RingSpec, index: Int) -> some View {
        let radius = ringRadius(index: index)
        let rawProgress = ring.target > 0 ? ring.value / ring.target : 0
        let animated = min(rawProgress, 1.0) * animationPhase
        let color = fillColor(for: ring)

        return ZStack {
            Circle()
                .stroke(ring.identityColor.opacity(0.15), lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
        }
    }

    private var tooltipView: some View {
        // The parent ZStack pins MacroRingsView at 140×140, so the tooltip would
        // inherit that width and wrap each row character-by-character (#699).
        // `.fixedSize(horizontal:)` lets the tooltip take its natural width
        // (~260pt) and overflow the ring's frame, which is the desired UX.
        // Own `onTapGesture` so taps on the overflowing region (outside the
        // ring's `.contentShape(Circle())` hit-region) still dismiss it.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                tooltipRow(for: ring)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // V7 light fix: was `.ultraThinMaterial` which renders as a
        // dark blob over saturated chart colors on light theme (see
        // WeightChartView annotation fix). Solid surface + hairline +
        // soft shadow is the V7 chrome pattern.
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        .fixedSize(horizontal: true, vertical: false)
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { showTooltip = false }
        }
    }

    private func tooltipRow(for ring: RingSpec) -> some View {
        let remaining = ring.target - ring.value
        let calPct = caloriePercent(for: ring)

        // `.lineLimit(1)` per-Text is defensive: a future ancestor that
        // re-constrains width can't bring back the per-character wrap (#699).
        return HStack(spacing: 6) {
            Circle().fill(ring.identityColor).frame(width: 6, height: 6)
            Text(ring.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ring.identityColor)
                .lineLimit(1)
                .frame(width: 46, alignment: .leading)
            Text("\(Int(ring.value))/\(Int(ring.target))\(ring.unit)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if calPct > 0 {
                Text("·")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                Text("\(Int(calPct))%")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if ring.target > 0 {
                Text(remaining >= 0
                     ? "\(Int(remaining))\(ring.unit) left"
                     : "\(Int(-remaining))\(ring.unit) over")
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? Color.secondary.opacity(0.6) : Theme.surplus)
                    .lineLimit(1)
            }
        }
    }

    private func caloriePercent(for ring: RingSpec) -> Double {
        guard ring.kcalPerUnit > 0, calories > 0 else { return 0 }
        return ring.value * ring.kcalPerUnit / calories * 100
    }
}
