import XCTest
@testable import DriftCore

/// Tier-0 tests for AIActionParser — pure parsing logic, no LLM or DB.
/// Run: cd DriftCore && swift test --filter AIActionParserTests
final class AIActionParserTests: XCTestCase {

    // MARK: - Bracket actions: LOG_FOOD

    func testLogFood_nameOnly() {
        let (action, clean) = AIActionParser.parse("Sure! [LOG_FOOD: chicken curry]")
        guard case .logFood(let name, let amount) = action else {
            return XCTFail("Expected logFood, got \(action)")
        }
        XCTAssertEqual(name, "chicken curry")
        XCTAssertNil(amount)
        XCTAssertEqual(clean, "Sure!")
    }

    func testLogFood_withGrams() {
        let (action, _) = AIActionParser.parse("[LOG_FOOD: dal makhani 200g]")
        guard case .logFood(let name, let amount) = action else {
            return XCTFail("Expected logFood")
        }
        XCTAssertEqual(name, "dal makhani")
        XCTAssertEqual(amount, "200g")
    }

    func testLogFood_withMl() {
        let (action, _) = AIActionParser.parse("[LOG_FOOD: lassi 250ml]")
        guard case .logFood(let name, let amount) = action else {
            return XCTFail("Expected logFood")
        }
        XCTAssertEqual(name, "lassi")
        XCTAssertEqual(amount, "250ml")
    }

    func testLogFood_withServings() {
        let (action, _) = AIActionParser.parse("[LOG_FOOD: idli 3 pieces]")
        guard case .logFood(let name, let amount) = action else {
            return XCTFail("Expected logFood")
        }
        XCTAssertEqual(name, "idli")
        XCTAssertEqual(amount, "3 pieces")
    }

    func testLogFood_cleanTextStripped() {
        let (_, clean) = AIActionParser.parse("Logged your meal. [LOG_FOOD: paneer] Enjoy!")
        XCTAssertFalse(clean.contains("[LOG_FOOD"))
        XCTAssertFalse(clean.contains("paneer"))
    }

    // MARK: - Bracket actions: LOG_WEIGHT

    func testLogWeight_withUnit() {
        let (action, clean) = AIActionParser.parse("Great! [LOG_WEIGHT: 75.5 kg]")
        guard case .logWeight(let value, let unit) = action else {
            return XCTFail("Expected logWeight")
        }
        XCTAssertEqual(value, 75.5, accuracy: 0.001)
        XCTAssertEqual(unit, "kg")
        XCTAssertEqual(clean, "Great!")
    }

    func testLogWeight_defaultsToLbs() {
        let (action, _) = AIActionParser.parse("[LOG_WEIGHT: 165]")
        guard case .logWeight(let value, let unit) = action else {
            return XCTFail("Expected logWeight")
        }
        XCTAssertEqual(value, 165, accuracy: 0.001)
        XCTAssertEqual(unit, "lbs")
    }

    func testLogWeight_invalidValue_returnsNone() {
        let (action, _) = AIActionParser.parse("[LOG_WEIGHT: heavy]")
        guard case .none = action else {
            return XCTFail("Expected none for invalid weight, got \(action)")
        }
    }

    // MARK: - Bracket actions: CREATE_WORKOUT

    func testCreateWorkout_singleExercise() {
        let (action, clean) = AIActionParser.parse("Here you go! [CREATE_WORKOUT: Push Ups 3x15]")
        guard case .createWorkout(let exercises) = action else {
            return XCTFail("Expected createWorkout")
        }
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "Push Ups")
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].reps, 15)
        XCTAssertNil(exercises[0].weight)
        XCTAssertEqual(clean, "Here you go!")
    }

    func testCreateWorkout_withWeight() {
        let (action, _) = AIActionParser.parse("[CREATE_WORKOUT: Bench Press 3x10@135]")
        guard case .createWorkout(let exercises) = action else {
            return XCTFail("Expected createWorkout")
        }
        XCTAssertEqual(exercises[0].name, "Bench Press")
        XCTAssertEqual(exercises[0].weight ?? 0, 135, accuracy: 0.001)
    }

    func testCreateWorkout_multiple() {
        let (action, _) = AIActionParser.parse("[CREATE_WORKOUT: Squats 4x8@100, Pull Ups 3x10]")
        guard case .createWorkout(let exercises) = action else {
            return XCTFail("Expected createWorkout")
        }
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises[0].name, "Squats")
        XCTAssertEqual(exercises[1].name, "Pull Ups")
    }

    // MARK: - Bracket actions: START_WORKOUT

    func testStartWorkout_withType() {
        let (action, clean) = AIActionParser.parse("Starting now. [START_WORKOUT: Push Day]")
        guard case .startWorkout(let type) = action else {
            return XCTFail("Expected startWorkout")
        }
        XCTAssertEqual(type, "Push Day")
        XCTAssertEqual(clean, "Starting now.")
    }

    // MARK: - Bracket actions: SHOW_WEIGHT / SHOW_NUTRITION

    func testShowWeight() {
        let (action, clean) = AIActionParser.parse("Here's your data. [SHOW_WEIGHT]")
        guard case .showWeight = action else {
            return XCTFail("Expected showWeight")
        }
        XCTAssertEqual(clean, "Here's your data.")
    }

    func testShowNutrition() {
        let (action, clean) = AIActionParser.parse("[SHOW_NUTRITION] Check this out.")
        guard case .showNutrition = action else {
            return XCTFail("Expected showNutrition")
        }
        XCTAssertEqual(clean, "Check this out.")
    }

    // MARK: - No action

    func testNoAction_plainText() {
        let (action, clean) = AIActionParser.parse("Just a regular response.")
        guard case .none = action else {
            return XCTFail("Expected none")
        }
        XCTAssertEqual(clean, "Just a regular response.")
    }

    func testNoAction_emptyString() {
        let (action, _) = AIActionParser.parse("")
        guard case .none = action else {
            return XCTFail("Expected none for empty string")
        }
    }

    // MARK: - JSON tool call format

    func testJSONToolCall_logFood() {
        let json = """
        {"tool": "log_food", "params": {"name": "samosa", "amount": "2 pieces"}}
        """
        let (action, clean) = AIActionParser.parse(json)
        guard case .logFood(let name, let amount) = action else {
            return XCTFail("Expected logFood from JSON, got \(action)")
        }
        XCTAssertEqual(name, "samosa")
        XCTAssertEqual(amount, "2 pieces")
        XCTAssertTrue(clean.isEmpty || !clean.contains("{"))
    }

    func testJSONToolCall_searchFood() {
        let json = """
        Here's what I found. {"tool": "search_food", "params": {"query": "biryani"}}
        """
        let (action, _) = AIActionParser.parse(json)
        guard case .logFood(let name, _) = action else {
            return XCTFail("Expected logFood from search_food JSON")
        }
        XCTAssertEqual(name, "biryani")
    }

    func testJSONToolCall_logWeight() {
        let json = """
        {"tool": "log_weight", "params": {"value": "82.5", "unit": "kg"}}
        """
        let (action, _) = AIActionParser.parse(json)
        guard case .logWeight(let value, let unit) = action else {
            return XCTFail("Expected logWeight from JSON")
        }
        XCTAssertEqual(value, 82.5, accuracy: 0.001)
        XCTAssertEqual(unit, "kg")
    }

    func testJSONToolCall_startWorkout() {
        let json = """
        {"tool": "start_workout", "params": {"name": "Push Day"}}
        """
        let (action, _) = AIActionParser.parse(json)
        guard case .startWorkout(let type) = action else {
            return XCTFail("Expected startWorkout from JSON")
        }
        XCTAssertEqual(type, "Push Day")
    }

    func testJSONToolCall_unknownTool_returnsNone() {
        let json = """
        {"tool": "unknown_tool", "foo": "bar"}
        """
        let (action, _) = AIActionParser.parse(json)
        guard case .none = action else {
            return XCTFail("Expected none for unknown JSON tool")
        }
    }

    func testJSONToolCall_logFood_emptyName_returnsNone() {
        let json = """
        {"tool": "log_food", "params": {"name": ""}}
        """
        let (action, _) = AIActionParser.parse(json)
        guard case .none = action else {
            return XCTFail("Expected none for empty food name")
        }
    }

    // MARK: - parseWorkoutExercises

    func testParseWorkoutExercises_standard() {
        let exercises = AIActionParser.parseWorkoutExercises("Deadlift 4x5@200")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "Deadlift")
        XCTAssertEqual(exercises[0].sets, 4)
        XCTAssertEqual(exercises[0].reps, 5)
        XCTAssertEqual(exercises[0].weight ?? 0, 200, accuracy: 0.001)
    }

    func testParseWorkoutExercises_noWeight() {
        let exercises = AIActionParser.parseWorkoutExercises("Burpees 3x20")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "Burpees")
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].reps, 20)
        XCTAssertNil(exercises[0].weight)
    }

    func testParseWorkoutExercises_multiple() {
        let exercises = AIActionParser.parseWorkoutExercises("Push Ups 3x15, Dips 3x12, Pull Ups 3x8")
        XCTAssertEqual(exercises.count, 3)
        XCTAssertEqual(exercises[0].name, "Push Ups")
        XCTAssertEqual(exercises[1].name, "Dips")
        XCTAssertEqual(exercises[2].name, "Pull Ups")
    }

    func testParseWorkoutExercises_nameOnlyFallback() {
        let exercises = AIActionParser.parseWorkoutExercises("Yoga")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "Yoga")
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].reps, 10)
    }

    func testParseWorkoutExercises_empty() {
        let exercises = AIActionParser.parseWorkoutExercises("")
        XCTAssertTrue(exercises.isEmpty)
    }

    // Numbers-first phrasing — what the voice/text sheets prompt with
    // ("3x10 bench at 135") and what the Android local fallback receives.

    func testParseWorkoutExercises_numbersFirstWithAtWeight() {
        let exercises = AIActionParser.parseWorkoutExercises("3x10 bench at 135")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "bench")
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].reps, 10)
        XCTAssertEqual(exercises[0].weight ?? 0, 135, accuracy: 0.001)
    }

    func testParseWorkoutExercises_numbersFirstMultiple() {
        let exercises = AIActionParser.parseWorkoutExercises("3x10 bench at 135, 3x12 squats at 185")
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises[0].name, "bench")
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].reps, 10)
        XCTAssertEqual(exercises[0].weight ?? 0, 135, accuracy: 0.001)
        XCTAssertEqual(exercises[1].name, "squats")
        XCTAssertEqual(exercises[1].sets, 3)
        XCTAssertEqual(exercises[1].reps, 12)
        XCTAssertEqual(exercises[1].weight ?? 0, 185, accuracy: 0.001)
    }

    func testParseWorkoutExercises_numbersFirstNoWeight() {
        let exercises = AIActionParser.parseWorkoutExercises("3x10 lat raises")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "lat raises")
        XCTAssertEqual(exercises[0].sets, 3)
        XCTAssertEqual(exercises[0].reps, 10)
        XCTAssertNil(exercises[0].weight)
    }

    func testParseWorkoutExercises_unicodeTimesAndSpacedX() {
        let exercises = AIActionParser.parseWorkoutExercises("3×12 curls at 40, squats 5 x 5 at 225")
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises[0].name, "curls")
        XCTAssertEqual(exercises[0].reps, 12)
        XCTAssertEqual(exercises[0].weight ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(exercises[1].name, "squats")
        XCTAssertEqual(exercises[1].sets, 5)
        XCTAssertEqual(exercises[1].reps, 5)
        XCTAssertEqual(exercises[1].weight ?? 0, 225, accuracy: 0.001)
    }

    func testParseWorkoutExercises_nameFirstAtWeight() {
        let exercises = AIActionParser.parseWorkoutExercises("bench press 3x10 at 135")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "bench press")
        XCTAssertEqual(exercises[0].weight ?? 0, 135, accuracy: 0.001)
    }

    func testParseWorkoutExercises_numbersFirstNameContainingAtPhrase() {
        let exercises = AIActionParser.parseWorkoutExercises("3x10 rows at home")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].name, "rows at home")
        XCTAssertNil(exercises[0].weight)
    }

    func testParseWorkoutExercises_decimalWeight() {
        let exercises = AIActionParser.parseWorkoutExercises("Romanian Deadlift 3x12@67.5")
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].weight ?? 0, 67.5, accuracy: 0.001)
    }

    // MARK: - WorkoutExercise Equatable

    func testWorkoutExercise_equatable() {
        let a = AIActionParser.WorkoutExercise(name: "Squat", sets: 3, reps: 10, weight: 100)
        let b = AIActionParser.WorkoutExercise(name: "Squat", sets: 3, reps: 10, weight: 100)
        XCTAssertEqual(a, b)
    }
}
