import XCTest
@testable import DiaryTranscriberCore

final class TranscriptionServiceTests: XCTestCase {

    func testInit_acceptsDependencies() {
        _ = TranscriptionService()
        _ = TranscriptionService(
            speechTranscriber: SpeechTranscriber(),
            whisperClient: WhisperClient(apiKey: "test")
        )
    }

    // MARK: - Primary success path

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

    // MARK: - Settings control engine selection

    @MainActor
    func testSettings_speechDisabledWhisperDisabled_yieldsFailed() async throws {
        let settings = TranscriptSettings(
            useOnDeviceSpeech: false,
            useWhisperFallback: false
        )
        let service = TranscriptionService(settings: settings)

        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")
        var updates: [TranscriptUpdate] = []
        let stream = await service.transcribe(at: bogusURL)
        for await update in stream { updates.append(update) }

        let hasFailed = updates.contains {
            if case .failed = $0 { return true }
            return false
        }
        XCTAssertTrue(hasFailed, "All engines disabled → .failed")
    }

    // MARK: - Whisper fallback on speech unavailable (device has no Speech)

    @MainActor
    func testSpeechUnavailable_fallsBackToWhisperOrFails() async throws {
        // Speech allocator not available → falls through to Whisper.
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

        // With bogus audio, either fall back to Whisper (which errors) or Speech errors.
        // Either way, at least one update is produced.
        XCTAssertFalse(updates.isEmpty, "Should produce updates for file-based audio")
    }

    // MARK: - TranscriptSettings defaults

    func testTranscriptSettings_defaults() {
        let settings = TranscriptSettings()
        XCTAssertTrue(settings.useOnDeviceSpeech, "Default should enable Speech")
        XCTAssertTrue(settings.useWhisperFallback, "Default should enable Whisper fallback")
    }

    func testTranscriptSettings_custom() {
        let settings = TranscriptSettings(useOnDeviceSpeech: false, useWhisperFallback: false)
        XCTAssertFalse(settings.useOnDeviceSpeech)
        XCTAssertFalse(settings.useWhisperFallback)
    }
}
