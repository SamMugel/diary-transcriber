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
}
