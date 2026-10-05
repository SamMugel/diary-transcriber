import XCTest
@testable import DiaryTranscriberCore

// AI:
//   what: AppEnvironmentTests — constructs AppEnvironment under controlled Keychain state and
//         asserts that the shared TranscriptionService is (or is not) Whisper-backed, plus that
//         committing a new API key reloads the Whisper client in place.
//   why:  PRD #28 acceptance criteria 1 & 2 — a Keychain-backed key must produce a
//         WhisperClient-backed TranscriptionService at startup, and editing the API key + pressing
//         Save must reload the Whisper client without restarting the app. Tests cannot read the
//         private `whisperClient` field directly, so they use the actor's test-only
//         `hasWhisperClient()` accessor exposed by PRD #28.
//   ref:  PRD 28-transcription-service-bootstrap, ISSUE-010b

final class AppEnvironmentTests: XCTestCase {

    // AI: per-test Keychain coordinates under a UUID'd service so multiple CI runs / parallel
    //     invocations never collide with each other or with the production api-key entry / PRD 30
    private let testService = "com.compactifai.diarytranscriber.test-appenv-\(UUID().uuidString)"
    private let testAccount = "api-key-test"

    override func tearDown() {
        // AI: guarantee the test service is cleared after every test so runs stay independent / PRD 30
        KeychainHelper.deleteAPIKey(service: testService, account: testAccount)
        super.tearDown()
    }

    // MARK: - Criterion 1: a Keychain-backed key boots a WhisperClient-backed service

    @MainActor
    func testAppEnvironment_withKeychainKey_buildsWhisperBackedService() async throws {
        // AI: Verifies PRD #28 acceptance criterion 1 — when the Keychain holds an OpenAI API key,
        //     constructing the shared TranscriptionService at startup wires a non-nil WhisperClient.
        //     Without this, the Whisper fallback (and thus the whole transcription pipeline) is
        //     silently skipped (ISSUE-010b).

        let key = "sk-test-\(UUID().uuidString)"
        try KeychainHelper.saveAPIKey(key, service: testService, account: testAccount)
        defer { KeychainHelper.deleteAPIKey(service: testService, account: testAccount) }

        let env = AppEnvironment(
            store: Self.makeTempStore(),
            settings: SettingsViewModel(),
            transcriptionService: Self.makeService(service: testService, account: testAccount)
        )

        let hasClient = await env.transcriptionService.hasWhisperClient()
        XCTAssertTrue(
            hasClient,
            "A Keychain-backed API key should produce a WhisperClient-backed TranscriptionService"
        )
    }

    // MARK: - Criterion 1 (negative): no key → no Whisper client, no crash

    @MainActor
    func testAppEnvironment_withoutKeychainKey_hasNoWhisperClient() async throws {
        // AI: Verifies PRD #28 acceptance criterion 1 (negative path) — when no API key is set,
        //     whisperClient is nil and Whisper fallback is skipped gracefully (requiring "not a crash").
        //     This guards against startup crashes on devices that have never had an API key configured.

        KeychainHelper.deleteAPIKey(service: testService, account: testAccount)

        let env = AppEnvironment(
            store: Self.makeTempStore(),
            settings: SettingsViewModel(),
            transcriptionService: Self.makeService(service: testService, account: testAccount)
        )

        let hasClient = await env.transcriptionService.hasWhisperClient()
        XCTAssertFalse(
            hasClient,
            "With no API key in Keychain, the service should have NO Whisper client (gracefully nil)"
        )
    }

    // MARK: - Criterion 2: reload flips the Whisper client after a key commit

    @MainActor
    func testReloadWhisperClient_afterKeyCommit_swapsClientInPlace() async throws {
        // AI: Verifies PRD #28 acceptance criterion 2 — after committing a new API key in Settings and
        //     calling reloadWhisperClient(), the shared TranscriptionService picks up the new client
        //     without a restart. The service INSTANCE stays the same (Approach R: in-place mutation),
        //     so view-models holding a stable `let service` reference are still valid after reload.

        let env = AppEnvironment(
            store: Self.makeTempStore(),
            settings: SettingsViewModel(),
            transcriptionService: Self.makeService(service: testService, account: testAccount)
        )

        // Precondition: no key → no client.
        KeychainHelper.deleteAPIKey(service: testService, account: testAccount)
        env.reloadWhisperClient(service: testService, account: testAccount)
        // AI: give the actor's replaceWhisperClient Task a chance to run before asserting.
        try await Task.sleep(for: .milliseconds(50))
        let hasAfterDelete = await env.transcriptionService.hasWhisperClient()
        XCTAssertFalse(
            hasAfterDelete,
            "With no key in Keychain, reload should leave the Whisper client nil"
        )

        // Commit a key via the test-friendly Keychain path (mirrors SettingsViewModel.commitAPIKey),
        // then reload — the same shared service instance should now report a Whisper client.
        let key = "sk-after-\(UUID().uuidString)"
        try KeychainHelper.saveAPIKey(key, service: testService, account: testAccount)
        defer { KeychainHelper.deleteAPIKey(service: testService, account: testAccount) }

        env.reloadWhisperClient(service: testService, account: testAccount)
        try await Task.sleep(for: .milliseconds(50))

        let hasAfterCommit = await env.transcriptionService.hasWhisperClient()
        XCTAssertTrue(
            hasAfterCommit,
            "After committing an API key and reloading, the shared service should be Whisper-backed"
        )
    }

    // MARK: - Criterion 2 (negative): deleting the key then reloading clears the client

    @MainActor
    func testReloadWhisperClient_afterKeyDeleted_clearsClient() async throws {
        // AI: Verifies PRD #28 acceptance criterion 2 in the reverse direction — if the user clears
        //     the API key field and saves (empty commit deletes from Keychain per SettingsViewModel),
        //     reloadWhisperClient() must tear down the existing Whisper client so no stale credentials
        //     linger. This closes a leak where a removed key keeps the old client alive.

        let env = AppEnvironment(
            store: Self.makeTempStore(),
            settings: SettingsViewModel(),
            transcriptionService: Self.makeService(service: testService, account: testAccount)
        )

        // Seed a key and assert the service picks it up after reload.
        try KeychainHelper.saveAPIKey("sk-initial", service: testService, account: testAccount)
        defer { KeychainHelper.deleteAPIKey(service: testService, account: testAccount) }
        env.reloadWhisperClient(service: testService, account: testAccount)
        try await Task.sleep(for: .milliseconds(50))
        let hasAfterSeed = await env.transcriptionService.hasWhisperClient()
        XCTAssertTrue(
            hasAfterSeed,
            "Precondition: a key in Keychain should yield a Whisper client after reload"
        )

        // Delete the key (empty commit), reload, and assert the client is gone.
        KeychainHelper.deleteAPIKey(service: testService, account: testAccount)
        env.reloadWhisperClient(service: testService, account: testAccount)
        try await Task.sleep(for: .milliseconds(50))
        let hasAfterRemove = await env.transcriptionService.hasWhisperClient()
        XCTAssertFalse(
            hasAfterRemove,
            "After deleting the API key and reloading, the service should no longer hold a Whisper client"
        )
    }

    // MARK: - Helpers

    /// Build a throwaway DiaryStore on a temp dir so the test never touches ~/Documents/Diary.
    private static func makeTempStore() -> DiaryStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "appenv-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // AI: best-effort cleanup on test exit; store is read-only after construction here anyway.
        //     No defer-path available in a static helper, so leakage is acceptable — each test sets
        //     up its own UUID'd dir and never reuses it.
        return DiaryStore(folder: tempDir)
    }

    /// Build a TranscriptionService using the AppEnvironment's production construction logic but
    /// pointed at a test-specific Keychain service/account. Mirrors `AppEnvironment.buildService`.
    private static func makeService(service: String, account: String) -> TranscriptionService {
        let key = KeychainHelper.loadAPIKey(service: service, account: account)
        let whisperClient: WhisperClient? = key.map { WhisperClient(apiKey: $0) }
        return TranscriptionService(whisperClient: whisperClient)
    }
}
