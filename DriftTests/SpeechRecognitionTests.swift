import XCTest
@testable import Drift

@MainActor
final class SpeechRecognitionTests: XCTestCase {

    func testSharedInstance() {
        let service = SpeechRecognitionService.shared
        XCTAssertNotNil(service)
        XCTAssertEqual(service.recordingState, .idle)
        XCTAssertEqual(service.transcript, "")
        XCTAssertFalse(service.isRecording)
    }

    func testInitialStateIsIdle() {
        let service = SpeechRecognitionService.shared
        XCTAssertEqual(service.recordingState, .idle)
        XCTAssertFalse(service.isRecording)
    }

    func testTranscriptStartsEmpty() {
        let service = SpeechRecognitionService.shared
        XCTAssertTrue(service.transcript.isEmpty)
    }

    func testStopRecordingWhenIdle() {
        let service = SpeechRecognitionService.shared
        // Stopping when not recording should not crash or change state
        service.forceStop()
        XCTAssertEqual(service.recordingState, .idle)
    }

    func testRecordingStateEquatable() {
        let idle: SpeechRecognitionService.RecordingState = .idle
        let recording: SpeechRecognitionService.RecordingState = .recording
        let unavailable: SpeechRecognitionService.RecordingState = .unavailable("test")

        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(recording, .recording)
        XCTAssertEqual(unavailable, .unavailable("test"))
        XCTAssertNotEqual(idle, recording)
        XCTAssertNotEqual(unavailable, .unavailable("different"))
    }

    func testIsRecordingReflectsState() {
        let service = SpeechRecognitionService.shared
        // In idle state, isRecording should be false
        XCTAssertFalse(service.isRecording)
        // Note: actual recording requires hardware — tested manually on device
    }
}
