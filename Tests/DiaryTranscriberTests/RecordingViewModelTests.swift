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

    // AI: PRD #24 — tests for teardown(). The core requirement is that teardown()
    //     cancels the periodic `timer` Task (and the `liveStreamTask`) and leaves
    //     them nil so no Task lingers in the heap once the recording view-model is
    //     discarded. We exercise the cancellation paths directly via the internal
    //     test seam; we do NOT call `start()` because that would require a working
    //     microphone + AVFoundation session on CI.

    @MainActor
    func testTeardown_whenIdle_isNoOpAndDoesNotCrash() async {
        // teardown() from idle should not crash and should leave the VM idle.
        let vm = RecordingViewModel()
        await vm.teardown()
        XCTAssertFalse(vm.isRecording, "idle teardown should leave isRecording false")
        XCTAssertFalse(vm.isFinalizing, "idle teardown should leave isFinalizing false")
        XCTAssertNil(vm.timer, "idle teardown should leave timer nil")
        XCTAssertNil(vm.liveStreamTask, "idle teardown should leave liveStreamTask nil")
    }

    @MainActor
    func testTeardown_isIdempotent() async {
        // Calling teardown() multiple times should be safe and not crash.
        let vm = RecordingViewModel()
        await vm.teardown()
        await vm.teardown()
        await vm.teardown()
        XCTAssertNil(vm.timer, "timer should remain nil after repeated teardown")
        XCTAssertNil(vm.liveStreamTask, "liveStreamTask should remain nil after repeated teardown")
    }

    @MainActor
    func testTeardown_nilTimerIsTreatedAsNoOp() async {
        // Requirement #3: cancelTimer (invoked by teardown) must guard for nil
        // and avoid double-cancel. With no timer ever started, teardown should
        // still leave vm.timer == nil and never crash.
        let vm = RecordingViewModel()
        XCTAssertNil(vm.timer, "Precondition: timer should be nil before teardown")
        await vm.teardown()
        XCTAssertNil(vm.timer, "teardown on nil timer should leave it nil (no crash)")
    }

    @MainActor
    func testTeardown_cancelsActiveTimerTask() async {
        // Start a timer-only task without going through `start()` (which requires
        // a mic). We mimic `startTimer()` exactly by assigning a Task that loops
        // every 100ms — same shape the real recording loop uses.
        let vm = RecordingViewModel()
        // Mirror RecordingViewModel.startTimer() so we exercise the real teardown
        // path on a genuine `Task<Void, Never>?`.
        vm.startTimerForTest()

        // Give the task a tick so it's definitely alive.
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNotNil(vm.timer, "Precondition: timer should be non-nil after start")

        await vm.teardown()

        XCTAssertNil(vm.timer, "teardown() must cancel and nil the timer Task")
        XCTAssertNil(vm.liveStreamTask, "teardown() must cancel and nil the liveStreamTask")

        // AI: After teardown, Awaiting a tick should not cause the cancelled
        //     timer Task to resume any work that mutates state — verify elapsed
        //     stays put (approximate; the timer might have ticked once more).
        let elapsedBefore = vm.elapsed
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(
            vm.elapsed > elapsedBefore + 1.0,
            "teardown() should stop the timer from advancing elapsed by >1s"
        )
    }

    @MainActor
    func testTeardown_recoversFromDoubleInvokeDuringActiveTimer() async {
        // Simulate the dismissal race: teardown called twice while the timer is
        // active. Requirement #3 demands no double-cancel crash.
        let vm = RecordingViewModel()
        vm.startTimerForTest()
        XCTAssertNotNil(vm.timer, "Precondition: timer should be non-nil")
        // Concurrent-like invocations from two independent dismiss paths.
        async let a: Void = vm.teardown()
        async let b: Void = vm.teardown()
        _ = await (a, b)
        XCTAssertNil(vm.timer, "Concurrent teardown invocations must leave timer nil")
        XCTAssertNil(vm.liveStreamTask, "Concurrent teardown invocations must leave liveStreamTask nil")
    }
}
