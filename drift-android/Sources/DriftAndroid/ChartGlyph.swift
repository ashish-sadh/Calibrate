import SwiftUI

/// Bar-chart glyph drawn as a `Path`: the pinned skip-ui 1.58.0 (#1134) has NO
/// chart entry at all — `chart.bar.xaxis`, the target Symbols.swift maps the
/// chart-family names to, only exists in skip-ui ≥1.59, so under the pin those
/// call sites rendered the warning triangle. Same precedent as
/// DumbbellGlyph/FlameGlyph/ClockGlyph: draw the real object.
///
/// Geometry mirrors Material's `bar_chart`: three bottom-aligned vertical bars
/// of different heights on a 24pt grid.
struct BarChartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func bar(_ x: Double, _ y: Double) -> CGRect {
            CGRect(x: ox + x * s, y: oy + y * s, width: 4.5 * s, height: (20.0 - y) * s)
        }
        var p = Path()
        p.addRect(bar(3.5, 11))    // short
        p.addRect(bar(9.75, 4))    // tall
        p.addRect(bar(16, 8))      // mid
        return p
    }
}
