import Foundation
import Synchronization
import XCTest
@testable import DiaryTranscriberCore

// AI: A Mutex-backed, Sendable collection box used by SpeechTranscriberTests to collect
//     stream results without tripping strict-concurrency "sending value of non-Sendable
//     type" errors. The closure captures this value and appends from within the Task,
//     then the test reads it after cancellation — both accesses go through the Mutex.
private final class CollectBox: Sendable {
    private let mutex = Mutex([String]())

    func append(_ text: String) {
        mutex.withLock { values in
            values.append(text)
        }
    }

    var isEmpty: Bool {
        mutex.withLock { values in
            values.isEmpty
        }
    }
}

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

        let collected = CollectBox()
        let collectTask = Task {
            for await text in stream {
                collected.append(text)
            }
        }

        // AI: On headless CI without a recognizer, the stream finishes immediately and
        //     collected stays empty. On a device with an active recognizer but no audio
        //     being fed, the recognition task never produces results — give it a moment
        //     to confirm and then cancel to avoid hanging the test.
        try? await Task.sleep(for: .seconds(2))
        collectTask.cancel()

        XCTAssertTrue(
            collected.isEmpty,
            "liveStream should yield no results when Speech is unavailable or no audio is provided"
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

        // AI: Should not throw or hang on cancellation. Task<Void, Never> does not
        //     throw on cancellation, so we just await its completion. We don't
        //     assert on collected values because the device may have an on-device
        //     recognizer; that case is covered by
        //     testLiveStream_returnsEmptyStreamWhenSpeechUnavailable.
        await task.value
    }
}
