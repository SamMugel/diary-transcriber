import XCTest
@testable import DiaryTranscriberCore

final class CoreModelTests: XCTestCase {

    // MARK: - DiaryEntry

    func testDiaryEntry_roundTripsJSON_noDataLoss() throws {
        let entry = DiaryEntry(
            id: UUID(uuidString: "8f6c1b2a-3f4d-4e9c-b8a7-2a1c3f4e5d60")!,
            startedAt: ISO8601DateFormatter().date(from: "2026-10-03T09:05:00Z")!,
            durationSeconds: 124.7,
            audioPath: "2026-10-03-0905.m4a",
            transcriptPath: "2026-10-03-0905.md",
            source: .speech,
            createdAt: ISO8601DateFormatter().date(from: "2026-10-03T09:07:15Z")!,
            updatedAt: ISO8601DateFormatter().date(from: "2026-10-03T09:07:15Z")!
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(DiaryEntry.self, from: data)

        XCTAssertEqual(decoded, entry, "DiaryEntry should round-trip with no data loss")
    }

    func testDiaryEntry_defaultUpdatedAt_equalsCreatedAt() {
        let createdAt = ISO8601DateFormatter().date(from: "2026-10-03T09:07:15Z")!
        let entry = DiaryEntry(
            startedAt: createdAt,
            durationSeconds: 0,
            audioPath: "test.m4a",
            transcriptPath: "test.md",
            createdAt: createdAt
        )
        XCTAssertEqual(entry.updatedAt, createdAt, "updatedAt should default to createdAt")
    }

    // MARK: - TranscriptSource

    func testTranscriptSource_encodesAsLowercaseString() throws {
        let cases: [TranscriptSource] = [.speech, .whisper, .none]
        for source in cases {
            let data = try JSONEncoder().encode(source)
            let json = String(decoding: data, as: UTF8.self)
            let expected = "\"\(source.rawValue)\""
            XCTAssertEqual(json, expected, "Expected lowercase \"\(source.rawValue)\", got \(json)")
        }
    }

    func testTranscriptSource_decodesFromLowercaseString() throws {
        let cases: [(String, TranscriptSource)] = [
            ("\"speech\"", .speech),
            ("\"whisper\"", .whisper),
            ("\"none\"", .none),
        ]
        for (json, expected) in cases {
            let source = try JSONDecoder().decode(TranscriptSource.self, from: Data(json.utf8))
            XCTAssertEqual(source, expected)
        }
    }

    // MARK: - Transcript

    func testTranscript_roundTripsJSON_noDataLoss() throws {
        let transcript = Transcript(
            text: "Hello, world.",
            confidence: 0.95,
            source: .speech,
            isFinal: true
        )

        let data = try JSONEncoder().encode(transcript)
        let decoded = try JSONDecoder().decode(Transcript.self, from: data)
        XCTAssertEqual(decoded, transcript)
    }

    func testTranscript_confidenceDefaultsToNilWhenAbsent() throws {
        let json = #"{"text":"Hi","source":"none","isFinal":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Transcript.self, from: json)
        XCTAssertNil(decoded.confidence, "Optional confidence should default to nil when absent")
    }

    // MARK: - TranscriptUpdate

    func testTranscriptUpdate_partialHoldsText() {
        let update = TranscriptUpdate.partial("Hello")
        if case let .partial(text) = update {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected .partial case")
        }
    }

    func testTranscriptUpdate_finalHoldsTranscript() {
        let transcript = Transcript(text: "Hello, world.", source: .speech, isFinal: true)
        let update = TranscriptUpdate.final(transcript)
        if case let .final(t) = update {
            XCTAssertEqual(t.text, "Hello, world.")
        } else {
            XCTFail("Expected .final case")
        }
    }

    func testTranscriptUpdate_failedHoldsMessage() {
        let update = TranscriptUpdate.failed("network error")
        if case let .failed(msg) = update {
            XCTAssertEqual(msg, "network error")
        } else {
            XCTFail("Expected .failed case")
        }
    }
}
