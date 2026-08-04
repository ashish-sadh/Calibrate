import Testing
@testable import DriftCore

/// The level→liblog priority mapping `PlainLogger` hands to
/// `__android_log_write` on Android (#1081). Wrong numbers here mean logs land
/// at the wrong severity and get filtered out of `adb logcat` silently.
struct AndroidLogPriorityTests {
    @Test func driftLevelsMapToAndroidLogPriorities() {
        #expect(AndroidLogPriority.priority(for: "debug") == 3)
        #expect(AndroidLogPriority.priority(for: "info") == 4)
        #expect(AndroidLogPriority.priority(for: "warning") == 5)
        #expect(AndroidLogPriority.priority(for: "error") == 6)
        #expect(AndroidLogPriority.priority(for: "fault") == 7)
    }

    @Test func unknownLevelFallsBackToInfo() {
        #expect(AndroidLogPriority.priority(for: "trace") == 4)
        #expect(AndroidLogPriority.priority(for: "") == 4)
        #expect(AndroidLogPriority.priority(for: "INFO") == 4)
    }
}
