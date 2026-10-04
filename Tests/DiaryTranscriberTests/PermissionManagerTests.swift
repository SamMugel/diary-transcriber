import XCTest
@testable import DiaryTranscriberCore

final class PermissionManagerTests: XCTestCase {

    // MARK: - RecorderError descriptions

    func testRecorderError_permissionDenied_hasDescriptiveMessage() {
        let error = RecorderError.permissionDenied("Access denied in settings")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Microphone access denied"))
        XCTAssertTrue(error.errorDescription!.contains("Access denied in settings"))
    }

    func testRecorderError_noDevice_hasDescriptiveMessage() {
        let error = RecorderError.noDevice
        XCTAssertEqual(error.errorDescription, "No audio input device found.")
    }

    func testRecorderError_cannotAddOutput_hasDescriptiveMessage() {
        let error = RecorderError.cannotAddOutput
        XCTAssertEqual(error.errorDescription, "Recording session rejected the output configuration.")
    }

    func testRecorderError_recordingFailed_includesUnderlyingMessage() {
        let underlying = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Internal error"
        ])
        let error = RecorderError.recordingFailed(underlying: underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Recording failed"))
        XCTAssertTrue(error.errorDescription!.contains("Internal error"))
    }

}
