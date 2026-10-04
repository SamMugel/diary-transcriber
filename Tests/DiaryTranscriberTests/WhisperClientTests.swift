import XCTest
@testable import DiaryTranscriberCore

final class WhisperClientTests: XCTestCase {

    func testInit_acceptsAPIKey() {
        // Verify the actor can be instantiated with any key string.
        _ = WhisperClient(apiKey: "test-key-123")
    }

    func testTranscribe_emptyAPIKey_throwsWhisperError401() async throws {
        let client = WhisperClient(apiKey: "")
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "whisper-test-\(UUID().uuidString).m4a")
        try "fake audio".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await client.transcribe(at: tempURL)
            XCTFail("Expected whisperError(401) for empty API key")
        } catch let error as TranscriptionError {
            switch error {
            case .whisperError(let status):
                XCTAssertEqual(status, 401, "Empty API key should trigger 401")
            default:
                XCTFail("Expected whisperError, got \(error)")
            }
        }
    }

    func testWhisperError_doesNotContainAPIKey() {
        let secretKey = "sk-super-secret-key-12345"
        let client = WhisperClient(apiKey: secretKey)

        // The client holds the API key internally but error messages must never expose it.
        // whisperError only includes the HTTP status code, never the key.
        let error = TranscriptionError.whisperError(status: 500)
        let desc = error.errorDescription ?? ""
        XCTAssertFalse(
            desc.contains(secretKey),
            "Error description must never contain the API key"
        )

        _ = client // Suppress unused warning.
    }

    func testTranscriptionError_whisperTimeout_hasDescription() {
        let error = TranscriptionError.whisperTimeout
        XCTAssertFalse(
            (error.errorDescription ?? "").isEmpty,
            "whisperTimeout should have a description"
        )
    }
}
