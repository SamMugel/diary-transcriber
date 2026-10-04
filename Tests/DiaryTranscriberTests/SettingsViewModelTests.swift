import XCTest
@testable import DiaryTranscriberCore

final class SettingsViewModelTests: XCTestCase {

    private static let outputFolderKey = "com.compactifai.diarytranscriber.outputFolder"

    @MainActor
    func testDefaultOutputFolder_isDocumentsDiary() {
        // Clear any previous value to test the true default.
        UserDefaults.standard.removeObject(forKey: Self.outputFolderKey)
        let vm = SettingsViewModel()
        XCTAssertTrue(vm.outputFolder.contains("Diary"), "Default output folder should be Diary-related")
    }

    @MainActor
    func testOutputFolder_persistsAcrossInstances() {
        let vm1 = SettingsViewModel()
        vm1.outputFolder = "/custom/test/path"

        let vm2 = SettingsViewModel()
        XCTAssertEqual(vm2.outputFolder, "/custom/test/path", "Output folder should persist via UserDefaults")

        // Clean up to avoid polluting other tests.
        UserDefaults.standard.removeObject(forKey: Self.outputFolderKey)
    }

    @MainActor
    func testTranscriptionSettings_defaultsToBothEnabled() {
        let vm = SettingsViewModel()
        XCTAssertTrue(vm.transcriptionSettings.useOnDeviceSpeech, "On-device Speech should default to on")
        XCTAssertTrue(vm.transcriptionSettings.useWhisperFallback, "Whisper fallback should default to on")
    }
}
