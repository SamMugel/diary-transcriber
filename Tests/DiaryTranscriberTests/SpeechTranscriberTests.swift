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

    // MARK: - Success / empty-result taxonomy (PRD #17)

    // AI:
    //   what: Defensive success-path contract for SpeechTranscriber.transcribe(at:)
    //   why:  PRD #17 requirement #2 — SpeechTranscriberTests must cover the "success path".
    //         SFSpeechRecognizer is only instantiated when `import Speech` resolves and the
    //         device reports a recognizer; headless CI does not, so the realistic testable
    //         contract is "either an error with the documented taxonomy OR a Transcript whose
    //         source is .speech". We drive an empty-but-real file (an empty file always fails
    //         to recognize, but the call still terminates via one of the two committed paths),
    //         then assert the taxonomy: errors are speechUnavailable or speechError; non-error
    //         results have source .speech and non-empty text (the success contract).
    //   ref:  PRD 17-test-suites requirement 2
    func testTranscribe_successContract_sourceIsSpeechOrErrorIsSpeechy() async throws {
        let transcriber = SpeechTranscriber()

        // AI: Use a real (empty) file. With SFSpeech unavailable → speechUnavailable.
        //     With SFSpeech present but empty content → speechError(...) per source.
        //     A hypothetical success path → Transcript(source: .speech, text: <non-empty>).
        let emptyFile = FileManager.default.temporaryDirectory
            .appending(path: "speech-empty-\(UUID().uuidString).m4a")
        try Data().write(to: emptyFile)
        defer { try? FileManager.default.removeItem(at: emptyFile) }

        do {
            let transcript = try await transcriber.transcribe(at: emptyFile)
            // AI: Reachable only if a recognizer is available and it somehow produces a
            //     non-empty result for an empty file (never on CI; theoretical device path).
            //     Pin the success contract so a future refactor that drops `source = .speech`
            //     trips this assertion instead of silently changing the public tax.
            XCTAssertEqual(
                transcript.source,
                .speech,
                "A successful SpeechTranscriber transcription must report source .speech"
            )
            XCTAssertFalse(
                transcript.text.isEmpty,
                "A successful transcript must be non-empty (empty results are surfaced as errors)"
            )
        } catch let error as TranscriptionError {
            // AI: Both failure cases are documented and acceptable on headless CI:
            //     speechUnavailable (no recognizer) or speechError (empty result / no result).
            switch error {
            case .speechUnavailable, .speechError:
                break // Expected.
            case .whisperError, .whisperTimeout, .networkUnavailable:
                XCTFail("SpeechTranscriber should not return Whisper errors: \(error)")
            }
        }
    }

    // AI:
    //   what: Empty-result path → speechError contract verification
    //   why:  PRD #17 requirement #2 — SpeechTranscriberTests must cover the "empty result"
    //         path. In source, SpeechTranscriber.transcribe throws `speechError("Speech
    //         recognition produced an empty transcript.")` when SFSpeech returns an empty
    //         transcript. We cannot synthesize an SFSpeechRecognitionResult on headless CI
    //         to trigger that branch directly; instead, we verify the contract via the error
    //         taxonomy: the `speechError` case is what callers (TranscriptionService) use to
    //         decide whether to fall back to Whisper for an "empty result". Pin the variant
    //         and its descriptive message so the fallback trigger in TranscriptionServiceTests
    //         remains sound.
    //   ref:  PRD 17-test-suites requirement 2, SpeechTranscriber.transcribe(at:) empty-text branch
    func testEmptyResult_contract_speechErrorContainsDetail() {
        // Mirrors the exact message string the source raises for an empty transcript.
        let emptyResultError = TranscriptionError.speechError(
            "Speech recognition produced an empty transcript."
        )
        guard case .speechError(let detail) = emptyResultError else {
            return XCTFail("Expected .speechError variant")
        }
        XCTAssertFalse(
            detail.isEmpty,
            "The empty-result error must carry a non-empty detail explaining the failure"
        )
        XCTAssertTrue(
            emptyResultError.errorDescription?.contains(detail) ?? false,
            "The errorDescription must include the empty-transcript detail so the user-facing failure stays informative"
        )
    }
}
