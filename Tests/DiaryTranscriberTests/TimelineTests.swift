import XCTest
@testable import DiaryTranscriberCore

final class TimelineTests: XCTestCase {

    @MainActor
    func testListViewModel_acceptsEmptyStore() async {
        let vm = ListViewModel()
        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 0)
    }

    @MainActor
    func testListViewModel_entriesSortedNewestFirst() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "timeline-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let older = DiaryEntry(
            startedAt: Date().addingTimeInterval(-3600),
            durationSeconds: 60,
            audioPath: "a.m4a",
            transcriptPath: "a.md",
            source: .speech
        )
        let newer = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "b.m4a",
            transcriptPath: "b.md",
            source: .whisper
        )

        try await store.append(entry: older)
        try await store.append(entry: newer)

        let vm = ListViewModel(store: store)
        await vm.refresh()

        XCTAssertEqual(vm.entries.count, 2, "Should have 2 entries")
        XCTAssertEqual(vm.entries[0].id, newer.id, "Newest entry should be first")
        XCTAssertEqual(vm.entries[1].id, older.id, "Oldest entry should be second")
    }

    @MainActor
    func testListViewModel_refreshUpdatesEntries() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "timeline-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ListViewModel(store: store)
        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 0)

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 30,
            audioPath: "test.m4a",
            transcriptPath: "test.md",
            source: .none
        )
        try await store.append(entry: entry)

        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 1, "Refresh should pick up new entries")
    }

    @MainActor
    func testListViewModel_isRecordingToggle() {
        let vm = ListViewModel()
        XCTAssertFalse(vm.isRecording)
        vm.startRecording()
        XCTAssertTrue(vm.isRecording)
        vm.cancelRecording()
        XCTAssertFalse(vm.isRecording)
    }
}
