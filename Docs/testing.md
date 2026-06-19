# Testing Guide

> **How testing works — the 5-tier map, which command to run for what, AI eval,
> coverage, and the `DriftChatSim` chat simulator — lives in
> [`Docs/development-sop.md`](development-sop.md) §3–§5.** This file keeps only
> the test-authoring patterns and simulator utilities.

## Ground rules (recap)
- **Never run two `xcodebuild test` in parallel** — they deadlock on the
  simulator. `pkill -9 -f xcodebuild; sleep 2` first.
- **One tier per file** (Tier 0 pure-logic vs Tier 3 LLM-backed never mix).
- DriftCore pure logic → `cd DriftCore && swift test` (~2s warm). iOS UI/HealthKit
  → the `Drift` scheme on a simulator. Real-model eval → `DriftLLMEvalMacOS` on
  macOS (the old iOS `DriftLLMEvalTests` target was removed — it skipped silently).

## Test patterns

```swift
// Tier 0 — DB test (isolated in-memory DB)
@Test func myTest() async throws {
    let db = try AppDatabase.empty()
    // ... exercise db, assert
}

// Tier 0 — pure logic
@Test func calculationTest() {
    #expect(MyService.calculate(input: 42) == expected)
}

// Tier 0 — precision/eval pattern (gold set, no LLM)
func testFoodIntents() {
    let cases = ["log 2 eggs", "ate chicken", /* ... */]
    let detected = cases.filter { parseFoodIntent($0) != nil }.count
    XCTAssertGreaterThanOrEqual(Double(detected) / Double(cases.count), 0.85)
}
```

Fixtures travel with their test target (`resources: [.process("Fixtures")]` +
`Bundle.module` for SwiftPM; dir-globbed for `DriftTests`). Assert non-empty in
setup so an orphaned fixture fails loudly instead of silently testing nothing.

## Reproducing chat/AI bugs

Use `DriftChatSim` to drive the real pipeline over a seeded DB and see per-turn
routing — far faster than rebuilding the app. See SOP §5 and
`DriftCore/Sources/DriftChatSim/README.md`.

## Simulator utilities

```bash
# Install + launch the built app on the simulator
APP=$(find ~/Library/Developer/Xcode/DerivedData/Drift-*/Build/Products/Debug-iphonesimulator/Drift.app -maxdepth 0 | head -1)
xcrun simctl install "iPhone 17 Pro" "$APP"
xcrun simctl launch "iPhone 17 Pro" com.drift.health

# Screenshot
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/drift_screenshot.png
```
