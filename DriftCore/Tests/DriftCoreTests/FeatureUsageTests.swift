@testable import DriftCore
import Testing

/// Tier-0: deterministic on-device counter and export behavior.
@Suite(.serialized) struct FeatureUsageTests {
    @Test func recordAccumulatesAndSortsByCountThenName() {
        FeatureUsage.reset()
        defer { FeatureUsage.reset() }

        FeatureUsage.record("weight")
        FeatureUsage.record("food")
        FeatureUsage.record("weight")
        FeatureUsage.record("exercise")

        let usage = FeatureUsage.all()
        #expect(usage.map(\.event) == ["weight", "exercise", "food"])
        #expect(usage.map(\.count) == [2, 1, 1])
    }

    @Test func resetRemovesAllCounters() {
        FeatureUsage.reset()
        FeatureUsage.record("food")

        FeatureUsage.reset()

        #expect(FeatureUsage.all().isEmpty)
    }

    @Test func exportTextIncludesHeaderAndSortedRows() {
        FeatureUsage.reset()
        defer { FeatureUsage.reset() }

        FeatureUsage.record("log_weight")
        FeatureUsage.record("log_food")
        FeatureUsage.record("log_food")

        #expect(
            FeatureUsage.exportText()
                == "Drift usage (on-device counts)\n2\tlog_food\n1\tlog_weight"
        )
    }
}
