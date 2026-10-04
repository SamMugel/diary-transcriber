import XCTest
@testable import DiaryTranscriberCore

final class EntryDetailViewModelTests: XCTestCase {

    @MainActor
    func testInitialState() {
        let entry = makeEntry(source: .speech)
        let vm = EntryDetailViewModel(entry: entry)
        XCTAssertEqual(vm.transcriptText, "", "Initial transcript text should be empty")
        XCTAssertFalse(vm.hasUnsavedChanges, "Should start with no unsaved changes")
        XCTAssertFalse(vm.showRetranscribe, "speech source should not show re-transcribe")
    }

    @MainActor
    func testShowRetranscribe_whenSourceNone() {
        let entry = makeEntry(source: .none)
        let vm = EntryDetailViewModel(entry: entry)
        XCTAssertTrue(vm.showRetranscribe, ".none source should show re-transcribe")
    }

    @MainActor
    func testShowRetranscribe_whenSourceWhisper_false() {
        let entry = makeEntry(source: .whisper)
        let vm = EntryDetailViewModel(entry: entry)
        XCTAssertFalse(vm.showRetranscribe, ".whisper source should not show re-transcribe")
    }

    @MainActor
    func testUpdateTranscript_marksUnsaved() {
        let entry = makeEntry(source: .speech)
        let vm = EntryDetailViewModel(entry: entry)
        vm.updateTranscript("New text")
        XCTAssertEqual(vm.transcriptText, "New text")
        XCTAssertTrue(vm.hasUnsavedChanges)
    }

    @MainActor
    func testSaveIfChanged_withStore_clearsUnsavedFlag() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "vm-save-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = makeEntry(source: .speech)
        try await store.append(entry: entry)

        let vm = EntryDetailViewModel(entry: entry, store: store)
        vm.updateTranscript("Edited transcript")
        XCTAssertTrue(vm.hasUnsavedChanges, "Should have unsaved changes after edit")

        await vm.saveIfChanged()
        XCTAssertFalse(vm.hasUnsavedChanges, "saveIfChanged should clear the flag on success")
    }

    @MainActor
    func testSaveIfChanged_noChanges_isNoOpWithStore() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "vm-noop-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = makeEntry(source: .speech)
        try await store.append(entry: entry)

        let vm = EntryDetailViewModel(entry: entry, store: store)
        // No changes made; saveIfChanged should be a no-op.
        await vm.saveIfChanged()
        XCTAssertFalse(vm.hasUnsavedChanges, "Should remain false with no changes")
    }

    @MainActor
    func testLoadData_loadsTranscriptFromStore() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "vm-load-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // append() creates an empty transcript file; loadData() should read it.
        let entry = makeEntry(source: .speech)
        try await store.append(entry: entry)

        let vm = EntryDetailViewModel(entry: entry, store: store)
        await vm.loadData()
        XCTAssertEqual(vm.transcriptText, "", "Should load empty transcript from newly created entry")
    }

    // MARK: - Helpers

    private func makeEntry(source: TranscriptSource) -> DiaryEntry {
        DiaryEntry(
            startedAt: Date(),
            durationSeconds: 120,
            audioPath: "test.m4a",
            transcriptPath: "test.md",
            source: source
        )
    }
}
