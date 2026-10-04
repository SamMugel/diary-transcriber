import XCTest
@testable import DiaryTranscriberCore

final class SettingsViewModelTests: XCTestCase {

    private static let outputFolderKey = "com.compactifai.diarytranscriber.outputFolder"
    private static let useOnDeviceSpeechKey = "com.compactifai.diarytranscriber.useOnDeviceSpeech"
    private static let useWhisperFallbackKey = "com.compactifai.diarytranscriber.useWhisperFallback"

    // AI: test-specific Keychain service/account so CI never collides with the user's real api-key entry / PRD 30
    private static let testService = "com.compactifai.diarytranscriber.test-\(UUID().uuidString)"
    private static let testAccount = "api-key-test"

    override func tearDown() {
        // AI: clean up the test-specific Keychain entry after every test so runs stay independent / PRD 30
        KeychainHelper.deleteAPIKey(service: Self.testService, account: Self.testAccount)
    }

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
        // AI: clearUserDefaultsForToggles so a stale value doesn't make a previously-passing test flaky / PRD 29
        Self.clearToggles()
        let vm = SettingsViewModel()
        XCTAssertTrue(vm.transcriptionSettings.useOnDeviceSpeech, "On-device Speech should default to on")
        XCTAssertTrue(vm.transcriptionSettings.useWhisperFallback, "Whisper fallback should default to on")
    }

    @MainActor
    func testTranscriptionSettings_persistsAcrossInstancesAfterSave() {
        Self.clearToggles()
        defer { Self.clearToggles() }

        let vm1 = SettingsViewModel()
        vm1.transcriptionSettings.useOnDeviceSpeech = false
        vm1.transcriptionSettings.useWhisperFallback = false
        vm1.save()

        let vm2 = SettingsViewModel()
        XCTAssertFalse(vm2.transcriptionSettings.useOnDeviceSpeech, "On-device Speech toggle should have persisted as false")
        XCTAssertFalse(vm2.transcriptionSettings.useWhisperFallback, "Whisper fallback toggle should have persisted as false")
    }

    @MainActor
    func testTranscriptionSettings_partialTogglePersistsAcrossInstancesAfterSave() {
        Self.clearToggles()
        defer { Self.clearToggles() }

        // AI: change only one toggle; the other should retain its default true / PRD 29 acceptance criterion 2
        let vm1 = SettingsViewModel()
        vm1.transcriptionSettings.useOnDeviceSpeech = false
        vm1.save()

        let vm2 = SettingsViewModel()
        XCTAssertFalse(vm2.transcriptionSettings.useOnDeviceSpeech, "On-device Speech toggle should have persisted as false")
        XCTAssertTrue(vm2.transcriptionSettings.useWhisperFallback, "Whisper fallback should hold its default true")
    }

    @MainActor
    func testTranscriptionSettings_freshUserDefaultsYieldsDefaults() {
        Self.clearToggles()
        defer { Self.clearToggles() }

        // AI: with no UserDefaults written, init must match TranscriptSettings() defaults so a fresh install shows expected state / PRD 29
        let vm = SettingsViewModel()
        XCTAssertEqual(vm.transcriptionSettings, TranscriptSettings(), "Fresh defaults must match TranscriptSettings() defaults")
    }

    @MainActor
    func testCommitAPIKey_nonEmptyValue_persistsAndReadsBack() {
        let vm = SettingsViewModel()
        // AI: ensure no pre-existing entry seeds a false positive before writing / PRD 30
        KeychainHelper.deleteAPIKey(service: Self.testService, account: Self.testAccount)
        defer { KeychainHelper.deleteAPIKey(service: Self.testService, account: Self.testAccount) }

        let key = "sk-test-\(UUID().uuidString)"
        vm.commitAPIKey(key, service: Self.testService, account: Self.testAccount)

        XCTAssertEqual(
            vm.apiKey(service: Self.testService, account: Self.testAccount),
            key,
            "commitAPIKey should write the value to Keychain readable via apiKey"
        )
    }

    @MainActor
    func testCommitAPIKey_emptyString_deletesFromKeychain() {
        let vm = SettingsViewModel()
        KeychainHelper.deleteAPIKey(service: Self.testService, account: Self.testAccount)
        defer { KeychainHelper.deleteAPIKey(service: Self.testService, account: Self.testAccount) }

        // AI: seed a value first so the deletion path has something to remove / PRD 30
        vm.commitAPIKey("sk-do-not-keep", service: Self.testService, account: Self.testAccount)
        XCTAssertEqual(vm.apiKey(service: Self.testService, account: Self.testAccount), "sk-do-not-keep")

        vm.commitAPIKey("", service: Self.testService, account: Self.testAccount)

        XCTAssertEqual(
            vm.apiKey(service: Self.testService, account: Self.testAccount),
            "",
            "Empty commitAPIKey should remove the entry so apiKey reads back empty"
        )
    }

    @MainActor
    func testCommitAPIKey_doesNotMutateProductionAPIKey() {
        // AI: PRD 30 acceptance — the test service/account must never touch the production api-key entry,
        //     so a commit under the test service leaves the production value untouched / PRD 30
        let vm = SettingsViewModel()
        let prodBefore = vm.apiKey

        vm.commitAPIKey("sk-test-only-\(UUID().uuidString)", service: Self.testService, account: Self.testAccount)
        defer { KeychainHelper.deleteAPIKey(service: Self.testService, account: Self.testAccount) }

        XCTAssertEqual(vm.apiKey, prodBefore, "Production api-key must be unaffected by a test-service commit")
    }

    private static func clearToggles() {
        UserDefaults.standard.removeObject(forKey: useOnDeviceSpeechKey)
        UserDefaults.standard.removeObject(forKey: useWhisperFallbackKey)
    }
}
