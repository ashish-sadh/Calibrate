import Foundation

/// The visible X window of the Body-tab weight chart.
///
/// The range chips (1W/1M/3M/…) set a **window**, they do not filter the data:
/// the plot always carries the whole series, and the window is anchored at the
/// LAST data point rather than at `Date()`. That anchoring is what makes an
/// empty chart structurally impossible — a weekly weigher tapping `1W` gets the
/// seven days ending at their last weigh-in, not a blank card because nothing
/// happened since Monday (#1220).
///
/// Extracted from the arithmetic `WeightChartView` performs inline on iOS
/// (`visibleSeconds` / `paddedLastChartDate` / `anchorScrollToLatest`) so the
/// Android Path chart, which has no `chartXVisibleDomain` to lean on, resolves
/// the identical window and is Tier-0 testable.
public enum WeightChartWindow {

    public struct Window: Equatable, Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        public var seconds: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Trailing breathing room past the last weigh-in, as a fraction of the
    /// window — without it the "you are here" dot sits ON the clip edge.
    public static let trailingPadFraction: Double = 0.04

    /// Narrowest window a chip may resolve to. A one-point-per-week series on
    /// `1W` would otherwise collapse to a hairline.
    public static let minimumSeconds: TimeInterval = 7 * 86_400

    /// - Parameters:
    ///   - firstDate: earliest plotted point.
    ///   - lastDate: latest plotted point.
    ///   - rangeStart: the chip's cutoff (`nil` = All).
    public static func resolve(firstDate: Date, lastDate: Date, rangeStart: Date?) -> Window {
        let total = max(86_400, lastDate.timeIntervalSince(firstDate))
        let visible: TimeInterval
        if let rangeStart {
            visible = min(total, max(minimumSeconds, lastDate.timeIntervalSince(rangeStart)))
        } else {
            visible = total
        }
        let paddedLast = lastDate.addingTimeInterval(visible * trailingPadFraction)
        return Window(start: paddedLast.addingTimeInterval(-visible), end: paddedLast)
    }
}
