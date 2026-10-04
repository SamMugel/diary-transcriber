import XCTest
@testable import DiaryTranscriberCore

final class AudioRecorderTests: XCTestCase {

    func testRecordingHandle_elapsedApproximatesTimeSinceStart() {
        let start = Date().addingTimeInterval(-5)
        let handle = RecordingHandle(startedAt: start, outputURL: URL(fileURLWithPath: "/tmp/test.m4a"))

        // elapsed() uses Date() internally, so verify it's in the right ballpark.
        let elapsed = handle.elapsed()
        XCTAssertGreaterThan(elapsed, 4.0, "Elapsed should be at least ~5 seconds after a 5s-old start")
        XCTAssertLessThan(elapsed, 10.0, "Elapsed should be well under 10 seconds")
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
    func testAudioRecorder_stopWhenNotRecording_throwsNotRecording() async {
        let recorder = AudioRecorder()
        // Calling stop() when not recording must throw RecorderError.notRecording.
        do {
            _ = try await recorder.stop()
            XCTFail("stop() without start() should throw RecorderError.notRecording")
        } catch RecorderError.notRecording {
            // Expected.
        } catch {
            XCTFail("Expected RecorderError.notRecording but got: \(error)")
        }
    }
}
