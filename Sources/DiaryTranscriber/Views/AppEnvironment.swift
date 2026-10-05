import Foundation
import SwiftUI

// AI:
//   what: AppEnvironment — minimal @MainActor @Observable container holding the app's shared services
//   why:  PRD #28 — a single shared TranscriptionService must be constructed at app launch with a
//         WhisperClient built from the Keychain API key, then injected into RecordingViewModel and
//         EntryDetailViewModel. AppEnvironment is the idiom for delivering it via SwiftUI Environment
//         and for rebuilding the Whisper client when the user commits a new API key in Settings
//         (PRD #28 acceptance criterion 2). Other shared collaborators (DiaryStore, SettingsViewModel)
//         live here only because SettingsView.openBackingSettingsViewModel.commitAPIKey must trigger
//         reloadWhisperClient(); there is no DI container, no resolver, no registerDependencies —
//         just construction.
//   ref:  PRD 28-transcription-service-bootstrap, CODE_REVIEW_ISSUES.md ISSUE-001/ISSUE-010b

@MainActor
@Observable
public final class AppEnvironment {

    /// Shared diary store passed to ContentView and view-models instead of being threaded ad-hoc.
    public let store: DiaryStore

    /// Shared settings view-model so SettingsView observes the same instance that drives
    /// reloadWhisperClient(). Constructed eagerly; reads UserDefaults/Keychain on init exactly
    /// once per app run.
    public let settings: SettingsViewModel

    /// Shared transcription service. Built once at init from the Keychain API key; clients hold a
    /// stable `let` reference and reload the Whisper fallback via reloadWhisperClient() rather than
    /// swapping the whole instance (Approach R).
    public let transcriptionService: TranscriptionService

    // AI: Production keychain coordinates; mirror KeychainHelper's private service/account. Tests
    //     inject their own service/account via the test-friendly initializers below so CI never
    //     touches the user's real api-key entry.
    private static let keychainService = "com.compactifai.diarytranscriber"
    private static let keychainAccount = "api-key"

    /// Production initializer. Reads the output folder from UserDefaults, builds the DiaryStore,
    /// builds the SettingsViewModel, and constructs the TranscriptionService with a WhisperClient
    /// only when a Keychain API key is present — matching PRD #28 acceptance criterion 1.
    public init() {
        self.store = AppEnvironment.makeDefaultStore()

        let settingsInstance = SettingsViewModel()
        self.settings = settingsInstance

        self.transcriptionService = AppEnvironment.buildService(
            settings: settingsInstance.transcriptionSettings,
            service: Self.keychainService,
            account: Self.keychainAccount
        )
    }

    /// Test-friendly initializer that lets tests inject a pre-built TranscriptionService (and the
    /// settings/store to back it) without touching production Keychain. Used by AppEnvironmentTests.
    // AI:
    //   what: Dependency-injected constructor for tests
    //   why:  PRD #28 tests must assert key-present / key-absent / reload paths against a real
    //         Whisper-backed service, but the production initializer reads from real Keychain. This
    //         overload lets a test pass a `TranscriptionService(whisperClient:)` built under a
    //         test-specific service/account so the assertions can run deterministically in CI.
    //   ref:  PRD 28-transcription-service-bootstrap, AppEnvironmentTests
    public init(
        store: DiaryStore,
        settings: SettingsViewModel,
        transcriptionService: TranscriptionService
    ) {
        self.store = store
        self.settings = settings
        self.transcriptionService = transcriptionService
    }

    // MARK: - Reload Whisper client

    /// Rebuilds the WhisperClient from the current Keychain API key and hot-swaps it on the shared
    /// TranscriptionService. Called from the Settings save path after commitAPIKey() so committing
    /// a new key reloads the Whisper fallback without restarting the app (PRD #28 criterion 2).
    public func reloadWhisperClient() {
        reloadWhisperClient(
            service: Self.keychainService,
            account: Self.keychainAccount
        )
    }

    /// Test-friendly reload that reads from an explicit keychain service/account so tests avoid
    //  polluting the production api-key entry.
    public func reloadWhisperClient(service: String, account: String) {
        let key = KeychainHelper.loadAPIKey(service: service, account: account)
        let client: WhisperClient? = key.map { WhisperClient(apiKey: $0) }
        Task { await transcriptionService.replaceWhisperClient(client) }
    }

    // MARK: - Private: Construction helpers

    private nonisolated static func makeDefaultStore() -> DiaryStore {
        let folder = outputFolderFromSettings()
        return DiaryStore(folder: URL(filePath: folder))
    }

    private nonisolated static func buildService(
        settings: TranscriptSettings,
        service: String,
        account: String
    ) -> TranscriptionService {
        let key = KeychainHelper.loadAPIKey(service: service, account: account)
        let whisperClient: WhisperClient? = key.map { WhisperClient(apiKey: $0) }
        return TranscriptionService(
            whisperClient: whisperClient,
            settings: settings
        )
    }

    // MARK: - Private: Settings mappers (moved from DiaryTranscriberApp)

    /// Read the output folder from UserDefaults (same key as SettingsViewModel).
    /// On first launch, defaults to `~/Documents/Diary`.
    private nonisolated static func outputFolderFromSettings() -> String {
        let key = "com.compactifai.diarytranscriber.outputFolder"
        let saved = UserDefaults.standard.string(forKey: key)
        if let saved, !saved.isEmpty {
            return resolveHome(saved)
        }

        // Default: ~/Documents/Diary
        let home = NSHomeDirectory()
        return "\(home)/Documents/Diary"
    }

    /// Resolve `~` in a path to the actual home directory.
    private nonisolated static func resolveHome(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return NSHomeDirectory() + String(path.dropFirst())
    }
}
