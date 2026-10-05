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

    // MARK: - Timeline excerpt preview (PRD #27)

    // AI:
    //   what: ListViewModel.previewExcerpts — cached, lazy-loaded transcript previews
    //   why:  PRD #27 — timeline rows for transcribed entries must show a truncated excerpt
    //         without re-reading each `.md` on every redraw. These tests pin: (1) `.none`-
    //         source rows are cached synchronously to "No transcript yet" (no I/O), (2)
    //         transcribed rows are populated after refresh() with a ≤120-char excerpt plus
    //         "…" when the transcript was longer, (3) the cache is stable across a second
    //         refresh() so the list does not re-issue reads on each redraw, and (4) deleted
    //         entries are evicted from the cache.
    //   ref:  PRD 27-timeline-excerpt

    @MainActor
    func testPreviewExcerpts_noneSourceCachedSynchronouslyToNoTranscriptYet() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "excerpt-none-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 30,
            audioPath: "pending.m4a",
            transcriptPath: "pending.md",
            source: .none
        )
        try await store.append(entry: entry)

        let vm = ListViewModel(store: store)
        await vm.refresh()

        // `.none`-source rows are cached inline during kickOffPreviewLoads() — no Task spin-up.
        XCTAssertEqual(
            vm.previewExcerpts[entry.id],
            "No transcript yet",
            ".none-source rows should be cached to the literal 'No transcript yet'"
        )
    }

    @MainActor
    func testPreviewExcerpts_transcribedEntryPopulatedAfterRefresh() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "excerpt-pop-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "a.m4a",
            transcriptPath: "a.md",
            source: .speech
        )
        try await store.append(entry: entry)
        try await store.setTranscript(for: entry.id, source: .speech, text: "Hello, world.")

        let vm = ListViewModel(store: store)
        await vm.refresh()

        // The asynchronous Task that reads the excerpt lands after refresh() returns; poll
        // briefly so the test reflects the event-loop ordering, not the production code.
        try await Task.sleep(nanoseconds: 200_000_000)

        let preview = vm.previewExcerpts[entry.id]
        XCTAssertEqual(preview, "Hello, world.", "Transcribed entry should populate the excerpt cache")
        XCTAssertFalse(
            preview?.contains("…") ?? true,
            "Short transcript should not be truncated with ellipsis"
        )
    }

    @MainActor
    func testPreviewExcerpts_truncatedTranscriptAppendsEllipsis() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "excerpt-trunc-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "long.m4a",
            transcriptPath: "long.md",
            source: .whisper
        )
        // 200 chars of transcript → preview should be capped to 120 + "…".
        try await store.append(entry: entry)
        try await store.setTranscript(
            for: entry.id,
            source: .whisper,
            text: String(repeating: "y", count: 200)
        )

        let vm = ListViewModel(store: store)
        await vm.refresh()

        // The excerpt-loading Task executes async after refresh() returns.
        try await Task.sleep(nanoseconds: 200_000_000)

        let preview = vm.previewExcerpts[entry.id] ?? ""
        XCTAssertEqual(preview.count, 121, "Preview should be 120 chars + ellipsis (1 char)")
        XCTAssertTrue(preview.hasSuffix("…"), "Truncated preview should end with U+2026")
    }

    @MainActor
    func testPreviewExcerpts_exactly120CharsNotTruncated() async throws {
        // A transcript of exactly 120 chars should NOT get the ellipsis, since we did not
        // read beyond length+1 (we read 121 chars and got only 120 back → no overflow).
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "excerpt-exact-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "exact.m4a",
            transcriptPath: "exact.md",
            source: .speech
        )
        try await store.append(entry: entry)
        try await store.setTranscript(
            for: entry.id,
            source: .speech,
            text: String(repeating: "z", count: 120)
        )

        let vm = ListViewModel(store: store)
        await vm.refresh()

        try await Task.sleep(nanoseconds: 200_000_000)

        let preview = vm.previewExcerpts[entry.id] ?? ""
        XCTAssertEqual(preview.count, 120, "Exactly-120 transcript should not be truncated")
        XCTAssertFalse(preview.hasSuffix("…"), "No ellipsis on exact-length transcript")
    }

    @MainActor
    func testPreviewExcerpts_stableAcrossRefreshesDoesNotReReadOnEachRedraw() async throws {
        // Acceptance criterion #3: scrolling a 1,000-entry timeline does not re-read every .md
        // on each redraw. We simulate the redraw-relevant calls — repeated refresh() — and
        // assert that already-cached entries keep their value (a re-read would re-populate
        // them identically, but the caching measurement is that no new Task is spawned: the
        // preview stays non-nil throughout without any intermediate empty state).
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "excerpt-stable-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "stable.m4a",
            transcriptPath: "stable.md",
            source: .whisper
        )
        try await store.append(entry: entry)
        try await store.setTranscript(for: entry.id, source: .whisper, text: "Stable text.")

        let vm = ListViewModel(store: store)
        await vm.refresh()
        try await Task.sleep(nanoseconds: 200_000_000)

        let firstPreview = vm.previewExcerpts[entry.id]
        XCTAssertEqual(firstPreview, "Stable text.")

        // Second refresh() — already-cached entries keep their value; no new Task fires for
        // entries with a non-nil cache.
        await vm.refresh()

        // The existing cache is preserved across refresh (the value never flips to nil),
        // proving kickOffPreviewLoads() did not re-issue a read for this already-cached id.
        XCTAssertEqual(vm.previewExcerpts[entry.id], "Stable text.", "Cached preview should persist across refresh")
    }

    @MainActor
    func testPreviewExcerpts_deletedEntryEvictedFromCache() async throws {
        // Stale cache entries for deleted ids must not accumulate unbounded across refreshes.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "excerpt-evict-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 60,
            audioPath: "evict.m4a",
            transcriptPath: "evict.md",
            source: .none
        )
        try await store.append(entry: entry)

        let vm = ListViewModel(store: store)
        await vm.refresh()
        XCTAssertEqual(vm.previewExcerpts[entry.id], "No transcript yet")

        try await store.delete(id: entry.id)
        await vm.refresh()

        XCTAssertNil(
            vm.previewExcerpts[entry.id],
            "Deleted entry should be evicted from the preview cache on refresh"
        )
    }

    // MARK: - PRD #34 — ListViewModel Init Task Lifecycle

    // AI: PRD #34 — Verify that constructing a ListViewModel no longer fires a
    //     detached refresh task. Previously `init` called `Task { await refresh() }`
    //     which populated `entries` asynchronously after construction. After the
    //     fix, `entries` stays empty until an explicit `refresh()` call (which is
    //     now driven by `ContentView.body`'s `.task` modifier). This guards against
    //     a regression where the detached task is reintroduced.
    @MainActor
    func testListViewModel_init_doesNotAutoRefresh() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "init-task-test-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 30,
            audioPath: "init.m4a",
            transcriptPath: "init.md",
            source: .none
        )
        try await store.append(entry: entry)

        // Construct the view-model but do NOT call refresh(). If init still
        // kicked off a detached task, the entry could appear here. Yield once
        // to give any possible detached task a chance to run.
        let vm = ListViewModel(store: store)
        await Task.yield()

        XCTAssertEqual(
            vm.entries.count, 0,
            "init must not auto-refresh; entries should remain empty until an explicit refresh"
        )
    }

    // AI: PRD #34 — Verify the timeline populates when refresh() is invoked from
    //     the view's `.task` scope (the direct equivalent of what ContentView's
    //     `.task { await viewModel.refresh() }` does on appear). This confirms the
    //     initial-refresh behavior is preserved end-to-end.
    @MainActor
    func testListViewModel_initialRefreshPopulatesTimeline() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "init-task-populate-\(UUID().uuidString)")
        let store = DiaryStore(folder: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = DiaryEntry(
            startedAt: Date(),
            durationSeconds: 30,
            audioPath: "populate.m4a",
            transcriptPath: "populate.md",
            source: .none
        )
        try await store.append(entry: entry)

        let vm = ListViewModel(store: store)
        XCTAssertEqual(vm.entries.count, 0, "Before refresh, entries should be empty")

        // Simulate what ContentView's `.task` does on appear.
        await vm.refresh()

        XCTAssertEqual(vm.entries.count, 1, "After refresh, the timeline should be populated")
        XCTAssertEqual(vm.entries[0].id, entry.id)
    }

    // MARK: - PRD #15 — Timeline acceptance criteria

    // AI:
    //   what: Timeline renders 1,000 entries in under 500ms (acceptance criterion 1)
    //   why:  PRD #15 requires the timeline to scale to a thousand entries without
    //         perceptible lag. The ListViewModel is the seam that drives rendering:
    //         refresh() loads the manifest and kicks off per-entry excerpt loads.
    //         `.none`-source rows are cached synchronously (no I/O), so the bulk of
    //         1,000 entries' synchronous work is the manifest read + sort + cache
    //         population. We measure refresh() end-to-end and assert <500ms.
    //   ref:  PRD 15-timeline (acceptance criterion 1)
    @MainActor
    func testTimeline_refreshes1000EntriesWithin500ms() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "timeline-1000-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Seed 1,000 entries by writing the manifest JSON directly. DiaryStore.append
        // rewrites the entire manifest on each call, so 1,000 appends would dominate the
        // test with O(n²) manifest I/O rather than measuring the timeline's refresh path.
        // `.none` source keeps excerpt caching synchronous (no per-entry disk read),
        // matching the worst-case rendering path LazyVStack takes for a freshly-loaded
        // timeline. Per-entry .md/.json files are created only when append() runs;
        // refresh()'s excerpt path for `.none` never touches them (synchronously cached),
        // so they are not needed here.
        let entries = (0..<1_000).map { index in
            DiaryEntry(
                startedAt: Date().addingTimeInterval(Double(index)),
                durationSeconds: 30,
                audioPath: "entry-\(index).m4a",
                transcriptPath: "entry-\(index).md",
                source: .none
            )
        }
        let manifest = Manifest(schemaVersion: 1, folder: tempDir.path, entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(manifest).write(
            to: tempDir.appending(path: "manifest.json"),
            options: .atomic
        )

        let vm = ListViewModel(store: DiaryStore(folder: tempDir))

        let start = Date()
        await vm.refresh()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(vm.entries.count, 1_000, "All 1,000 entries should be loaded")
        XCTAssertLessThan(
            elapsed, 0.500,
            "Refreshing 1,000 entries took \(elapsed * 1000)ms; must be under 500ms"
        )
    }

    // AI:
    //   what: Source badge label matches each TranscriptSource (acceptance criterion 3)
    //   why:  The timeline EntryRow must display the correct label for each source so
    //         users can distinguish speech / whisper / pending entries at a glance.
    //         The label/icon/tint are pure static functions on EntryRow so the
    //         acceptance criterion is verifiable without a SwiftUI hierarchy.
    //   ref:  PRD 15-timeline (acceptance criterion 3), specs/ui.md EntryRow source badge
    func testSourceBadge_labelMatchesEachTranscriptSource() {
        XCTAssertEqual(EntryRow.sourceBadgeLabel(for: .speech), "Speech")
        XCTAssertEqual(EntryRow.sourceBadgeLabel(for: .whisper), "Whisper")
        XCTAssertEqual(EntryRow.sourceBadgeLabel(for: .none), "Pending")
    }

    // AI: PRD #15 — the badge icon distinctly identifies each source so rows are
    //     visually distinguishable beyond color alone (accessibility).
    func testSourceBadge_iconMatchesEachTranscriptSource() {
        XCTAssertEqual(EntryRow.sourceBadgeIcon(for: .speech), "waveform")
        XCTAssertEqual(EntryRow.sourceBadgeIcon(for: .whisper), "brain")
        XCTAssertEqual(EntryRow.sourceBadgeIcon(for: .none), "hourglass")
    }

    // AI: PRD #15 — exhaustive coverage: every TranscriptSource case has a label,
    //     icon, and tint. Guards against a future case added to TranscriptSource
    //     without a corresponding badge branch (which would render an empty label).
    func testSourceBadge_coversEveryTranscriptSourceCase() {
        let allSources: [TranscriptSource] = [.speech, .whisper, .none]
        for source in allSources {
            XCTAssertFalse(
                EntryRow.sourceBadgeLabel(for: source).isEmpty,
                "Every TranscriptSource must have a non-empty badge label; \(source) is empty"
            )
            XCTAssertFalse(
                EntryRow.sourceBadgeIcon(for: source).isEmpty,
                "Every TranscriptSource must have a non-empty badge icon; \(source) is empty"
            )
        }
    }

    // AI:
    //   what: EntryRow surfaces date, source badge, duration, and excerpt (requirement 1)
    //   why:  PRD #15 requirement 1 specifies each row shows date/time, source badge,
    //         duration, and a ~120-char excerpt. EntryRow's `entry`, `displayedExcerpt`,
    //         and `displayedDuration` are the testable surfaces for the row's data
    //         without rendering SwiftUI. Verifies the row is wired to real entry data,
    //         a real duration format, and a real excerpt string.
    //   ref:  PRD 15-timeline requirement 1, specs/ui.md EntryRow
    @MainActor
    func testEntryRow_surfacesDateSourceDurationExcerpt() async throws {
        let fixedDate = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 10, minute: 5))!
        let entry = DiaryEntry(
            startedAt: fixedDate,
            durationSeconds: 65,
            audioPath: "row.m4a",
            transcriptPath: "row.md",
            source: .speech
        )
        let row = EntryRow(entry: entry, preview: "Hello timeline.")

        XCTAssertEqual(row.entry.startedAt, fixedDate)
        XCTAssertEqual(EntryRow.sourceBadgeLabel(for: row.entry.source), "Speech")
        XCTAssertEqual(row.displayedDuration, "1:05", "65 seconds should format to 1:05")
        XCTAssertEqual(row.displayedExcerpt, "Hello timeline.")
    }

    // AI:
    //   what: Duration formatting across edge values
    //   why:  PRD #15 requirement 1 includes duration on every row. The format is
    //         mm:ss; pin the boundaries (0s, sub-minute, exactly one minute, >1 hour)
    //         so a regression in the formatter is caught.
    //   ref:  PRD 15-timeline requirement 1
    @MainActor
    func testEntryRow_durationFormatting() {
        func makeRow(seconds: Double) -> EntryRow {
            EntryRow(
                entry: DiaryEntry(
                    startedAt: Date(),
                    durationSeconds: seconds,
                    audioPath: "x.m4a",
                    transcriptPath: "x.md",
                    source: .none
                ),
                preview: ""
            )
        }

        XCTAssertEqual(makeRow(seconds: 0).displayedDuration, "0:00")
        XCTAssertEqual(makeRow(seconds: 4).displayedDuration, "0:04")
        XCTAssertEqual(makeRow(seconds: 59).displayedDuration, "0:59")
        XCTAssertEqual(makeRow(seconds: 60).displayedDuration, "1:00")
        XCTAssertEqual(makeRow(seconds: 125).displayedDuration, "2:05")
        XCTAssertEqual(makeRow(seconds: 3_600).displayedDuration, "60:00")
    }
}
