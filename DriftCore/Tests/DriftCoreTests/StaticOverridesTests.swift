import XCTest
@testable import DriftCore

/// Tier-0: deterministic StaticOverrides logic — no LLM, no network.
/// Covers containsWorkoutSetPattern, navigation routing, greeting/thanks,
/// bare-meal prompts, cheat-meal, barcode scan, copy-yesterday, and activity patterns.
@MainActor
final class StaticOverridesTests: XCTestCase {

    // MARK: - containsWorkoutSetPattern

    func testWorkoutPattern_setsFormat() {
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("3x10"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("4x8 bench press"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("bench press 5x5"))
    }

    func testWorkoutPattern_setsOfFormat() {
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("3 sets of 10"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("4 sets of 8 reps"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("bench 3 set of 12"))
    }

    func testWorkoutPattern_atWeight() {
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("@135"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("bench press @225"))
    }

    func testWorkoutPattern_atWeightWithUnit() {
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("squat at 135 lbs"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("deadlift at 100 kg"))
        XCTAssertTrue(StaticOverrides.containsWorkoutSetPattern("press at 60 pounds"))
    }

    func testWorkoutPattern_plainActivityNoPattern() {
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("yoga"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("i did yoga for 30 min"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("ran 5k"))
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern("went for a walk"))
    }

    func testWorkoutPattern_emptyString() {
        XCTAssertFalse(StaticOverrides.containsWorkoutSetPattern(""))
    }

    // MARK: - Greetings

    func testGreeting_hi() {
        let result = StaticOverrides.match("hi")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'hi'"); return
        }
        XCTAssertFalse(text.isEmpty)
    }

    func testGreeting_hello() {
        let result = StaticOverrides.match("hello")
        if case .response = result { } else {
            XCTFail("Expected .response for 'hello'")
        }
    }

    func testGreeting_hey() {
        let result = StaticOverrides.match("hey")
        if case .response = result { } else {
            XCTFail("Expected .response for 'hey'")
        }
    }

    func testGreeting_notMatchedForLongerPhrase() {
        // "hey what's my weight" should not match greeting
        let result = StaticOverrides.match("hey what's my weight")
        if case .response(let text) = result, text.contains("Ask about") {
            XCTFail("Greeting match should not fire for longer phrases")
        }
    }

    // MARK: - Thanks

    func testThanks_thanks() {
        let result = StaticOverrides.match("thanks")
        if case .response = result { } else {
            XCTFail("Expected .response for 'thanks'")
        }
    }

    func testThanks_cool() {
        let result = StaticOverrides.match("cool")
        if case .response = result { } else {
            XCTFail("Expected .response for 'cool'")
        }
    }

    func testThanks_okay() {
        let result = StaticOverrides.match("okay")
        if case .response = result { } else {
            XCTFail("Expected .response for 'okay'")
        }
    }

    // MARK: - Barcode scan

    func testBarcode_scanBarcode() {
        let result = StaticOverrides.match("scan barcode")
        guard case .uiAction(let action, _) = result else {
            XCTFail("Expected .uiAction for 'scan barcode'"); return
        }
        if case .openBarcodeScanner = action { } else {
            XCTFail("Expected .openBarcodeScanner action")
        }
    }

    func testBarcode_scan() {
        let result = StaticOverrides.match("scan")
        if case .uiAction(let action, _) = result,
           case .openBarcodeScanner = action { } else {
            XCTFail("Expected .uiAction(.openBarcodeScanner) for 'scan'")
        }
    }

    func testBarcode_scanFood() {
        let result = StaticOverrides.match("scan food")
        if case .uiAction(let action, _) = result,
           case .openBarcodeScanner = action { } else {
            XCTFail("Expected .uiAction(.openBarcodeScanner) for 'scan food'")
        }
    }

    // MARK: - Bare meal pattern

    func testBareMeal_logLunch() {
        let result = StaticOverrides.match("log lunch")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'log lunch'"); return
        }
        XCTAssertTrue(text.lowercased().contains("lunch"), "Response should mention 'lunch'")
    }

    func testBareMeal_trackBreakfast() {
        let result = StaticOverrides.match("track breakfast")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'track breakfast'"); return
        }
        XCTAssertTrue(text.lowercased().contains("breakfast"))
    }

    func testBareMeal_addDinner() {
        let result = StaticOverrides.match("add dinner")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'add dinner'"); return
        }
        XCTAssertTrue(text.lowercased().contains("dinner"))
    }

    func testBareMeal_logLunchWithFood_doesNotMatch() {
        // "log lunch chicken" has a food name — should NOT match bare-meal override
        let result = StaticOverrides.match("log lunch chicken")
        if case .response(let text) = result, text.contains("What did you have") {
            XCTFail("'log lunch chicken' should not fire the bare-meal prompt")
        }
    }

    // MARK: - Cheat meal

    func testCheatMeal_cheatMeal() {
        let result = StaticOverrides.match("cheat meal")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'cheat meal'"); return
        }
        XCTAssertFalse(text.isEmpty)
    }

    func testCheatMeal_ateOut() {
        let result = StaticOverrides.match("ate out today")
        if case .response = result { } else {
            XCTFail("Expected .response for 'ate out today'")
        }
    }

    func testCheatMeal_offTrack() {
        let result = StaticOverrides.match("went off plan")
        if case .response = result { } else {
            XCTFail("Expected .response for 'went off plan'")
        }
    }

    // MARK: - Copy yesterday

    func testCopyYesterday_copyYesterday() {
        let result = StaticOverrides.match("copy yesterday")
        if case .handler = result { } else {
            XCTFail("Expected .handler for 'copy yesterday'")
        }
    }

    func testCopyYesterday_sameAsYesterday() {
        let result = StaticOverrides.match("same as yesterday")
        if case .handler = result { } else {
            XCTFail("Expected .handler for 'same as yesterday'")
        }
    }

    func testCopyYesterday_confirmCopy() {
        let result = StaticOverrides.match("confirm copy")
        if case .handler = result { } else {
            XCTFail("Expected .handler for 'confirm copy'")
        }
    }

    // MARK: - Navigation

    func testNavigation_goToFood() {
        let result = StaticOverrides.match("go to food")
        guard case .uiAction(let action, _) = result else {
            XCTFail("Expected .uiAction for 'go to food'"); return
        }
        if case .navigate(let tab) = action {
            XCTAssertEqual(tab, 2, "Food tab should be tab 2")
        } else {
            XCTFail("Expected .navigate action")
        }
    }

    func testNavigation_openExercise() {
        let result = StaticOverrides.match("open exercise")
        guard case .uiAction(let action, _) = result else {
            XCTFail("Expected .uiAction for 'open exercise'"); return
        }
        if case .navigate(let tab) = action {
            XCTAssertEqual(tab, 3, "Exercise tab should be tab 3")
        } else {
            XCTFail("Expected .navigate action")
        }
    }

    func testNavigation_showMeMyWeight() {
        let result = StaticOverrides.match("show me my weight")
        guard case .uiAction(let action, _) = result else {
            XCTFail("Expected .uiAction for 'show me my weight'"); return
        }
        if case .navigate(let tab) = action {
            XCTAssertEqual(tab, 1, "Weight tab should be tab 1")
        } else {
            XCTFail("Expected .navigate action")
        }
    }

    func testNavigation_switchToSupplements() {
        let result = StaticOverrides.match("switch to supplements")
        guard case .uiAction(let action, _) = result else {
            XCTFail("Expected .uiAction for 'switch to supplements'"); return
        }
        if case .navigate(let tab) = action {
            XCTAssertEqual(tab, 4, "Supplements should be tab 4")
        } else {
            XCTFail("Expected .navigate action")
        }
    }

    func testNavigation_goToDashboard() {
        let result = StaticOverrides.match("go to dashboard")
        guard case .uiAction(let action, _) = result else {
            XCTFail("Expected .uiAction for 'go to dashboard'"); return
        }
        if case .navigate(let tab) = action {
            XCTAssertEqual(tab, 0, "Dashboard should be tab 0")
        } else {
            XCTFail("Expected .navigate action")
        }
    }

    func testNavigation_unknownTarget_returnsNil() {
        let result = StaticOverrides.match("go to unicorns")
        XCTAssertNil(result, "'go to unicorns' should fall through to LLM")
    }

    // MARK: - Emoji-only

    func testEmojiOnly_singleEmoji() {
        let result = StaticOverrides.match("😊")
        if case .response = result { } else {
            XCTFail("Single emoji should return a response")
        }
    }

    func testEmojiOnly_twoEmoji() {
        let result = StaticOverrides.match("😊👍")
        if case .response = result { } else {
            XCTFail("Two emoji should return a response")
        }
    }

    func testEmojiOnly_textWithEmoji_doesNotMatch() {
        // "log 🍎" has text + emoji — should not hit emoji-only path
        let result = StaticOverrides.match("log 🍎")
        if case .response(let text) = result, text == "What can I help you with?" {
            XCTFail("'log 🍎' is not emoji-only and should not match emoji override")
        }
    }

    func testEmojiOnly_bareDigitsDoNotMatch() {
        // Regression: Unicode marks ASCII digits as emoji (keycap bases), so
        // "1"/"2"/"3" wrongly hit the emoji-only override → "What can I help you
        // with?", swallowing meal-planning + clarification number picks. #multi-turn-fix
        for digit in ["1", "2", "3", "10"] {
            let result = StaticOverrides.match(digit)
            if case .response(let text) = result, text == "What can I help you with?" {
                XCTFail("bare '\(digit)' must NOT match the emoji-only override (it's a pick, not an emoji)")
            }
        }
        // True emoji-only still matches.
        if case .response(let text) = StaticOverrides.match("👍"), text == "What can I help you with?" {
            // expected
        } else {
            XCTFail("'👍' should still hit the emoji-only override")
        }
    }

    // MARK: - nil fall-through

    func testNilFallthrough_randomQuery() {
        let result = StaticOverrides.match("how much protein in chicken breast")
        // Should fall through to LLM — no static override
        XCTAssertNil(result, "Nutrition info query should fall through to LLM")
    }

    func testNilFallthrough_workoutLog() {
        let result = StaticOverrides.match("bench press 3x10 at 135")
        // Structured workout logging should fall through to LLM pipeline
        XCTAssertNil(result, "Structured workout log should fall through to LLM")
    }

    // MARK: - Interrogative guard (#902)

    /// Criterion 1: activity *questions* must NOT be logged as an activity
    /// named the question. "did I move/walk enough today?" → fall through to
    /// the agent (activity summary), NOT "Log I Move Enough Today?..." prompt.
    func testInterrogative_didIMoveEnough_doesNotLogActivity() {
        XCTAssertNil(StaticOverrides.match("did I move enough today?"),
                     "'did I move enough today?' is a question — must fall through to the agent, not log an activity")
    }

    func testInterrogative_didIWalkEnough_doesNotLogActivity() {
        XCTAssertNil(StaticOverrides.match("did I walk enough today?"),
                     "'did I walk enough today?' is a question — must fall through to the agent, not log an activity")
    }

    /// Criterion 2: interrogatives never trigger a log override (food/weight/activity).
    /// The last two would previously have matched quick-add-calories and
    /// body-comp respectively and silently written an entry.
    func testInterrogative_classNeverTriggersLogOverride() {
        let questions = [
            "did I move enough today?",
            "have I exercised enough this week?",
            "how much did I eat today?",
            "am I drinking enough water?",
            "did I eat 500 calories today?",   // would have matched quick-add cal
            "is my body fat 15?",              // would have matched body-comp
        ]
        for q in questions {
            XCTAssertNil(StaticOverrides.match(q),
                         "Interrogative '\(q)' must not trigger a static log/write override")
        }
    }

    /// Criterion 3: real log commands are unaffected (the guard is precise).
    /// "did yoga" is a bare-verb log, not a question, so it still produces the
    /// activity-confirmation prompt; "i walked 8000 steps"/"log a walk" still
    /// defer to the agent's log_activity (nil from StaticOverrides) — unchanged.
    func testInterrogative_realLogsNotBlocked() {
        guard case .response(let text)? = StaticOverrides.match("did yoga") else {
            XCTFail("'did yoga' is a log command — should still produce an activity confirmation"); return
        }
        XCTAssertTrue(text.lowercased().contains("yoga"), "Confirmation should name the activity")
        XCTAssertNil(StaticOverrides.match("i walked 8000 steps"),
                     "'i walked 8000 steps' defers to the agent (unchanged)")
        XCTAssertNil(StaticOverrides.match("log a walk"),
                     "'log a walk' defers to the agent (unchanged)")
    }
}
