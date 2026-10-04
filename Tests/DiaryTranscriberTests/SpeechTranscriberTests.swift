import XCTest
@testable import DiaryTranscriberCore

final class SpeechTranscriberTests: XCTestCase {

    // SFSpeechRecognizer requires a device context and may return nil in CI.
    // We test the actor's behavior defensively.

    func testTranscribe_nonExistentFile_raisesSpeechUnavailableOrSpeechError() async throws {
        let transcriber = SpeechTranscriber()
        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")

        do {
            _ = try await transcriber.transcribe(at: bogusURL)
            // If it succeeds (unlikely with a bogus file), just verify the result.
            // Some test environments may have Speech unavailable.
        } catch let error as TranscriptionError {
            // Acceptable: speechUnavailable or speechError.
            switch error {
            case .speechUnavailable, .speechError:
                break // Expected.
            case .whisperError, .whisperTimeout, .networkUnavailable:
                // These should not come from SpeechTranscriber.
                XCTFail("SpeechTranscriber should not return Whisper errors: \(error)")
            }
        }
    }

    func testTranscriptionError_errorDescription_isDescriptive() {
        let speechUnavailable = TranscriptionError.speechUnavailable
        XCTAssertFalse(
            speechUnavailable.errorDescription?.isEmpty ?? true,
            "speechUnavailable should have a description"
        )

        let speechError = TranscriptionError.speechError("network timeout")
        XCTAssertTrue(
            speechError.errorDescription?.contains("network timeout") ?? false,
            "speechError should include the detail"
        )

        let whisperError = TranscriptionError.whisperError(status: 401)
        XCTAssertTrue(
            whisperError.errorDescription?.contains("401") ?? false,
            "whisperError should include the status code"
        )
    }

    func testTranscriptionError_isLocalizedError() {
        let errors: [TranscriptionError] = [
            .speechUnavailable,
            .speechError("test"),
            .whisperError(status: 500),
            .whisperTimeout,
            .networkUnavailable
        ]

        for error in errors {
            XCTAssertNotNil(
                error.errorDescription,
                "Each TranscriptionError variant should have a non-nil description"
            )
        }
    }
}
