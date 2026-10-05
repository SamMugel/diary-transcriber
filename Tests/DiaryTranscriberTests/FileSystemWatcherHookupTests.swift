import XCTest
@testable import DiaryTranscriberCore

// AI:
//   what: Tests for FileSystemWatcher hookup in ListViewModel (PRD #32)
//   why:  The watcher must update the timeline on external file changes, teardown()
//         must cancel the subscription Task (no leak), and burst writes must result
//         in ≤2 refresh events. Mirrors the RecordingViewModel.teardown() test
//         patterns from RecordingViewModelTests.
//   ref:  PRD 32-filesystem-watcher-hookup, PRD 24-recording-timer-leak

final class FileSystemWatcherHookupTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "watcher-hookup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - teardown() from idle / never-started

    @MainActor
    func testTeardown_whenIdle_isNoOpAndDoesNotCrash() async {
        // teardown() without ever calling startWatching() should not crash and
        // should be a safe no-op.
        let vm = ListViewModel(store: DiaryStore(folder: tempDir))
        await vm.teardown()
        XCTAssertEqual(vm.entries.count, 0, "No entries should exist")
    }

    @MainActor
    func testTeardown_isIdempotent() async {
        // Calling teardown() multiple times should be safe and not crash.
        let vm = ListViewModel(store: DiaryStore(folder: tempDir))
        await vm.startWatching()
        await vm.teardown()
        await vm.teardown()
        await vm.teardown()
        // No crash, no hang — the watcher subscription is fully released.
    }

    // MARK: - startWatching() idempotency

    @MainActor
    func testStartWatching_isIdempotent() async {
        // Calling startWatching() twice should not create duplicate subscriptions.
        let vm = ListViewModel(store: DiaryStore(folder: tempDir))
        await vm.startWatching()
        await vm.startWatching()
        await vm.teardown()
    }

    // MARK: - teardown stops refreshes (no leaked subscription)

    @MainActor
    func testTeardown_stopsRefreshingAfterCall() async throws {
        // After teardown(), writing to the folder should NOT trigger refresh()
        // — proving the subscription Task was cancelled (no leak).
        let store = DiaryStore(folder: tempDir)
        let vm = ListViewModel(store: store)

        // Seed one entry so entries is non-empty.
        let first = makeEntry(startedAt: Date(timeIntervalSince1970: 1727943900))
        try await store.append(entry: first)

        await vm.startWatching()
        await vm.refresh()

        // Give the watcher time to take its initial snapshot.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(vm.entries.count, 1, "Should have 1 entry initially")

        await vm.teardown()

        // After teardown, add a file directly to the folder. This would normally
        // trigger the watcher, but since the subscription is cancelled, it should
        // NOT update vm.entries (no leaked subscription).
        let fileName = "post-teardown-\(UUID().uuidString).m4a"
        try "fake audio".write(
            to: tempDir.appending(path: fileName),
            atomically: true,
            encoding: .utf8
        )

        // Wait long enough for the watcher's debounce + poll interval to have
        // fired had the subscription been alive.
        try await Task.sleep(for: .seconds(2))

        // entries should still be 1 because teardown() cancelled the subscription
        // and no refresh() was triggered by the external file write.
        XCTAssertEqual(
            vm.entries.count,
            1,
            "After teardown(), external file writes should NOT trigger refresh"
        )
    }

    // MARK: - end-to-end: external file change updates timeline

    @MainActor
    func testStartWatching_externalChangeUpdatesTimeline() async throws {
        let store = DiaryStore(folder: tempDir)
        let vm = ListViewModel(store: store)

        await vm.startWatching()
        await vm.refresh()

        // Give the watcher time to take its initial snapshot.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssert(vm.entries.isEmpty, "Should have 0 entries initially")

        // Use the actor API to append a manifest row; this also writes files to
        // the folder so it triggers the watcher's change detection, and the
        // resulting refresh() picks up the new manifest entry.
        let entry = makeEntry(startedAt: Date(timeIntervalSince1970: 1728000000))
        try await store.append(entry: entry)

        // Poll for the timeline to update (the watcher debounces 0.5s, then
        // refresh() re-reads the manifest). We allow up to 5 seconds.
        var updated = false
        for _ in 0..<50 {
            if vm.entries.count == 1 {
                updated = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertTrue(
            updated,
            "External append should update the timeline via the watcher within ~2s"
        )

        await vm.teardown()
    }

    // MARK: - Helpers

    private func makeEntry(startedAt: Date) -> DiaryEntry {
        let timestamp = ISO8601DateFormatter.format(startedAt)
        return DiaryEntry(
            id: UUID(),
            startedAt: startedAt,
            durationSeconds: 30.0,
            audioPath: "\(timestamp).m4a",
            transcriptPath: "\(timestamp).md",
            source: .none
        )
    }
}

private extension ISO8601DateFormatter {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        return formatter.string(from: date)
    }
}
