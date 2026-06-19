import XCTest
@testable import Drift

/// Serving-multiplier math for the combo editor: scales up AND down, floors,
/// and kills float drift. Regression for the "stuck at 1.5×, can't scale down"
/// bug. #serving-edit
final class ServingMultiplierStepperTests: XCTestCase {

    func testClampFloors() {
        XCTAssertEqual(ServingMultiplierStepper.clamp(0.1, min: 0.25), 0.25)
        XCTAssertEqual(ServingMultiplierStepper.clamp(-5, min: 0.25), 0.25)
        XCTAssertEqual(ServingMultiplierStepper.clamp(0, min: 0.25), 0.25)
    }

    func testClampKillsFloatDrift() {
        XCTAssertEqual(ServingMultiplierStepper.clamp(1.4999999, min: 0.25), 1.5)
        XCTAssertEqual(ServingMultiplierStepper.clamp(1.2, min: 0.25), 1.2, accuracy: 0.0001)
    }

    func testScalesDownToFloorAndUpUncapped() {
        // The bug: from 1.5 you couldn't step down. Now you can, to the floor.
        XCTAssertEqual(ServingMultiplierStepper.clamp(1.5 - 0.5, min: 0.25), 1.0)
        XCTAssertEqual(ServingMultiplierStepper.clamp(0.5 - 0.5, min: 0.25), 0.25)  // floored
        // And up with no cap.
        XCTAssertEqual(ServingMultiplierStepper.clamp(2.0 + 0.5, min: 0.25), 2.5)
        XCTAssertEqual(ServingMultiplierStepper.clamp(9.0 + 0.5, min: 0.25), 9.5)
    }

    func testFormatTrimsTrailingZeros() {
        XCTAssertEqual(ServingMultiplierStepper.format(1.0), "1")
        XCTAssertEqual(ServingMultiplierStepper.format(2.0), "2")
        XCTAssertEqual(ServingMultiplierStepper.format(1.5), "1.5")
        XCTAssertEqual(ServingMultiplierStepper.format(1.25), "1.25")
    }
}
