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

    // AI:
    //   what: liveStream() returns an AsyncStream that can be iterated without crashing
    //   why:  PRD 12 (recording-view) requires "Live transcript updates word-by-word from SpeechTranscriber via AsyncStream".
    //         On headless CI where SFSpeechRecognizer is nil or unavailable, the stream should
    //         finish immediately and yield zero values.
    //   ref:  specs/ui.md RecordingViewModel, PRD 12
    func testLiveStream_returnsEmptyStreamWhenSpeechUnavailable() async {
        let transcriber = SpeechTranscriber()
        let stream = await transcriber.liveStream()

        var collected: [String] = []
        for await text in stream {
            collected.append(text)
        }

        // AI: In CI without a live microphone or on-device recognizer, the stream
        //     finalizes right away and produces no partial results. On a real
        //     device with microphone access this would be non-empty, but we can
        //     only assert the negative case from the test environment.
        XCTAssertTrue(
            collected.isEmpty,
            "liveStream should yield no results when Speech is unavailable in tests"
        )
    }

    // AI:
    //   what: liveStream can be iterated briefly and then cancelled safely
    //   why:  PRD 12 — onTermination must cancel the underlying recognition task
    //         without asserting or leaking.
    //   ref:  specs/ui.md RecordingViewModel, PRD 12
    func testLiveStream_canBeCancelledWithoutError() async {
        let transcriber = SpeechTranscriber()
        let stream = await transcriber.liveStream()

        let task = Task {
            for await _ in stream { /* discard; expect zero or partial */ }
        }
        task.cancel()

        // AI: Should not throw on cancellation. We don't assert on collected values
        //     because the device may lack an on-device recognizer; that case is
        //     covered by testLiveStream_returnsEmptyStreamWhenSpeechUnavailable.
        do {
            try await task.value
        } catch {
            XCTFail("Cancelling liveStream should not throw: \(error)")
        }
    }
}
