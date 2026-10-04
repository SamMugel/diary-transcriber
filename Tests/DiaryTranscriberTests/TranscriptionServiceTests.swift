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

        // Should produce at least one update — either failed or partial.
        XCTAssertFalse(updates.isEmpty, "Should produce at least one update")
    }

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
}
