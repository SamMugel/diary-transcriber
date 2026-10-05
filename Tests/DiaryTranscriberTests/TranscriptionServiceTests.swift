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
}
