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

    // AI:
    //   what: saveIfChanged persists transcript edits to the .md file via setTranscript (closes ISSUE-015)
    //   why:  PRD #18 acceptance criterion #2 requires that inline transcript edits in EntryDetailView
    //         reach the .md file on disk, not just the manifest. The pre-#18 `saveIfChanged` routed
    //         through `store.update`, which left `.md` empty. This test fails loudly if saveIfChanged
    //         reverts to the old path.
    //   ref:  PRD 18-transcription-post-recording-pipeline, ISSUE-015
    @MainActor
    func testSaveIfChanged_PersistsTextToMDFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "vm-save-md-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = makeEntry(source: .speech)
        try await store.append(entry: entry)

        let vm = EntryDetailViewModel(entry: entry, store: store)
        vm.updateTranscript("Edited transcript text")
        await vm.saveIfChanged()

        let transcriptURL = tempDir.appending(path: entry.transcriptPath)
        let text = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertEqual(text, "Edited transcript text", "saveIfChanged should persist transcript to .md (ISSUE-015)")
    }

    // AI:
    //   what: saveIfChanged on a .none entry preserves .none source (does not invent a source)
    //   why:  PRD #18 — a failed-transcription (.none source) entry should stay .none after an
    //         inline user edit; saving shouldn't accidentally upgrade it to .speech/.whisper.
    //   ref:  PRD 18-transcription-post-recording-pipeline
    @MainActor
    func testSaveIfChanged_withSourceNone_keepsSourceNoneOnDisk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "vm-save-none-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = makeEntry(source: .none)
        try await store.append(entry: entry)

        let vm = EntryDetailViewModel(entry: entry, store: store)
        vm.updateTranscript("User-typed fallback text")
        await vm.saveIfChanged()

        let entries = try await store.entries()
        guard let updated = entries.first(where: { $0.id == entry.id }) else {
            return XCTFail("Entry should still be present after saveIfChanged")
        }
        // AI: write TranscriptSource.none explicitly to disambiguate Swift's `.none`
        //     (which could otherwise resolve to Optional<TranscriptSource>.none).
        XCTAssertEqual(updated.source, TranscriptSource.none, "source should remain .none after saveIfChanged on an .none entry")
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
