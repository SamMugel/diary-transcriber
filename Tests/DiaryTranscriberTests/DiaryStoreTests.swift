import XCTest
@testable import DiaryTranscriberCore

final class DiaryStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "DiaryStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Initialization

    func testInit_createsManifestIfAbsent() async throws {
        let store = DiaryStore(folder: tempDir)
        let entries = try await store.entries()
        XCTAssertTrue(entries.isEmpty, "New store should have no entries")
    }

    // MARK: - Append

    func testAppend_createsTranscriptAndMetadataFiles() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))

        try await store.append(entry: entry)

        // Audio file is NOT created by append() — it's written by the recorder.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDir.appending(path: entry.transcriptPath).path
            ),
            "Transcript file should exist after append"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDir.appending(path: "\(entry.audioPath.split(separator: ".").first ?? "").json").path
            ),
            "Per-entry metadata JSON should exist after append"
        )
    }

    func testAppend_entriesReturnedSortedNewestFirst() async throws {
        let store = DiaryStore(folder: tempDir)

        let older = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        let newer = makeEntry(startedAt: Date(timeIntervalSince1970: 1728000000))

        try await store.append(entry: older)
        try await store.append(entry: newer)

        let entries = try await store.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.id, newer.id, "Newest entry should be first")
    }

    // MARK: - Update

    func testUpdate_modifiesEntryInPlace() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        var modified = entry
        modified.source = .speech

        try await store.update(entry: modified)

        let entries = try await store.entries()
        XCTAssertEqual(entries.first?.source, .speech)
    }

    // MARK: - Delete

    func testDelete_removesFilesAndManifestRow() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        try await store.delete(id: entry.id)

        let entries = try await store.entries()
        XCTAssertTrue(entries.isEmpty, "Entry should be removed from manifest")

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDir.appending(path: entry.audioPath).path
            ),
            "Audio file should be deleted"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDir.appending(path: entry.transcriptPath).path
            ),
            "Transcript file should be deleted"
        )
    }

    // MARK: - URL resolution

    func testUrlFor_resolvesToAbsoluteURL() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))

        let resolved = await store.url(for: entry)
        XCTAssertTrue(resolved.scheme != nil, "URL should be absolute")
        XCTAssertTrue(
            resolved.path.contains(entry.audioPath),
            "Resolved URL should contain the audio path"
        )
    }

    // MARK: - Data

    func testData_returnsTranscriptAndMetadata() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        let data = try await store.data(for: entry)

        XCTAssertEqual(data.metadata.id, entry.id)
        XCTAssertEqual(data.transcriptText, "", "Initial transcript should be empty")
    }

    // MARK: - Concurrent safety

    func testConcurrentUpdates_doNotCorruptManifest() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    var modified = entry
                    modified.updatedAt = Date()
                    try? await store.update(entry: modified)
                }
            }
        }

        let entries = try await store.entries()
        XCTAssertEqual(entries.count, 1, "Concurrent updates should not duplicate entries")
    }

    // MARK: - setTranscript (PRD #18)

    // AI:
    //   what: setTranscript writes transcript text into the entry's `.md` and updates manifest
    //   why:  PRD #18 — the post-recording pipeline persists transcript text atomically; this test
    //         verifies both the on-disk `.md` content *and* the manifest's source/updatedAt mutation
    //         so neither side of the contract regresses silently.
    //   ref:  PRD 18-transcription-post-recording-pipeline, ISSUE-015
    func testSetTranscript_writesTextToMDFile() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        try await store.setTranscript(for: entry.id, source: .whisper, text: "Hello, world.")

        let transcriptURL = tempDir.appending(path: entry.transcriptPath)
        let text = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertEqual(text, "Hello, world.", "setTranscript should write the text to the .md file")
    }

    func testSetTranscript_updatesManifestSourceAndUpdatedAt() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        // Capture the on-disk updatedAt as committed by `append` (not the
        // fabrication-time `entry.updatedAt`, which may share Date() ticks
        // with setTranscript on a fast host). setTranscript's contract is to
        // never roll `updatedAt` backward — assert that, plus the stronger
        // signal: `source` actually changes from .none to .speech.
        let preEntries = try await store.entries()
        let preUpdated = preEntries.first(where: { $0.id == entry.id })
        let baselineUpdatedAt = preUpdated?.updatedAt ?? entry.updatedAt

        try await store.setTranscript(for: entry.id, source: .speech, text: "new text")

        let entries = try await store.entries()
        guard let updated = entries.first(where: { $0.id == entry.id }) else {
            return XCTFail("Entry should still be present after setTranscript")
        }
        XCTAssertEqual(updated.source, .speech, "Manifest source should be updated to .speech")
        XCTAssertGreaterThanOrEqual(updated.updatedAt, baselineUpdatedAt, "Manifest updatedAt should not roll backward past the pre-update value")
    }

    func testSetTranscript_unknownID_throwsEntryNotFound() async throws {
        let store = DiaryStore(folder: tempDir)
        // Don't append any entry.
        do {
            try await store.setTranscript(for: UUID(), source: .none, text: "ghost")
            XCTFail("setTranscript on unknown id should throw")
        } catch StoreError.entryNotFound {
            // Expected.
        }
    }

    func testSetTranscript_atomicWrite_doesNotCorruptOnValidInput() async throws {
        // Acceptance criterion #4: atomic writes (temp + rename) leave a consistent prior state.
        // Verify writing a large transcript round-trips through the .md file intact.
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)

        let largeText = String(repeating: "a", count: 5_000)
        try await store.setTranscript(for: entry.id, source: .whisper, text: largeText)

        let transcriptURL = tempDir.appending(path: entry.transcriptPath)
        let text = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertEqual(text.count, 5_000, "Large transcript should round-trip intact")
    }

    // MARK: - excerpt (PRD #27)

    // AI:
    //   what: DiaryStore.excerpt contract tests
    //   why:  PRD #27 — the timeline preview reads the first `length` chars of each entry's
    //         transcript. These tests pin the contract: bounded slice, empty for missing/empty,
    //         empty for `.none` source (no disk read for pending rows), and full text when the
    //         transcript is shorter than the requested length.
    //   ref:  PRD 27-timeline-excerpt

    func testExcerpt_returnsFirstNCharsOfTranscript() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)
        try await store.setTranscript(
            for: entry.id,
            source: .speech,
            text: "The quick brown fox jumps over the lazy dog."
        )

        let persisted = try await store.entries().first { $0.id == entry.id }!
        let excerpt = try await store.excerpt(for: persisted, length: 10)
        XCTAssertEqual(excerpt, "The quick ", "Should return the first 10 characters of the transcript")
    }

    func testExcerpt_defaultLengthIs120() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)
        // 200 chars → default length 120 should truncate.
        try await store.setTranscript(
            for: entry.id,
            source: .whisper,
            text: String(repeating: "x", count: 200)
        )

        let persisted = try await store.entries().first { $0.id == entry.id }!
        let excerpt = try await store.excerpt(for: persisted)
        XCTAssertEqual(excerpt.count, 120, "Default length should be 120 chars")
    }

    func testExcerpt_returnsFullTextWhenShorterThanLength() async throws {
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: entry)
        try await store.setTranscript(for: entry.id, source: .speech, text: "short")

        let persisted = try await store.entries().first { $0.id == entry.id }!
        let excerpt = try await store.excerpt(for: persisted, length: 120)
        XCTAssertEqual(excerpt, "short", "Should return full text when shorter than length")
    }

    func testExcerpt_returnsEmptyForMissingTranscript() async throws {
        // Entry is appended (creating an empty .md), but never receives text via setTranscript.
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        // append() writes an empty .md via writeTranscriptFile and stores source as .none.
        // Flip the source to .speech so excerpt does not short-circuit on the `.none` gate,
        // but do NOT call setTranscript — the .md remains empty.
        var withSource = entry
        withSource.source = .speech
        try await store.append(entry: entry)
        try await store.update(entry: withSource)

        let excerpt = try await store.excerpt(for: withSource, length: 120)
        XCTAssertEqual(excerpt, "", "Empty transcript should return empty excerpt")
    }

    func testExcerpt_returnsEmptyForNoneSourceWithoutReadingDisk() async throws {
        // `.none` source → excerpt must short-circuit to "" without requiring the file to exist.
        let store = DiaryStore(folder: tempDir)
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        // Do NOT append — no transcript file exists at all.
        let excerpt = try await store.excerpt(for: entry, length: 120)
        XCTAssertEqual(excerpt, "", ".none source should return empty excerpt without disk access")
    }

    // MARK: - Helpers

    private func makeEntry(startedAt: Date) -> DiaryEntry {
        let timestamp = ISO8601DateFormatter.format(startedAt)
        return DiaryEntry(
            id: UUID(),
            startedAt: startedAt,
            durationSeconds: 30.0,
            audioPath: "\(timestamp).m4a",
            transcriptPath: "\(timestamp).md",
            source: .none
        )
    }
}

private extension ISO8601DateFormatter {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        return formatter.string(from: date)
    }
}
