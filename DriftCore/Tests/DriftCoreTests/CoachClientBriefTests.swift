import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the coach-facing brief. The cloud call is Tier-3; this locks the
/// decode and the offline fallback — specifically that neither can put words in
/// a coach's mouth that the data doesn't support.
struct CoachClientBriefTests {

    @Test func decodesHeadlineWatchAndAsk() {
        let raw = #"""
        {"headline":"Training consistently but sleeping short.","watch":["Sleep under 6h all week"],"ask":["How's the lower back after Saturday?"]}
        """#
        let brief = CoachClientBrief.decode(raw)
        #expect(brief?.headline == "Training consistently but sleeping short.")
        #expect(brief?.watch == ["Sleep under 6h all week"])
        #expect(brief?.ask.first?.contains("lower back") == true)
    }

    /// The prompt caps these at 3; a model that ignores the cap must not turn
    /// the card into a wall a coach won't read.
    @Test func listsAreCappedAtThree() {
        let raw = #"""
        {"headline":"ok","watch":["a","b","c","d","e"],"ask":["1","2","3","4"]}
        """#
        let brief = CoachClientBrief.decode(raw)
        #expect(brief?.watch.count == 3)
        #expect(brief?.ask.count == 3)
    }

    @Test func aBriefWithNoHeadlineIsNoBrief() {
        #expect(CoachClientBrief.decode(#"{"headline":"","watch":["x"]}"#) == nil)
        #expect(CoachClientBrief.decode("sorry, I can't") == nil)
    }

    @Test func markdownFencedJSONStillDecodes() {
        let raw = "```json\n{\"headline\":\"Steady week.\",\"watch\":[],\"ask\":[]}\n```"
        #expect(CoachClientBrief.decode(raw)?.headline == "Steady week.")
    }

    // MARK: - Offline fallback

    /// Offline it reports only what the numbers say. Inventing coaching insight
    /// without a model would be worse than admitting there isn't any.
    @Test func offlineStatesTheNumbersAndNothingMore() {
        var metrics = BriefingMetrics()
        metrics.workoutsCompleted = 3
        metrics.avgSleepHours = 6.4
        metrics.avgProteinG = 118
        let briefing = ClientBriefing(clientID: "c", summary: "", notes: [], metrics: metrics)

        let brief = CoachClientBrief.offline(for: briefing)
        #expect(brief.headline.contains("3 workouts"))
        #expect(brief.headline.contains("6.4h"))
        #expect(brief.headline.contains("118g"))
        #expect(brief.ask.isEmpty, "offline never invents questions to ask")
    }

    @Test func offlineAdmitsWhenThereIsNothingToSay() {
        let briefing = ClientBriefing(clientID: "c", summary: "", notes: [],
                                      metrics: BriefingMetrics())
        #expect(CoachClientBrief.offline(for: briefing).headline
            .contains("Not enough shared"))
    }

    @Test func offlineSurfacesTheMostRecentNote() {
        let notes = [
            CoachNotes.Note(date: "2026-07-01", text: "Old news", kind: .moment),
            CoachNotes.Note(date: "2026-07-25", text: "Back sore again", kind: .moment),
        ]
        let briefing = ClientBriefing(clientID: "c", summary: "", notes: notes,
                                      metrics: BriefingMetrics())
        #expect(CoachClientBrief.offline(for: briefing).watch
            .contains { $0.contains("Back sore again") })
    }
}
