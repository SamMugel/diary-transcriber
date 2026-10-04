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
}
