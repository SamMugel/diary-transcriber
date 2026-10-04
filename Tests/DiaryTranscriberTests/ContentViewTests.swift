import XCTest
@testable import DiaryTranscriberCore

final class ContentViewTests: XCTestCase {

    @MainActor
    func testListViewModel_initialState() async {
        let vm = ListViewModel(store: nil)
        XCTAssertTrue(vm.entries.isEmpty, "With no store, entries should be empty")
        XCTAssertFalse(vm.isRecording, "isRecording should be false initially")
    }

    @MainActor
    func testListViewModel_startRecording_setsFlag() async {
        let vm = ListViewModel(store: nil)
        vm.startRecording()
        XCTAssertTrue(vm.isRecording, "isRecording should be true after startRecording")
    }

    @MainActor
    func testListViewModel_cancelRecording_clearsFlag() async {
        let vm = ListViewModel(store: nil)
        vm.startRecording()
        vm.cancelRecording()
        XCTAssertFalse(vm.isRecording, "isRecording should be false after cancelRecording")
    }

    @MainActor
    func testEmptyState_canInstantiate() {
        _ = EmptyState()
    }

    @MainActor
    func testEntryRow_canInstantiateWithEntry() {
        let entry = DiaryEntry(
            id: UUID(),
            startedAt: Date(),
            durationSeconds: 120,
            audioPath: "2026-10-04-0900.m4a",
            transcriptPath: "2026-10-04-0900.md",
            source: .speech
        )
        _ = EntryRow(entry: entry)
    }
}
