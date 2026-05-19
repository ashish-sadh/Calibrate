import SwiftUI

/// One ring's data — value, target, hue, label.
///
/// Mirrors the `rings: [{ value, target, color, bg, label, unit }]` shape used
/// in `Docs/design-references/v6-2026-05-14/v6/v6-rings.jsx`.
///
/// `id` is the label so SwiftUI's `ForEach` keeps stable identity across body
/// recomputes — the parent rebuilds the `[V6Ring]` array every time
/// `todayNutrition` changes, and a `UUID()` per init would churn identity and
/// strip the diffing engine of a useful key.
struct V6Ring: Identifiable {
    var id: String { label }
    let label: String
    let unit: String
    let value: Double
    let target: Double
    let color: Color
    let trackColor: Color
}

/// Apple-Fitness-style concentric rings — the V6 hero.
///
/// Layout matches `V6Rings()` in v6-rings.jsx: outer ring is the first element,
/// each subsequent ring is inset by `stroke + gap`. Overshoot (value > target)
/// renders a thinner, semi-transparent halo on top so the user sees they went
/// past goal without the primary stroke double-painting.
struct V6Rings: View {
    let rings: [V6Ring]
    var size: CGFloat = 200
    var stroke: CGFloat = 18
    var gap: CGFloat = 4
    /// Optional center content (typically a `V6Num` + label).
    var center: AnyView?

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                ringLayer(ring: ring, index: index)
            }
            if let center {
                center
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { animationPhase = 1 }
        }
    }

    private func radius(for index: Int) -> CGFloat {
        (size - stroke) / 2 - CGFloat(index) * (stroke + gap)
    }

    @ViewBuilder
    private func ringLayer(ring: V6Ring, index: Int) -> some View {
        let r = radius(for: index)
        // NaN/inf guard: a NaN value or NaN target would silently render nothing
        // (NaN compares false to everything → both pct and over become 0).
        // Treat non-finite inputs as zero so the user sees an empty ring,
        // not a phantom missing arc.
        let safeValue = ring.value.isFinite ? ring.value : 0
        let safeTarget = ring.target.isFinite ? ring.target : 0
        let pct = safeTarget > 0 ? min(safeValue / safeTarget, 1.0) : 0
        let over = safeTarget > 0 && safeValue > safeTarget ? min(safeValue / safeTarget - 1, 1.0) : 0
        let animated = pct * animationPhase

        ZStack {
            Circle()
                .stroke(ring.trackColor, style: StrokeStyle(lineWidth: stroke))
                .frame(width: r * 2, height: r * 2)

            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    LinearGradient(
                        colors: [ring.color, ring.color.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: r * 2, height: r * 2)

            if over > 0 {
                Circle()
                    .trim(from: 0, to: over * animationPhase)
                    .stroke(ring.color.opacity(0.35),
                            style: StrokeStyle(lineWidth: stroke * 0.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: r * 2, height: r * 2)
            }
        }
    }
}

/// Row of dot + label + value/target — sits under V6Rings.
///
/// Same item shape as `V6RingLegend` in v6-rings.jsx, plus a `columns` knob so
/// callers can render either the 3-ring legend (under the rings) or a sparser
/// carbs-vs-fat row (under a hairline divider).
struct V6RingLegend: View {
    let rings: [V6Ring]
    var columns: Int = 0  // 0 = one column per ring

    var body: some View {
        let cols = columns > 0 ? columns : rings.count
        let spec = Array(repeating: GridItem(.flexible(), spacing: 12), count: cols)
        LazyVGrid(columns: spec, spacing: 4) {
            ForEach(rings) { ring in
                V6LegendItem(ring: ring)
            }
        }
    }
}

/// One legend cell — dot + label, value/target underneath.
struct V6LegendItem: View {
    let ring: V6Ring

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(ring.color).frame(width: 7, height: 7)
                Text(ring.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                Text("\(Int(ring.value))")
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("/\(Int(ring.target))\(ring.unit)")
                    .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("V6Rings — kcal/protein/fiber") {
    let rings: [V6Ring] = [
        V6Ring(label: "kcal", unit: "", value: 1450, target: 2000,
               color: Theme.V6.ringMove, trackColor: Theme.V6.ringMoveBg),
        V6Ring(label: "protein", unit: "g", value: 95, target: 150,
               color: Theme.V6.ringEx, trackColor: Theme.V6.ringExBg),
        V6Ring(label: "fiber", unit: "g", value: 18, target: 30,
               color: Theme.V6.ringStand, trackColor: Theme.V6.ringStandBg),
    ]
    return VStack(spacing: 16) {
        V6Rings(
            rings: rings,
            size: 210,
            stroke: 20,
            center: AnyView(
                VStack(spacing: 4) {
                    Text("1,450")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    Text("KCAL")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
            )
        )
        V6RingLegend(rings: rings)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}
#endif
