import XCTest
@testable import DiaryTranscriberCore

final class RecordingViewModelTests: XCTestCase {

    @MainActor
    func testInitialState() {
        let vm = RecordingViewModel()
        XCTAssertEqual(vm.liveTranscript, "", "Initial transcript should be empty")
        XCTAssertEqual(vm.elapsed, 0, "Initial elapsed should be 0")
        XCTAssertFalse(vm.isFinalizing, "isFinalizing should be false initially")
        XCTAssertFalse(vm.isRecording, "isRecording should be false initially")
        XCTAssertEqual(vm.permissionMessage, "", "permissionMessage should be empty initially")
    }

    @MainActor
    func testAppendTranscript_appendsWithSpace() {
        let vm = RecordingViewModel()
        vm.appendTranscript(text: "Hello")
        vm.appendTranscript(text: "world")
        XCTAssertEqual(vm.liveTranscript, "Hello world", "Words should be space-separated")
    }

    @MainActor
    func testAppendTranscript_firstWordNoLeadingSpace() {
        let vm = RecordingViewModel()
        vm.appendTranscript(text: "First")
        XCTAssertEqual(vm.liveTranscript, "First", "First word should have no leading space")
    }

    @MainActor
    func testStopWithoutStarting_isNoOp() async {
        let vm = RecordingViewModel()
        // Calling stop() without starting should be a no-op (guard returns early).
        await vm.stop()
        XCTAssertFalse(vm.isRecording, "Should not be recording without starting")
        XCTAssertFalse(vm.isFinalizing, "isFinalizing should remain false")
        XCTAssertNil(vm.handle, "handle should remain nil")
        XCTAssertNil(vm.completedEntry, "completedEntry should remain nil")
    }

    // AI: PRD #22 — tests for cancelRecording() and removePartialFile(at:).

    @MainActor
    func testCancelRecording_whenIdle_isNoOp() async {
        let vm = RecordingViewModel()
        await vm.cancelRecording()
        XCTAssertFalse(vm.isRecording, "Should not be recording after cancel")
        XCTAssertFalse(vm.isFinalizing, "isFinalizing should remain false")
        XCTAssertNil(vm.handle, "handle should remain nil")
        XCTAssertNil(vm.completedEntry, "completedEntry should remain nil")
    }

    @MainActor
    func testCancelRecording_whenFinalizing_isNoOp() async {
        let vm = RecordingViewModel()
        // Simulate the finalizing state, which cancelRecording must NOT touch.
        vm.isFinalizing = true
        await vm.cancelRecording()
        XCTAssertTrue(vm.isFinalizing, "isFinalizing should remain true when cancelled during finalizing")
    }

    func testRemovePartialFile_deletesExistingFile() {
        // Create a temp file and verify removePartialFile deletes it.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uniqueName = "test-partial-\(UUID().uuidString).m4a"
        let tempFile = tempDir.appendingPathComponent(uniqueName)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(), attributes: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path), "Temp file should exist before removal")

        RecordingViewModel.removePartialFile(at: tempFile)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path), "Partial file should be deleted")
    }

    func testRemovePartialFile_nilURL_isNoOp() {
        // Passing nil should not crash and should be a no-op.
        RecordingViewModel.removePartialFile(at: nil)
    }

    func testRemovePartialFile_nonExistentFile_isNoOp() {
        // Pointing to a path that does not exist should not crash.
        let nonExistent = URL(fileURLWithPath: "/tmp/diary-transcriber-nonexistent-\(UUID().uuidString).m4a")
        RecordingViewModel.removePartialFile(at: nonExistent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistent.path), "File should not exist")
    }
}
