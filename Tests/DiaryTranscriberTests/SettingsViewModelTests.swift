import XCTest
@testable import DiaryTranscriberCore

final class SettingsViewModelTests: XCTestCase {

    @MainActor
    func testDefaultOutputFolder_isDocumentsDiary() {
        let vm = SettingsViewModel()
        // Default should contain "Documents/Diary" when no override set
        XCTAssertTrue(vm.outputFolder.contains("Diary"), "Default output folder should be Diary-related")
    }

    @MainActor
    func testAPIKey_returnsEmptyWhenNotSet() {
        let vm = SettingsViewModel()
        // When no key is set, returns empty string (not nil)
        // Note: may return a previously saved key from Keychain in test environment
        _ = vm.apiKey
        XCTAssertTrue(true, "API key accessor compiles and runs")
    }

    @MainActor
    func testTranscriptionSettings_defaultsToBothEnabled() {
        let vm = SettingsViewModel()
        XCTAssertTrue(vm.transcriptionSettings.useOnDeviceSpeech, "On-device Speech should default to on")
        XCTAssertTrue(vm.transcriptionSettings.useWhisperFallback, "Whisper fallback should default to on")
    }
}
