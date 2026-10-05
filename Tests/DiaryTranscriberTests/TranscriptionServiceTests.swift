import XCTest
@testable import DiaryTranscriberCore

final class TranscriptionServiceTests: XCTestCase {

    // MARK: - Primary bogus-file path

    @MainActor
    func testTranscribe_bogusFile_yieldsFailedOrPartial() async throws {
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test")
        )
        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: bogusURL)
        for await update in stream {
            updates.append(update)
        }

        XCTAssertFalse(updates.isEmpty, "Should produce at least one update")
    }

    // MARK: - No engines available → total failure path

    @MainActor
    func testTranscriptionService_noEnginesAvailable_yieldsFailed() async throws {
        let settings = TranscriptSettings(
            useOnDeviceSpeech: false,
            useWhisperFallback: false
        )
        let service = TranscriptionService(
            whisperClient: nil,
            settings: settings
        )

        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: bogusURL)
        for await update in stream {
            updates.append(update)
        }

        let hasFailed = updates.contains { update in
            if case .failed = update { return true }
            return false
        }
        XCTAssertTrue(hasFailed, "With no engines enabled, should yield .failed")
    }

    // MARK: - Whisper fallback on speech unavailable

    @MainActor
    func testSpeechUnavailable_fallsBackToWhisperOrFails() async throws {
        // When Speech is unavailable on the device, the service should fall through
        // to Whisper. With a bogus file, Whisper errors, but updates are still produced.
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test"),
            settings: TranscriptSettings(useOnDeviceSpeech: true, useWhisperFallback: true)
        )

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "ts-test-\(UUID().uuidString).m4a")
        try "placeholder audio".write(to: cacheDir, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: cacheDir)
        for await update in stream { updates.append(update) }

        XCTAssertFalse(updates.isEmpty, "Should produce updates for file-based audio")
    }

    // MARK: - Speech disabled, Whisper disabled (distinct from nil client)

    @MainActor
    func testTranscribe_speechDisabledWhisperDisabled_yieldsFailed() async throws {
        let settings = TranscriptSettings(
            useOnDeviceSpeech: false,
            useWhisperFallback: false
        )
        // Even with a whisperClient, settings disable both engines.
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test"),
            settings: settings
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appending(path: "ts-disabled-\(UUID().uuidString).m4a")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: tempFile)
        for await update in stream { updates.append(update) }

        let hasFailed = updates.contains {
            if case .failed = $0 { return true }
            return false
        }
        XCTAssertTrue(hasFailed, "With all engines disabled via settings, should yield .failed")
    }

    // MARK: - Fallback trigger conditions (PRD #17 acceptance criterion 2)

    // Verify all four PRD #08 fallback trigger conditions: empty text, low confidence /
    // short length (<50% expected length), Speech error, and >3× audio duration hang
    // protection. Tested via the DEBUG-seam decision function so the assertions are
    // deterministic on headless CI without a live SFSpeechRecognizer or network — the
    // real-failure integration surface is already covered by the bogus-file tests above.

    // Trigger #1: empty text → must fall back to Whisper.
    func testFallback_emptyText_triggersWhisperFallback() async throws {
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test")
        )

        let emptyTranscript = Transcript(
            text: "",
            confidence: 0.95,
            source: .speech,
            isFinal: true
        )

        // AI: shouldFallbackFromSpeech is `nonisolated` (pure, no actor-state access),
        //     so it returns Bool synchronously — no await required (awaited calls
        //     trigger a "no async operations" warning under -strict-concurrency=complete).
        let shouldFallback = service.shouldFallbackFromSpeech(
            transcript: emptyTranscript,
            audioDuration: 60
        )
        XCTAssertTrue(
            shouldFallback,
            "Speech returning empty text should trigger Whisper fallback"
        )
    }

    // Trigger #2a: low confidence (<50%) → must fall back. The "<50% expected length"
    // criterion captures both interrelated symptoms: a low-confidence pass.
    func testFallback_lowConfidence_triggersWhisperFallback() async throws {
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test")
        )

        let lowConfidenceTranscript = Transcript(
            // Length is generous relative to duration — only confidence is the signal.
            text: String(repeating: "a", count: 200),
            confidence: 0.4,
            source: .speech,
            isFinal: true
        )

        let shouldFallback = service.shouldFallbackFromSpeech(
            transcript: lowConfidenceTranscript,
            audioDuration: 60
        )
        XCTAssertTrue(
            shouldFallback,
            "Low confidence (<0.5) should trigger Whisper fallback"
        )
    }

    // Trigger #2b: transcript length is less than the expected minimum (~audioDuration*2)
    // → must fall back. Expected min for 60s audio = 120 chars; provide fewer.
    func testFallback_shortTranscript_triggersWhisperFallback() async throws {
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test")
        )

        let shortTranscript = Transcript(
            text: "hello world", // 11 chars; 60s of audio → expected minimum 120 chars
            confidence: 0.95,
            source: .speech,
            isFinal: true
        )

        let shouldFallback = service.shouldFallbackFromSpeech(
            transcript: shortTranscript,
            audioDuration: 60
        )
        XCTAssertTrue(
            shouldFallback,
            "Transcript shorter than the expected minimum should trigger Whisper fallback"
        )
    }

    // Trigger #2c (non-trigger): sufficiently long + confident transcript → no fallback.
    // Guards against a regression where every Speech pass falls back regardless of quality.
    func testFallback_confidentFullLengthTranscript_doesNotTriggerFallback() async throws {
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test")
        )

        let goodTranscript = Transcript(
            text: String(repeating: "x", count: 200), // 200 ≥ 120 expected for 60s audio
            confidence: 0.9,
            source: .speech,
            isFinal: true
        )

        let shouldFallback = service.shouldFallbackFromSpeech(
            transcript: goodTranscript,
            audioDuration: 60
        )
        XCTAssertFalse(
            shouldFallback,
            "High-confidence, sufficiently long transcription should NOT trigger fallback"
        )
    }

    // Trigger #4: 3× hang-protection threshold. Verifies the exact multiplier the
    // production pipeline enforces: `audioDuration * 3`, floored at 30s so brief
    // captures aren't held to an unreasonably small timeout. Testing the threshold
    // directly avoids depending on real elapsed time in CI.
    func testHangProtection_timeoutIsThreeTimesAudioDurationFlooredAt30s() async throws {
        // Typical short capture: 30s audio → 90s timeout.
        XCTAssertEqual(
            TranscriptionService.hangProtectionTimeoutSeconds(for: 30),
            90,
            "Hang timeout should be 3× the audio duration (30s audio → 90s timeout)"
        )

        // Long capture: 200s audio → 600s timeout.
        XCTAssertEqual(
            TranscriptionService.hangProtectionTimeoutSeconds(for: 200),
            600,
            "Hang timeout should scale with audio duration"
        )

        // Sub-floor: 5s audio → 30s floor (not 15s).
        XCTAssertEqual(
            TranscriptionService.hangProtectionTimeoutSeconds(for: 5),
            30,
            "Hang timeout should be floored at 30s for very short captures"
        )

        // Exactly at the floor (10s audio → 30s floor).
        XCTAssertEqual(
            TranscriptionService.hangProtectionTimeoutSeconds(for: 10),
            30,
            "10s audio → 30s timeout (the floor)"
        )
    }

    // MARK: - Trigger #3: Speech error surfaces to the pipeline

    // Speech errors flow through `runTranscription`'s `case .failure` branch. A bogus
    // file produces a Speech error in the realistic integration path; assert that the
    // pipeline yields at least one update (the fallback or failure message) rather than
    // dying silently, which is the contracted behavior on Speech error.
    @MainActor
    func testSpeechError_pipelineProducesAtLeastOneUpdate() async throws {
        let service = TranscriptionService(
            whisperClient: WhisperClient(apiKey: "test"),
            settings: TranscriptSettings(useOnDeviceSpeech: true, useWhisperFallback: false)
        )

        let bogusURL = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString).m4a")

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: bogusURL)
        for await update in stream { updates.append(update) }

        XCTAssertFalse(
            updates.isEmpty,
            "Body with a Speech error and no Whisper fallback should still emit at least one update (failed or partial)"
        )
    }

    // MARK: - Engine-mock tests (PRD #36)
    //
    // PRD #36 requires controllable mocks for SpeechTranscriber and WhisperClient so the
    // fallback-decision branches inside TranscriptionService.runTranscription are exercised
    // fully without touching SFSpeechRecognizer or the real OpenAI network. The mocks below
    // conform to SpeechTranscriberProtocol / WhisperClientProtocol (PRD #36's seam) and track
    // call counts so tests can assert exactly which engine ran and which didn't. The tests
    // assert: speech-only success, speech-empty → whisper fallback, speech-error → whisper
    // fallback, speech-disabled → whisper only, and both-failed → .failed with no .final.
    //
    // ref: PRD 36-transcription-service-tests acceptance criteria

    // AI:
    //   what: MockSpeechTranscriber — actor conforming to SpeechTranscriberProtocol for PRD #36
    //   why:  TranscriptionServiceTests must drive TranscriptionService with a controllable Speech
    //         engine that either succeeds with a deterministic Transcript (including an empty-text
    //         Transcript to exercise the empty-result fallback path) or throws, WITHOUT instantiating
    //         a real SFSpeechRecognizer. The mock tracks `transcribeCallCount` so PRD #36's
    //         "only Whisper runs" assertion can guard against a regression where Speech runs when
    //         it should not. `liveStream()` returns a trivially-finished stream — that API is
    //         unused by the TranscriptionService path under test.
    //   ref:  PRD 36-transcription-service-tests, SpeechTranscriberProtocol
    actor MockSpeechTranscriber: SpeechTranscriberProtocol {
        private let outcome: Outcome
        private var transcribeCallCount: Int = 0

        enum Outcome {
            /// `transcribe(at:)` returns the configured Transcript verbatim (contents may include
            /// empty text, low confidence, etc., exactly as a real pass would deliver).
            case success(Transcript)
            /// `transcribe(at:)` throws the configured error.
            case failure(Error)
        }

        init(outcome: Outcome) {
            self.outcome = outcome
        }

        func transcribe(at audioURL: URL) async throws -> Transcript {
            transcribeCallCount += 1
            switch outcome {
            case .success(let transcript):
                return transcript
            case .failure(let error):
                throw error
            }
        }

        func liveStream() async -> AsyncStream<String> {
            // Unused by TranscriptionService's transcribe(at:) path; return an empty stream.
            AsyncStream { continuation in continuation.finish() }
        }

        /// Exposed so PRD #36 tests can assert that Speech ran or did not run.
        func callCount() async -> Int {
            transcribeCallCount
        }
    }

    // AI:
    //   what: MockWhisperClient — actor conforming to WhisperClientProtocol for PRD #36
    //   why:  TranscriptionServiceTests must drive TranscriptionService's Whisper fallback path
    //         with a controllable client that either succeeds with a deterministic Transcript or
    //         throws, WITHOUT issuing a real URLSession POST to api.openai.com. The mock tracks
    //         `transcribeCallCount` so the "Whisper.transcribe is never called" assertion (PRD #36
    //         testSpeechSucceeds_NoWhisperFallback) can guard against a regression where Speech
    //         success still falls through to Whisper.
    //   ref:  PRD 36-transcription-service-tests, WhisperClientProtocol
    actor MockWhisperClient: WhisperClientProtocol {
        private let outcome: Outcome
        private var transcribeCallCount: Int = 0

        enum Outcome {
            /// `transcribe(at:)` returns the configured Transcript verbatim.
            case success(Transcript)
            /// `transcribe(at:)` throws the configured error.
            case failure(Error)
        }

        init(outcome: Outcome) {
            self.outcome = outcome
        }

        func transcribe(at audioURL: URL) async throws -> Transcript {
            transcribeCallCount += 1
            switch outcome {
            case .success(let transcript):
                return transcript
            case .failure(let error):
                throw error
            }
        }

        /// Exposed so PRD #36 tests can assert the exact number of Whisper invocations.
        func callCount() async -> Int {
            transcribeCallCount
        }
    }

    // AI:
    //   what: Test fixture audio URL helper
    //   why:  TranscriptionService.estimateAudioDuration reads the file size to compute hang-
    //         protection timeout; mocks return synchronously regardless of file existence, but a
    //         real temp file keeps estimateAudioDuration deterministic (returns a real size → a
    //         real floor-clamped timeout) rather than relying on its 60s default for a missing
    //         file. Also matches the production call path where AudioRecorder writes a real .m4a.
    private func makeTempAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ts-mock-\(UUID().uuidString).m4a")
        try "mock audio bytes".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Speech success → no Whisper fallback

    // AI: PRD #36 testSpeechSucceeds_NoWhisperFallback — mock Speech success with a confident,
    //     non-empty transcript; assert Whisper.transcribe is never called (call-count mock),
    //     a .final update is emitted, and its source is .speech. Guards against a regression
    //     where Speech success still falls through to Whisper.
    @MainActor
    func testSpeechSucceeds_NoWhisperFallback() async throws {
        let speechTranscript = Transcript(
            text: "Good evening, diary entry.",
            confidence: 0.9,
            source: .speech,
            isFinal: true
        )
        let speech = MockSpeechTranscriber(outcome: .success(speechTranscript))
        let whisper = MockWhisperClient(outcome: .success(Transcript(
            text: "would only see this if Speech fell through",
            confidence: nil,
            source: .whisper,
            isFinal: true
        )))

        let service = TranscriptionService(
            speechTranscriber: speech,
            whisperClient: whisper,
            settings: TranscriptSettings(useOnDeviceSpeech: true, useWhisperFallback: true)
        )

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: audioURL)
        for await update in stream { updates.append(update) }

        // AI: Whisper must never be invoked when Speech succeeds with a high-confidence,
        //     non-empty transcript that exceeds the length-sanity threshold for a real-duration capture.
        let whisperCalls = await whisper.callCount()
        XCTAssertEqual(whisperCalls, 0, "Whisper must not run when Speech succeeds")

        let speechCalls = await speech.callCount()
        XCTAssertEqual(speechCalls, 1, "Speech must run exactly once on the success path")

        let final = updates.first { update in
            if case .final = update { return true } else { return false }
        }
        guard case .final(let transcript) = final else {
            XCTFail("Expected a .final update on Speech-only success; updates: \(updates)")
            return
        }
        XCTAssertEqual(
            transcript.source,
            .speech,
            "Final source must be .speech on the Speech-only success path"
        )
        XCTAssertEqual(
            transcript.text,
            speechTranscript.text,
            "Final transcript text must match the Speech engine's output verbatim"
        )
    }

    // MARK: - Speech returns empty → Whisper fallback

    // AI: PRD #36 testWhisperFallback_WhenSpeechReturnsEmpty — mock Speech returning an empty-text
    //     Transcript (the empty-result fallback trigger in shouldFallbackFromSpeech); assert Whisper
    //     runs, the final source is .whisper, and the final text matches Whisper's output. Guards
    //     against a regression where an empty Speech result is persisted as a .final speech transcript
    //     instead of falling back.
    @MainActor
    func testWhisperFallback_WhenSpeechReturnsEmpty() async throws {
        let speech = MockSpeechTranscriber(outcome: .success(Transcript(
            text: "",
            confidence: 0.95,
            source: .speech,
            isFinal: true
        )))
        let whisperTranscript = Transcript(
            text: "Whisper recovered the transcript.",
            confidence: nil,
            source: .whisper,
            isFinal: true
        )
        let whisper = MockWhisperClient(outcome: .success(whisperTranscript))

        let service = TranscriptionService(
            speechTranscriber: speech,
            whisperClient: whisper,
            settings: TranscriptSettings(useOnDeviceSpeech: true, useWhisperFallback: true)
        )

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: audioURL)
        for await update in stream { updates.append(update) }

        let whisperCalls = await whisper.callCount()
        XCTAssertEqual(whisperCalls, 1, "Whisper must run once when Speech returns empty text")

        let final = updates.first { update in
            if case .final = update { return true } else { return false }
        }
        guard case .final(let transcript) = final else {
            XCTFail("Expected a .final update on the Whisper fallback path; updates: \(updates)")
            return
        }
        XCTAssertEqual(
            transcript.source,
            .whisper,
            "Final source must be .whisper when Speech returned empty text"
        )
        XCTAssertEqual(
            transcript.text,
            whisperTranscript.text,
            "Final transcript text must match Whisper's output on the fallback path"
        )
    }

    // MARK: - Speech throws → Whisper fallback

    // AI: PRD #36 testWhisperFallback_WhenSpeechFails — mock Speech throwing a TranscriptionError
    //     (speechError); assert Whisper is invoked, the final source is .whisper, and the final text
    //     matches Whisper's output. Guards against a regression where a Speech failure short-circuits
    //     the Whisper fallback or persists a .failed instead of the recovered Whisper transcript.
    @MainActor
    func testWhisperFallback_WhenSpeechFails() async throws {
        let speech = MockSpeechTranscriber(outcome: .failure(
            TranscriptionError.speechError("simulated recognizer failure")
        ))
        let whisperTranscript = Transcript(
            text: "Whisper took over after Speech failure.",
            confidence: nil,
            source: .whisper,
            isFinal: true
        )
        let whisper = MockWhisperClient(outcome: .success(whisperTranscript))

        let service = TranscriptionService(
            speechTranscriber: speech,
            whisperClient: whisper,
            settings: TranscriptSettings(useOnDeviceSpeech: true, useWhisperFallback: true)
        )

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: audioURL)
        for await update in stream { updates.append(update) }

        let whisperCalls = await whisper.callCount()
        XCTAssertEqual(whisperCalls, 1, "Whisper must run once when Speech throws")

        let final = updates.first { update in
            if case .final = update { return true } else { return false }
        }
        guard case .final(let transcript) = final else {
            XCTFail("Expected a .final update on the Speech-failure fallback path; updates: \(updates)")
            return
        }
        XCTAssertEqual(
            transcript.source,
            .whisper,
            "Final source must be .whisper when Speech threw and Whisper recovered"
        )
        XCTAssertEqual(
            transcript.text,
            whisperTranscript.text,
            "Final transcript text must match Whisper's output after Speech failure"
        )
    }

    // MARK: - Speech disabled → Whisper only

    // AI: PRD #36 testWhisperOnly_WhenSpeechDisabled — set useOnDeviceSpeech=false; assert Speech
    //     is never called, Whisper runs, and the final source is .whisper. Guards against a
    //     regression where the Speech branch runs even when the user has disabled on-device speech
    //     in Settings (privacy-sensitive recordings).
    @MainActor
    func testWhisperOnly_WhenSpeechDisabled() async throws {
        let speech = MockSpeechTranscriber(outcome: .success(Transcript(
            text: "would only see this if Speech ran while disabled",
            confidence: 0.9,
            source: .speech,
            isFinal: true
        )))
        let whisperTranscript = Transcript(
            text: "Whisper-only transcript.",
            confidence: nil,
            source: .whisper,
            isFinal: true
        )
        let whisper = MockWhisperClient(outcome: .success(whisperTranscript))

        let service = TranscriptionService(
            speechTranscriber: speech,
            whisperClient: whisper,
            settings: TranscriptSettings(useOnDeviceSpeech: false, useWhisperFallback: true)
        )

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: audioURL)
        for await update in stream { updates.append(update) }

        let speechCalls = await speech.callCount()
        XCTAssertEqual(speechCalls, 0, "Speech must not run when useOnDeviceSpeech is false")

        let whisperCalls = await whisper.callCount()
        XCTAssertEqual(whisperCalls, 1, "Whisper must run exactly once when Speech is disabled")

        let final = updates.first { update in
            if case .final = update { return true } else { return false }
        }
        guard case .final(let transcript) = final else {
            XCTFail("Expected a .final update on the Whisper-only path; updates: \(updates)")
            return
        }
        XCTAssertEqual(
            transcript.source,
            .whisper,
            "Final source must be .whisper when on-device speech is disabled"
        )
    }

    // MARK: - Both engines fail → .failed emitted, no .final

    // AI: PRD #36 testBothFailed_FailedUpdateEmitted — mock Speech throwing and Whisper throwing;
    //     assert a .failed update is emitted, no .final update is emitted, and Whisper was invoked
    //     (the Speech failure triggered the fallback). Guards against a regression where total
    //     failure yields an empty stream (silent hang) or a spurious .final.
    @MainActor
    func testBothFailed_FailedUpdateEmitted() async throws {
        let speech = MockSpeechTranscriber(outcome: .failure(
            TranscriptionError.speechError("simulated recognizer failure")
        ))
        let whisper = MockWhisperClient(outcome: .failure(
            TranscriptionError.whisperError(status: 503)
        ))

        let service = TranscriptionService(
            speechTranscriber: speech,
            whisperClient: whisper,
            settings: TranscriptSettings(useOnDeviceSpeech: true, useWhisperFallback: true)
        )

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: audioURL)
        for await update in stream { updates.append(update) }

        let whisperCalls = await whisper.callCount()
        XCTAssertEqual(whisperCalls, 1, "Whisper must run once when Speech fails (before both fail)")

        let hasFinal = updates.contains { update in
            if case .final = update { return true } else { return false }
        }
        XCTAssertFalse(hasFinal, "Both engines failing must NOT yield a .final update")

        let failedMessage = updates.first { update in
            if case .failed = update { return true } else { return false }
        }
        guard case .failed(let message) = failedMessage else {
            XCTFail("Expected a .failed update when both engines fail; updates: \(updates)")
            return
        }
        XCTAssertFalse(
            message.isEmpty,
            "The .failed message must be non-empty so the user-facing failure stays informative"
        )
    }
}
