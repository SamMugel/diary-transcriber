# Code Review Issues

> Source of truth for PRD generation. Each issue is scoped so an agent can
> emit one focused PRD per item. Ids are stable; severity is P1 (blocks the
> app's primary function) → P4 (polish).
>
> **Reported user symptoms:**
> 1. "There's no function to make a new entry."
> 2. "When I click on record, it plays the animation for starting and stopping recording, but nothing happens."

---

## P1 — Recording produces no transcript (the core feature is missing)

### ISSUE-001 — TranscriptionService is never instantiated or invoked

- **Files:** `App/DiaryTranscriberApp.swift`, `Sources/DiaryTranscriber/Views/RecordingViewModel.swift`, `Sources/DiaryTranscriber/Views/ContentView.swift`
- **Problem:** `TranscriptionService` exists and is fully implemented, but nothing constructs it with a real `WhisperClient` and nothing calls `service.transcribe(at:)`. After `AudioRecorder.stop()`, `RecordingViewModel.stop()` builds a `DiaryEntry` with `source: .none` and an empty transcript — the entry is then persisted with no text. The app's central promise (diary transcriber) never runs.
- **Expected:** When recording stops, the pipeline runs `TranscriptionService.transcribe(at:)` on the finalized audio file and writes the resulting transcript into the entry's `.md` and back into `manifest.json`.
- **Acceptance:** Stopping a 5 s recording results in a non-empty transcript within 10 s for a normal installation (faster on-device if Speech succeeds; longer for Whisper fallback).

### ISSUE-002 — No live transcript streaming during recording

- **Files:** `Sources/DiaryTranscriber/Views/RecordingViewModel.swift`
- **Problem:** `RecordingViewModel.appendTranscript(text:)` is `internal` and only ever called by tests. The recording view shows the placeholder "Live transcript will appear here…" forever. `SpeechTranscriber.transcribe(at:)` is implemented for full-file transcription, never for streaming.
- **Expected:** Even if full-file is the only engine available in v1, the UI must show "Recording… transcription will start when you stop" instead of an empty placeholder, OR stream partial transcription live.
- **Acceptance:** The transcript area is non-empty during recording (or clearly indicates transcription is deferred) and the final transcript appears after stop.

### ISSUE-003 — `RecordingOutputDelegate` race → `stop()` can hang forever

- **Files:** `Sources/DiaryTranscriber/Recording/AudioRecorder.swift` (lines 116–207)
- **Problem:** In `endCapture()`, `output.stopRecording()` is called **before** `await delegate.waitForCompletion()`. `didFinishRecordingTo` is delivered on a background thread and can fire before `waitForCompletion` enters `withCheckedContinuation`. In that case `continuation` is still `nil`, the callback's `cont?.resume()` is a no-op, and `waitForCompletion` awaits a continuation that nothing will resume. Side effects:
  - The `continuation` field is mutated from MainActor (`waitForCompletion`) and from the AVFoundation delegate thread (the callback) without synchronization — a data race.
  - `waitForCompletion()` is `@MainActor` but is called from the `AudioRecorder` actor; the cross-actor hop widens the window for the race.
- **Expected:** A frame for `output.stopRecording()` → `didFinishRecordingTo` that is robust to out-of-order delivery and safe across all threads.
- **Acceptance:** 50 sequential `start()→stop()` cycles complete in <2 s each with no hanguts; `Thread Sanitizer` + `swift test` clean.

### ISSUE-004 — Microphone permission flow may not work on macOS

- **Files:** `Sources/DiaryTranscriber/Recording/PermissionManager.swift`
- **Problem:** `AVCaptureDevice.authorizationStatus(for: AVMediaType.audio)` and `requestAccess(for:)` are the iOS-style APIs. On macOS the status can be `.authorized` immediately or `.notDetermined` with no system prompt, and `requestAccess`'s callback may never fire. If `requestAccess` does not call back, `requestMicrophoneAccess()`'s `withCheckedThrowingContinuation` never resumes → `start()` hangs; the recording view shows neither progress nor a clear error.
- **Expected:** A macOS-appropriate permission path. At minimum: timeout on the permission call, explicit error surfaced to the user when `.denied`, and retry/recovery guidance ("Open System Settings → Privacy → Microphone") rather than a silent hang.
- **Acceptance:** `swift test --sanitize=thread` is clean and a first-launch attempt to record either prompts correctly, fails fast, or guides the user to Settings within 5 s.

---

## P1 — Recording sheet fails to produce/dismiss an entry

### ISSUE-005 — No Cancel path; `onCancel` callback is never wired

- **Files:** `Sources/DiaryTranscriber/Views/RecordingView.swift`, `Sources/DiaryTranscriber/Views/ContentView.swift`
- **Problem:** `RecordingView` accepts an `onCancel` continuation but no view element triggers it. `.interactiveDismissDisabled(isRecording || isFinalizing)` prevents swipe-close during recording, but `.notRecording` state after a failed start offers no obvious dismissal. If the sheet closes externally (window close, Escape) while `started—no handle—no completedEntry`, neither `onCompleted` nor `onCancel` fires; `ListViewModel.isRecording` stays `true` and the New Entry toolbar button is forever disabled.
- **Expected:** A visible Cancel/Close button in all states; `.onDisappear { onCancel() }` fallback to reset `ListViewModel.isRecording`; on dismiss-without-completion the partial audio file is deleted.
- **Acceptance:** Closing the recording sheet at any state returns the app to a clean cancellable state; `isRecording` is `false` afterwards; no orphan `.m4a` files remain in `~/Documents`.

### ISSUE-006 — `stop()` builds an `DiaryEntry` from a possibly-empty URL

- **Files:** `Sources/DiaryTranscriber/ViewReuse/RecordingViewModel.swift` (lines 45–67), `Sources/DiaryTranscriber/Recording/AudioRecorder.swift` (stop returns `URL(fileURLWithPath: "")`)
- **Problem:** `AudioRecorder.stop()` returns an empty sentinel URL when not recording. `RecordingViewModel.stop()` unconditionally constructs a `DiaryEntry` from that URL (`audioPath = ""`) and sets `completedEntry`. The downstream `finishRecording` then calls `FileManager.moveItem(at: URL(filePath: ""), to: …)` which throws; the entry is dropped but `onCompleted` was already invoked, leaving an inconsistent state.
- **Expected:** `AudioRecorder.stop()` should throw `RecorderError.notRecording` (or similar) when no recording is active; `RecordingViewModel.stop()` should not emit `completedEntry` on failure.
- **Acceptance:** Calling `start()` then `stop()` returns a valid entry; calling `stop()` without `start()` produces no `completedEntry` and no UI side-effects.

### ISSUE-007 — `RecordingViewModel.timer` Task can leak

- **Files:** `Sources/DiaryTranscriber/Views/RecordingViewModel.swift` (lines 79–92)
- **Problem:** `startTimer()` spawns a `Task { while !Task.isCancelled { ... await Task.sleep(...) } }`. It is cancelled only by `cancelTimer()` from `stop()`. If the `RecordingView` disappears via non-`stop()` paths (sheet dismissal, app termination), the timer keeps running.
- **Expected:** Cancel on `RecordingView.onDisappear`/`.task` teardown; expose a `teardown()` method on the view-model.
- **Acceptance:** After closing the sheet at any state, no `Task` related to the old view-model remains in the heap.

### ISSUE-008 — `finishRecording` swallows persistence failures

- **Files:** `Sources/DiaryTranscriber/Views/ContentView.swift` (lines 46–90)
- **Problem:** The `catch` in `finishRecording` only calls `await refresh()`. If `moveItem` or `store.append` fails (disk full, empty URL, permission), the user sees no indication; the audio file may be orphaned in `~/Documents`, no entry appears in the timeline, and the recording-time data is silently lost.
- **Expected:** Surface a non-fatal error banner/toast with "Audio saved to ~/Documents, entry could not be saved"; optionally retry persist.
- **Acceptance:** Failed append shows a clear message and the user can retry without losing the audio file.

---

## P2 — Core feature gaps / wired-up gaps that block usability

### ISSUE-009 — Re-transcribe button handler is empty

- **Files:** `Sources/DiaryTranscriber/Views/EntryDetailView.swift` (lines 49–52), `Sources/DiaryTranscriber/Views/EntryDetailViewModel.swift`
- **Problem:** The "Re-transcribe" button (shown when `entry.source == .none`) has an empty action closure. There is no call from view-model to `TranscriptionService`.
- **Expected:** Clicking Re-transcribe runs `TranscriptionService.transcribe(at: store.url(for: entry))`, streams the updates, updates the transcript text live, and sets `entry.source` on completion.
- **Acceptance:** Awaiting a re-transcribe displays partial results and finalizes the entry with `source == .speech` or `.whisper` (or shows the failure message with the button still enabled).

### ISSUE-010 — Transcript excerpt is always empty in the timeline

- **Files:** `Sources/DiaryTranscriber/Views/ContentView.swift` (lines 286–289 `EntryRow.excerpt`)
- **Problem:** `excerpt` returns the literal `""` with a `// No transcript text is available in the model` comment. The timeline rows show only timestamps and duration — no preview. Combined with the missing transcription (ISSUE-001), this is why users "see nothing" after recording.
- **Expected:** Load the first ~120 characters of the entry's `.md` transcript (lazily, from `DiaryStore.data(for:)` or a dedicated `excerpt(for:)` API) and show it truncated with ellipsis.
- **Acceptance:** Timeline rows for transcribed entries show a truncated transcript preview at ≤1 line.

### ISSUE-010b — `TranscriptionService` is never constructed with a valid Whisper client

- **Files:** `App/DiaryTranscriberApp.swift`, `Sources/DiaryTranscriber/Views/SettingsViewModel.swift`, `Sources/DiaryTranscriber/Models/TranscriptSettings.swift`
- **Problem:** `TranscriptionService` default `init()` has `whisperClient: WhisperClient? = nil`. Nothing reads the API key from Keychain and constructs `WhisperClient(apiKey:)` at app launch or when settings change. If a TranscriptionService is ever wired (per ISSUE-001), it would silently skip Whisper fallback.
- **Expected:** App startup builds a single `TranscriptionService` with `whisperClient` tied to the current Keychain API key. When the user edits the API key, the service reloads (or a new client is produced).
- **Acceptance:** With an API key set and Speech disabled/failed, transcription succeeds via Whisper.

### ISSUE-011 — `TranscriptSettings` not persisted across restarts

- **Files:** `Sources/DiaryTranscriber/Models/TranscriptSettings.swift`, `Sources/DiaryTranscriber/Views/SettingsViewModel.swift`
- **Problem:** `TranscriptSettings` is `Codable` but never written to disk. `SettingsViewModel.transcriptionSettings = TranscriptSettings()` is a fresh default each run; `useOnDeviceSpeech` and `useWhisperFallback` are reset on restart. Only the API key (Keychain) and folder/mic (UserDefaults) survive.
- **Expected:** Persist toggles to `UserDefaults` (or `settings.json`) and reload on init.
- **Acceptance:** Toggle a setting, restart the app, verify the toggle holds.

### ISSUE-012 — SecureField API-key binding reads Keychain on every keystroke

- **Files:** `Sources/DiaryTranscriber/Views/SettingsView.swift` (lines 52–55), `Sources/DiaryTranscriber/Models/TranscriptSettings.swift` (apiKey get/set)
- **Problem:** Each keystroke in the API key field writes the whole key to Keychain (`saveAPIKey`) and reads it back on the next redraw (`loadAPIKey`). On long journeys the field can briefly desync; calling `SecItemDelete → SecItemAdd` per keystroke is heavy and can race on slow Keychain services.
- **Expected:** Use a local in-memory `@State` buffer for input; commit to Keychain on `.onSubmit`, `.onDisappear`, or a Save button.
- **Acceptance:** Typing smoothly into the API key field does not cause freezes or duplicated characters; the saved value matches what was typed.

---

## P3 — Robustness & lifecycle

### ISSUE-013 — `EntryDetailViewModel` never cleans up `AudioPlayer`

- **Files:** `Sources/DiaryTranscriber/Views/EntryDetailView.swift`, `Sources/DiaryTranscriber/Playback/AudioPlayer.swift`
- **Problem:** `AudioPlayer.startTimer()` schedules a repeating `Timer` that is only stopped when playback ends or `stop()`/`cleanup()` is called. `EntryDetailView.onDisappear` saves the transcript but does not call `audioPlayer.cleanup()`. Navigating away mid-playback leaves the timer (and the AVAudioPlayer) running.
- **Expected:** `.onDisappear { viewModel.audioPlayer.cleanup() }` (or `stop()`) on `EntryDetailView`.
- **Acceptance:** After navigating away from an entry mid-playback, no `AVAudioPlayer` instance remains active.

### ISSUE-014 — `FileSystemWatcher` is implemented but never used

- **Files:** `Sources/DiaryTranscriber/Storage/FileSystemWatcher.swift`, `Sources/DiaryTranscriber/Views/ContentView.swift`
- **Problem:** The watcher is fully built (polling + debounce) but no view-model subscribes to it. The timeline only refreshes via the toolbar Refresh button or after `finishRecording`. External changes (a third-party file dropped in, a deleted entry, a manifest update from transcription) are invisible until the user clicks Refresh.
- **Expected:** `ListViewModel` holds a `FileSystemWatcher`, subscribes to its `AsyncStream<URL>`, and calls `refresh()` on each debounced emission.
- **Acceptance:** Dropping a new `.m4a` into the diary folder (and side-loading a matching manifest row) causes the timeline to update within ~2 s without manual refresh.

### ISSUE-015 — Format of `DiaryEntry` written to transcript `.md` after transcription is undefined

- **Files:** `Sources/DiaryTranscriber/Storage/DiaryStore.swift` (`append` writes empty `.md`), specs/storage.md
- **Problem:** `append(entry:)` writes an empty `.md` placeholder. There is no API on `DiaryStore` that writes the actual transcript text back to the file, nor code that re-uses `update(entry:)` to write transcript content. So even if ISSUE-001 is fixed, the `.md` is never updated with the transcript.
- **Expected:** A `DiaryStore.setTranscript(for: id, source: TranscriptSource, text: String)` (or the existing `update`) that writes the transcript text into the `.md` and bumps `manifest.updatedAt`.
- **Acceptance:** After transcription, `manifest.json` shows the new `source` and `updatedAt`, and the `.md` contains the transcript text.

### ISSUE-016 — Layout: EmptyState mentions a "New Entry" button but only the toolbar button exists

- **Files:** `Sources/DiaryTranscriber/Views/ContentView.swift` (lines 98–116 EmptyState)
- **Problem:** First-launch users see "No entries yet. Click 'New Entry'…". On macOS toolbars, the New Entry button is small and unlabeled unless `primaryAction` shows the label — visually hidden from the kind of user who'd be looking for a centered CTA. The empty state has no actionable button.
- **Expected:** Center a prominent CTA Button ("New Entry") inside `EmptyState` that calls the same `startRecording()` action.
- **Acceptance:** From a fresh installation, a user can start their first recording within one click without scanning the toolbar.

### ISSUE-017 — `ListViewModel.init` fires a detached refresh task

- **Files:** `Sources/DiaryTranscriber/Views/ContentView.swift` (lines 20–23)
- **Problem:** `init(store:)` starts `Task { await refresh() }` and discards the handle. If the view is destroyed during init (unlikely but possible during fast navigation), the task may outlive the view-model and touch `@Observable` state after deallocation.
- **Expected:** Move initial refresh into `.task` on `ContentView.body` (which auto-cancels on disappear), or hold the task in a stored property.
- **Acceptance:** No leaked task after window/frame destruction; `@MainActor` state is touched only from the visible view-model.

### ISSUE-018 — `RecordingOutputDelegate` is `@unchecked Sendable` with no atomic field

- **Files:** `Sources/DiaryTranscriber/Recording/AudioRecorder.swift` (lines 182–207)
- **Problem:** The `captureError: Error?` and `continuation: CheckedContinuation<Void, Never>?` fields are accessed concurrently across MainActor and the AVFoundation delegate thread. The `@unchecked Sendable` annotation hides the race; `Thread Sanitizer` will flag this.
- **Expected:** Wrap both fields in `Mutex` (Swift 6.0 `synchronization`) or refactor to a single-threaded mailbox.
- **Acceptance:** `swift test --sanitize=thread` passes.

---

## P3 — Test coverage

### ISSUE-019 — No integration test for the record → finalize → persist pipeline

- **Files:** `Tests/DiaryTranscriberTests/AudioRecorderTests.swift`, `Tests/DiaryTranscriberTests/RecordingViewModelTests.swift`, `Tests/DiaryTranscriberTests/TimelineTests.swift`
- **Problem:** `AudioRecorderTests` only checks `stop()` is idempotent and `RecordingHandle` properties. `RecordingViewModelTests` checks no-op `stop()` and `appendTranscript`. No test exercises the actual success path: `start()` → wait briefly → `stop()` → `completedEntry` non-nil → `finishRecording` → entry appears in timeline.
- **Expected:** A test that uses a stub/fake `AudioRecorder` returning a fake `.m4a`, drives `RecordingViewModel` through start→stop, asserts `completedEntry`, and asserts `ListViewModel.finishRecording` produces a persisted `DiaryEntry`.
- **Acceptance:** One end-to-end pipeline test in CI; it runs in <2 s and doesn't actually require a real microphone.

### ISSUE-020 — Missing tests for transcription orchestration

- **Files:** `Tests/DiaryTranscriberTests/TranscriptionServiceTests.swift`
- **Problem:** Existing tests use bogus files and assert only that "at least one update emits". They don't verify the partial→final sequencing, the fallback trigger when Speech returns low-confidence text, or the dirty-path: Speech succeeds → `.final` emitted → no Whisper call.
- **Expected:** Mock `SpeechTranscriber` and `WhisperClient` controllably; assert exactly which engine runs and what the final TranscriptionContent is.
- **Acceptance:** Tests for: speech-only success, whisper-only success, speech-failed-fallback-to-whisper, both-failed.

---

## P4 — Polishing & build

### ISSUE-025 — `SpeechTranscriberTests` hangs headless CI (liveStream never returns)

- **Files:** `Tests/DiaryTranscriberTests/SpeechTranscriberTests.swift`, `Sources/DiaryTranscriber/Transcription/SpeechTranscriber.swift`
- **Problem:** `SpeechTranscriber()` constructs an `SFSpeechRecognizer` which is `nil` on the headless CI agent. `testLiveStream_returnsEmptyStreamWhenSpeechUnavailable` and `testLiveStream_canBeCancelledWithoutError` call `liveStream()`, whose `onTermination` cancellation does not fire if the underlying recognizer is `nil` and the stream has no producer; `for await text in stream` blocks forever. `testTranscribe_nonExistentFile_raisesSpeechUnavailableOrSpeechError` can also stall on a `nil` recognizer path. Running the full `swift test` suite therefore hangs with no output beyond `Build complete!`. Reproducible on `main` with `swift test --filter SpeechTranscriberTests` (no test result lines emitted; killed by timeout). NOT a regression from PRD #28 — `SpeechTranscriber.swift` and this test file are untouched by #28; the hang was surfaced while validating #28 and confirmed against the clean tree.
- **Expected:** `liveStream()` must guarantee the stream finishes (yields zero values and returns) when `SFSpeechRecognizer` is `nil` or unavailable, rather than awaiting a producer that will never run. `transcribe(at:)` should also finalize on all unreachable-recognizer paths.
- **Acceptance:** `swift test --filter SpeechTranscriberTests` completes in <5 s on a headless machine with all assertions passing; `swift test` (full suite) no longer hangs.
- **Out of scope for PRD #28 commit:** Documented only; `SpeechTranscriber` cancellation/finalization fix belongs in its own PRD (speech-transcriber resilience / liveStream finalization).



- **Files:** `scripts/package.sh`
- **Problem:** The script sets `PROJECT_ROOT` but never `cd`s there. `xcodebuild -scheme DiaryTranscriber` searches the current directory for the workspace; invoked from anywhere else, it fails with "Scheme not found".
- **Expected:** `cd "$PROJECT_ROOT"` before `xcodebuild`.
- **Acceptance:** `cd /tmp && /Users/.../scripts/package.sh` succeeds.

### ISSUE-022 — Strict concurrency flag diverges from AGENTS.md

- **Files:** `Package.swift`, `AGENTS.md`
- **Problem:** AGENTS.md mandates `-strict-concurrency=complete`; `Package.swift` sets only `.swiftLanguageMode(.v6)`. Swift 6.0 language mode implies strict concurrency by default, but the explicit flag would make intent clear and future-proof against toolchain drift.
- **Expected:** Either pin `.swiftLanguageMode(.v6)` with an explicit comment confirming it enforces strict concurrency, or add `.unsafeFlags(["-strict-concurrency=complete"])` if needed by an older toolchain.
- **Acceptance:** `swift build` produces no concurrency warnings.

### ISSUE-023 — `Info.plist` missing `NSSpeechRecognitionUsageDescription`

- **Files:** `Resources/Info.plist`
- **Problem:** `SFSpeechRecognizer` may surface a one-time permission/rationale on some Mac configurations. Declaring `NSSpeechRecognitionUsageDescription` (an iOS key but widely respected) and ensuring `NSMicrophoneUsageDescription` is in the right bundle path is the cleaner path for Store submission. Currently only `NSMicrophoneUsageDescription` is set.
- **Expected:** Add `NSSpeechRecognitionUsageDescription` describing voice transcription.
- **Acceptance:** No system prompts without a rationale; `plutil` confirms the key in the final Info.plist.

### ISSUE-024 — `AGENTS.md` notes `NSAllowsArbitraryLoads: false` but no ATS exception audit

- **Files:** `Resources/Info.plist`
- **Problem:** ATS permits exceptions only for `api.openai.com` (good). However this is a hard requirement that OpenAI could rotate endpoints without notice; no fallback or error handling exists for TLS-rejected connections beyond `whisperError(0)`.
- **Expected:** Document the ATS exception as a known risk; ensure non-2xx HTTP 0 (i.e. ATS rejection) is reported as `whisperError(0)` and surfaced clearly to the user.
- **Acceptance:** Disconnecting the network and running transcription yields a clear "network unavailable" toast, not a silent hang.

---

## Cross-cutting observations (for PRD authors)

- **No dependency injection container.** `RecordingView()` and `RecordingViewModel()` default-construct `AudioRecorder()`; `DiaryStore` is the only injection point (via `ContentView`). To wire `TranscriptionService` cleanly (ISSUE-001, ISSUE-010b), introduce a small `AppEnvironment` or `@Environment`-delivered service.
- **`TranscriptionSettings` is duplicated** as `TranscriptionService`'s constructor param and `SettingsViewModel`'s state. They can drift. Single source of truth + observation is required.
- **`Keychain` writes are non-atomic** with UserDefaults writes. A fresh SettingsView with both persisted (ISSUE-011) must keep ordering consistent.
- **Tests use `@testable import DiaryTranscriberCore`** — all internal types (`RecorderError`, `PermissionManager`, `KeychainHelper`, `Manifest`) are reachable. PRDs should retain this and avoid making needed-by-tests types `private`.
- **No CI surfaced** in this review; if `swift test --sanitize=thread` is added (per ISSUE-003/018), make sure CI runs both sanitizers.

---

## Suggested PRD grouping (one PRD per issue, or merge where noted)

| PRD Slug | Issue(s) | Priority | Depends On |
|---|---|---|---|
| transcription-post-recording-pipeline | ISSUE-001, ISSUE-015 | P1 | audio-recorder, whisper-client, transcription-service, diary-store |
| live-transcript-streaming | ISSUE-002 | P1 | transcription-post-recording-pipeline, speech-transcriber |
| recording-delegate-deadlock | ISSUE-003, ISSUE-018 | P1 | audio-recorder |
| macos-microphone-permission | ISSUE-004 | P1 | permission-manager, audio-recorder |
| recording-sheet-cancel-clear | ISSUE-005 | P1 | recording-view |
| recorder-stop-error-handling | ISSUE-006 | P1 | audio-recorder |
| recording-timer-leak | ISSUE-007 | P2 | recording-view |
| finish-recording-error-feedback | ISSUE-008 | P2 | content-view |
| retranscribe-button | ISSUE-009 | P2 | entry-detail-view, transcription-service |
| timeline-excerpt | ISSUE-010 | P2 | diary-store, content-view |
| transcription-service-bootstrap | ISSUE-010b | P2 | transcription-service, settings-view |
| transcript-settings-persistence | ISSUE-011 | P2 | settings-view |
| api-key-input-binding | ISSUE-012 | P2 | settings-view |
| audio-player-cleanup | ISSUE-013 | P3 | audio-player, entry-detail-view |
| filesystem-watcher-hookup | ISSUE-014 | P3 | file-system-watcher, content-view |
| empty-state-cta | ISSUE-016 | P3 | content-view |
| list-viewmodel-init-task | ISSUE-017 | P4 | content-view |
| end-to-end-record-pipeline-tests | ISSUE-019 | P3 | test-suites |
| transcription-service-tests | ISSUE-020 | P3 | test-suites |
| package-script-cwd | ISSUE-021 | P4 | packaging |
| strict-concurrency-explicit | ISSUE-022 | P4 | project-setup |
| info-plist-speech-recognition-key | ISSUE-023 | P4 | packaging |
| ats-handling-audit | ISSUE-024 | P4 | whisper-client |
| speech-transcriber-livestream-finalize | ISSUE-025 | P3 | speech-transcriber |
