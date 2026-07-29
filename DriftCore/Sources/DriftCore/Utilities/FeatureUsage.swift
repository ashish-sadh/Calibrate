import Foundation

/// Feature usage counters. Historically a local-only UserDefaults tally shown
/// in Settings → Usage Insights (operator decision 2026-07-09, when Drift had
/// no backend and "friend feedback over telemetry" meant literally no
/// pipeline).
///
/// As of 2026-07-28 these route to `TelemetryService`: anonymous, aggregated
/// server-side, ON by default with an opt-out. The local tally is gone — it
/// only ever answered "what did *I* do on *this* phone", which never told us
/// what real users reach for. Tenet adjudication in `Docs/decisions.md`.
///
/// Kept as a thin façade rather than deleted so the call sites don't need to
/// know about outboxes or install ids.
public enum FeatureUsage {

    /// Record a usage event. Fire-and-forget: one local INSERT, flushed to the
    /// backend in batches. Never blocks the caller, never throws, no-ops when
    /// the user has opted out.
    public static func record(_ event: String) {
        // Screen views are high-volume and collapse to ONE event name with the
        // screen as a prop, so the server-side vocabulary stays closed.
        if event.hasPrefix("screen.") {
            TelemetryService.shared.event(
                TelemetryEvent.screenView,
                props: ["screen": String(event.dropFirst("screen.".count))])
        } else {
            TelemetryService.shared.event(event)
        }
    }
}
