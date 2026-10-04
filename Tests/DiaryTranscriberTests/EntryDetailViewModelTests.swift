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
    func testUpdateTranscript_marksUnsaved() {
        let entry = makeEntry(source: .speech)
        let vm = EntryDetailViewModel(entry: entry)
        vm.updateTranscript("New text")
        XCTAssertEqual(vm.transcriptText, "New text")
        XCTAssertTrue(vm.hasUnsavedChanges)
    }

    @MainActor
    func testSaveIfChanged_doesNotCrash_withoutStore() async {
        let entry = makeEntry(source: .speech)
        let vm = EntryDetailViewModel(entry: entry)
        vm.updateTranscript("Edited")
        await vm.saveIfChanged()
        // No store → should silently succeed.
    }

    @MainActor
    func testSaveIfChanged_noChanges_isNoOp() async {
        let entry = makeEntry(source: .speech)
        let vm = EntryDetailViewModel(entry: entry)
        await vm.saveIfChanged()
        // No changes → should not crash.
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
