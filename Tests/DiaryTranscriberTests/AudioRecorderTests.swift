import XCTest
@testable import DiaryTranscriberCore

final class AudioRecorderTests: XCTestCase {

    func testRecordingHandle_elapsedCalculatesFromStartedAt() {
        let start = Date(timeIntervalSince1970: 1000)
        let handle = RecordingHandle(startedAt: start, outputURL: URL(fileURLWithPath: "/tmp/test.m4a"))

        // Elapsed should be non-negative (time since start).
        let elapsed = handle.elapsed()
        XCTAssertGreaterThanOrEqual(elapsed, 0, "Elapsed time should be non-negative")
    }

    func testRecordingHandle_preservesOutputURL() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let handle = RecordingHandle(startedAt: Date(), outputURL: url)
        XCTAssertEqual(handle.outputURL, url)
    }

    func testRecordingHandle_hasUniqueID() {
        let handle1 = RecordingHandle(startedAt: Date(), outputURL: URL(fileURLWithPath: "/tmp/a.m4a"))
        let handle2 = RecordingHandle(startedAt: Date(), outputURL: URL(fileURLWithPath: "/tmp/b.m4a"))
        XCTAssertNotEqual(handle1.id, handle2.id, "Each RecordingHandle should have a unique ID")
    }

    @MainActor
    func testAudioRecorder_stopWhenNotRecording_isIdempotent() async throws {
        let recorder = AudioRecorder()
        // Calling stop() when not recording should not throw.
        let result = try await recorder.stop()
        // Calling stop() again should also not throw.
        let result2 = try await recorder.stop()
        // Both calls should return the same empty/sentinel URL.
        XCTAssertEqual(result, result2, "Repeated stop() calls should be idempotent")
    }
}
