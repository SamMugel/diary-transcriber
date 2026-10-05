import XCTest
@testable import DiaryTranscriberCore

final class TimelineTests: XCTestCase {

    @MainActor
    func testListViewModel_acceptsEmptyStore() async {
        let vm = ListViewModel()
        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 0)
    }

    @MainActor
    func testListViewModel_entriesSortedNewestFirst() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "timeline-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let older = DiaryEntry(
            startedAt: Date().addingTimeInterval(-3600),
            durationSeconds: 60,
            audioPath: "a.m4a",
            transcriptPath: "a.md",
            source: .speech
        )
        let newer = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "b.m4a",
            transcriptPath: "b.md",
            source: .whisper
        )

        try await store.append(entry: older)
        try await store.append(entry: newer)

        let vm = ListViewModel(store: store)
        await vm.refresh()

        XCTAssertEqual(vm.entries.count, 2, "Should have 2 entries")
        XCTAssertEqual(vm.entries[0].id, newer.id, "Newest entry should be first")
        XCTAssertEqual(vm.entries[1].id, older.id, "Oldest entry should be second")
    }

    @MainActor
    func testListViewModel_refreshUpdatesEntries() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "timeline-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ListViewModel(store: store)
        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 0)

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 30,
            audioPath: "test.m4a",
            transcriptPath: "test.md",
            source: .none
        )
        try await store.append(entry: entry)

        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 1, "Refresh should pick up new entries")
    }

    @MainActor
    func testListViewModel_isRecordingToggle() {
        let vm = ListViewModel()
        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.showRecordingSheet)
        vm.startRecording()
        XCTAssertTrue(vm.isRecording)
        XCTAssertTrue(vm.showRecordingSheet)
        vm.cancelRecording()
        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.showRecordingSheet)
    }

    @MainActor
    func testListViewModel_finishRecording_persistsAndRefreshes() async throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appending(path: "finish-store-\(UUID().uuidString)")
        let store = DiaryStore(folder: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let vm = ListViewModel(store: store)
        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 0)

        // Simulate a finished recording: create a fake audio file in a *different*
        // directory (as AudioRecorder writes to ~/Documents, not the store folder).
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "finish-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let audioFile = sourceDir.appending(path: "fake-recording.m4a")
        try "fake audio data".write(to: audioFile, atomically: true, encoding: .utf8)

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 5,
            audioPath: audioFile.path,
            transcriptPath: audioFile.deletingPathExtension().appendingPathExtension("md").path,
            source: .none
        )

        await vm.finishRecording(entry: entry)

        // Sheet should be dismissed, timeline should show 1 entry.
        XCTAssertFalse(vm.showRecordingSheet)
        XCTAssertEqual(vm.entries.count, 1, "Timeline should have 1 entry after finishRecording")

        // The audio file should have been moved into the store folder.
        let movedAudio = storeDir.appending(path: "fake-recording.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedAudio.path),
                       "Audio file should be moved into the store folder")

        // Original should no longer exist.
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path),
                        "Original audio file should be moved, not copied")
    }

    // AI: PRD #25 — finishRecording with an unwritable store path sets errorBanner
    //     and retains the failed entry+transcript for Retry. The original audio file
    //     must remain on disk (not moved) so Retry can re-attempt.
    @MainActor
    func testListViewModel_finishRecording_setsErrorBannerOnFailure() async throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "fail-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let audioFile = sourceDir.appending(path: "fake-recording.m4a")
        try "fake audio data".write(to: audioFile, atomically: true, encoding: .utf8)

        // Point the store at a non-writable directory to trigger a persistence failure.
        let unwritableDir = FileManager.default.temporaryDirectory
            .appending(path: "fail-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unwritableDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [FileAttributeKey.posixPermissions: 0o000],
            ofItemAtPath: unwritableDir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [FileAttributeKey.posixPermissions: 0o755],
                ofItemAtPath: unwritableDir.path
            )
            try? FileManager.default.removeItem(at: unwritableDir)
        }

        let store = DiaryStore(folder: unwritableDir)
        let vm = ListViewModel(store: store)
        await vm.refresh()

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 5,
            audioPath: audioFile.path,
            transcriptPath: audioFile.deletingPathExtension().appendingPathExtension("md").path,
            source: .none
        )

        await vm.finishRecording(entry: entry)

        // An error banner must be set describing the failure.
        XCTAssertNotNil(vm.errorBanner, "errorBanner should be set when append fails")
        XCTAssertTrue(vm.errorBanner!.contains("Audio saved to ~/Documents"))
        XCTAssertTrue(vm.errorBanner!.contains("entry could not be saved"))

        // The original audio file must still exist (not moved) so retry can use it.
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioFile.path),
                       "Audio file should remain at source location on failure")
    }

    // AI: PRD #25 — retryFinishRecording re-attempts the failed append step. After a
    //     successful retry, errorBanner is cleared and the entry appears in the timeline.
    @MainActor
    func testListViewModel_retryFinishRecording_succeedsAfterRepreparation() async throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "retry-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let audioFile = sourceDir.appending(path: "fake-recording.m4a")
        try "fake audio data".write(to: audioFile, atomically: true, encoding: .utf8)

        let unwritableDir = FileManager.default.temporaryDirectory
            .appending(path: "retry-data-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unwritableDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [FileAttributeKey.posixPermissions: 0o000],
            ofItemAtPath: unwritableDir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [FileAttributeKey.posixPermissions: 0o755],
                ofItemAtPath: unwritableDir.path
            )
            try? FileManager.default.removeItem(at: unwritableDir)
        }

        let store = DiaryStore(folder: unwritableDir)
        let vm = ListViewModel(store: store)
        await vm.refresh()

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 5,
            audioPath: audioFile.path,
            transcriptPath: audioFile.deletingPathExtension().appendingPathExtension("md").path,
            source: .none
        )

        await vm.finishRecording(entry: entry)
        XCTAssertNotNil(vm.errorBanner, "Initial failure should set errorBanner")

        // Now fix the store folder: make it writable, and point a new store at it.
        try FileManager.default.setAttributes(
            [FileAttributeKey.posixPermissions: 0o755],
            ofItemAtPath: unwritableDir.path
        )

        // Retry re-attempts the failed append step.
        await vm.retryFinishRecording()

        XCTAssertNil(vm.errorBanner, "errorBanner should be cleared after successful retry")
        XCTAssertEqual(vm.entries.count, 1, "Timeline should show the retried entry")
    }

    // AI: PRD #25 — the error banner can be cleared (dismissed) by setting errorBanner = nil.
    @MainActor
    func testListViewModel_errorBanner_canBeCleared() async throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appending(path: "clear-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let audioFile = sourceDir.appending(path: "fake-recording.m4a")
        try "fake audio data".write(to: audioFile, atomically: true, encoding: .utf8)

        let unwritableDir = FileManager.default.temporaryDirectory
            .appending(path: "clear-data-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unwritableDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [FileAttributeKey.posixPermissions: 0o000],
            ofItemAtPath: unwritableDir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [FileAttributeKey.posixPermissions: 0o755],
                ofItemAtPath: unwritableDir.path
            )
            try? FileManager.default.removeItem(at: unwritableDir)
        }

        let store = DiaryStore(folder: unwritableDir)
        let vm = ListViewModel(store: store)
        await vm.refresh()

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 5,
            audioPath: audioFile.path,
            transcriptPath: audioFile.deletingPathExtension().appendingPathExtension("md").path,
            source: .none
        )

        await vm.finishRecording(entry: entry)
        XCTAssertNotNil(vm.errorBanner)

        // Simulate the Dismiss button: setting errorBanner = nil.
        vm.errorBanner = nil
        XCTAssertNil(vm.errorBanner, "errorBanner should be cleared by Dismiss")
    }
}
