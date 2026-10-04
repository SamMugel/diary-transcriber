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
