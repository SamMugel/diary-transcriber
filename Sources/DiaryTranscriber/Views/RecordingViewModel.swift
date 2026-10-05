import SwiftUI

// AI:
//   what: RecordingViewModel — @MainActor observable backing RecordingView
//   why:  specs/ui.md: liveTranscript, elapsed, isFinalizing state;
//         orchestrates AudioRecorder and SpeechTranscriber
//   ref:  specs/ui.md RecordingViewModel, D-0004, D-0008

@MainActor
@Observable
public final class RecordingViewModel {

    public var liveTranscript: String = ""
    public var elapsed: Double = 0
    public var isFinalizing = false
    public var permissionMessage: String = ""

    // AI: PRD #18 — typed error surfaced when transcription fails after recording.
    //     `stop()` sets it on a `.failed` update so the view can show a non-empty
    //     failure reason instead of silently persisting an empty transcript.
    public var transcriptionError: String = ""

    private let recorder: AudioRecorder
    private let speechTranscriber: SpeechTranscriber?
    // AI: PRD #28 — shared TranscriptionService injected from AppEnvironment. Optional + nil-default
    //     so existing tests that construct `RecordingViewModel()` keep compiling. #28 only wires it
    //     here; stop() drives it in #18.
    private let transcriptionService: TranscriptionService?
    private(set) var handle: RecordingHandle?
    // AI: PRD #24 — exposed as `internal private(set)` so the recycled `@testable`
    //     test target can assert that `teardown()` cancels the timer/live-stream
    //     Tasks. Writes stay private to the class; reads widen only across the
    //     module boundary (no public API change).
    internal private(set) var timer: Task<Void, Never>?
    internal private(set) var liveStreamTask: Task<Void, Never>?

    /// The resulting DiaryEntry after recording stops, or nil if recording
    /// has not completed (or was cancelled).
    public private(set) var completedEntry: DiaryEntry?

    /// The final `Transcript` produced by the transcription pipeline, if any.
    /// `ContentView.finishRecording` reads this to persist the transcript text
    /// via `DiaryStore.setTranscript` AFTER `store.append` creates the manifest row.
    //
    // AI:
    //   what: completedTranscript — out-parameter from the recorder's transcription pipeline
    //   why:  PRD #18 — the manifest row is created by `finishRecording`'s `store.append`, NOT by
    //         `stop()`; `setTranscript` can only be called after the row exists. So `stop()` runs the
    //         transcription pipeline and exposes the resulting Transcript (or nil on failure/no-op)
    //         for `finishRecording` to persist atomically. Keeping this on the VM also lets `RecordingView`
    //         propagate it through the onCompleted closure.
    //   ref:  PRD 18-transcription-post-recording-pipeline
    public private(set) var completedTranscript: Transcript?

    public init(
        recorder: AudioRecorder = AudioRecorder(),
        speechTranscriber: SpeechTranscriber? = nil,
        transcriptionService: TranscriptionService? = nil
    ) {
        self.recorder = recorder
        // AI: Default to a shared SpeechTranscriber when not injected. Tests can
        //     pass nil to skip live transcription entirely.
        self.speechTranscriber = speechTranscriber ?? SpeechTranscriber()
        self.transcriptionService = transcriptionService
    }

    public var isRecording: Bool { handle != nil && !isFinalizing }

    public func start() async {
        do {
            liveTranscript = ""
            elapsed = 0
            isFinalizing = false
            completedEntry = nil
            completedTranscript = nil
            handle = try await recorder.start()
            startTimer()
            startLiveStream()
        } catch {
            // Surface error to the view for display.
            permissionMessage = error.localizedDescription
            liveTranscript = "Error: \(error.localizedDescription)"
        }
    }

    // AI:
    //   what: stop() — halt recording, run transcription pipeline, expose the final Transcript
    //   why:  PRD #18 — once `recorder.stop()` returns a non-empty audio URL, drive the injected
    //         TranscriptionService's `AsyncStream<TranscriptUpdate>`:
    //           - `.partial(String)` updates `liveTranscript` (live feedback in the finalizing view);
    //           - `.final(Transcript)` updates the in-memory entry's `source` and is exposed via
    //             `completedTranscript` so `ContentView.finishRecording` can persist the transcript
    //             text via `store.setTranscript` AFTER `store.append` creates the manifest row
    //             (`setTranscript` is a no-op if the row doesn't exist). This is the lifecycle
    //             constraint that makes `stop()` not call `setTranscript` directly.
    //           - `.failed(String)` sets `transcriptionError` and leaves `completedTranscript = nil`;
    //             the entry still flows through `onCompleted` with `.none` source so the timeline
    //             shows the recorded audio (audio retained on disk per acceptance criterion #4) and
    //             the user can re-transcribe (PRD #26).
    //         If no TranscriptionService is wired (e.g., tests, legacy path), commit the entry with
    //         `.none` source so the recorded audio is never orphaned.
    //   ref:  PRD 18-transcription-post-recording-pipeline
    public func stop() async {
        guard handle != nil, !isFinalizing else { return }
        isFinalizing = true
        transcriptionError = ""
        completedTranscript = nil
        cancelTimer()
        cancelLiveStream()

        do {
            let audioURL = try await recorder.stop()
            var entry = DiaryEntry(
                startedAt: handle!.startedAt,
                durationSeconds: handle!.elapsed(),
                audioPath: audioURL.path,
                transcriptPath: audioURL.deletingPathExtension()
                    .appendingPathExtension("md").path,
                source: .none
            )

            // AI: Drive the transcription pipeline only when a shared
            //     TranscriptionService is injected. Without one (legacy path),
            //     commit the entry with `.none` source so the recorded audio is
            //     never orphaned. The pipeline iteration terminates because
            //     TranscriptionService's `continuation.finish()` is reached on
            //     every path (speech-success, whisper-success, both-failed,
            //     no-engines), so this loop cannot hang beyond the service's
            //     internal timeout.
            if let service = transcriptionService {
                let stream = await service.transcribe(at: audioURL)
                var finalTranscript: Transcript?
                for await update in stream {
                    switch update {
                    case .partial(let text):
                        liveTranscript = text
                    case .final(let transcript):
                        finalTranscript = transcript
                    case .failed(let message):
                        transcriptionError = message
                    }
                }

                if let transcript = finalTranscript {
                    entry.source = transcript.source
                    completedTranscript = transcript
                }
            }

            completedEntry = entry
        } catch RecorderError.notRecording {
            // AI: Idempotent stop path — recorder already stopped. Reset UI
            //     without surfacing an error or emitting completedEntry.
            liveTranscript = ""
            completedEntry = nil
        } catch {
            liveTranscript = "Error: \(error.localizedDescription)"
        }

        isFinalizing = false
        handle = nil
    }

    // AI:
    //   what: cancelRecording() — stop recording without running the transcription pipeline
    //   why:  PRD #22 — when the user cancels or the sheet is dismissed externally while
    //         recording (completedEntry == nil), we must tear down the recorder, timer,
    //         and live stream so no microphone session, background tasks, or partial
    //         .m4a files are left orphaned. Unlike `stop()`, this does NOT create a
    //         `completedEntry` or run the transcription pipeline — the recording is
    //         simply discarded.
    //   ref:  PRD 22-recording-sheet-cancel-clear
    public func cancelRecording() async {
        guard !isFinalizing else { return }
        cancelTimer()
        cancelLiveStream()

        // Stop the underlying recorder without capturing its output URL for a
        // completedEntry. The caller (RecordingView) is responsible for cleaning
        // up any partial .m4a file at `handle.outputURL`.
        if handle != nil {
            do {
                _ = try await recorder.stop()
            } catch {
                // Recorder may already be stopped or never started; the
                // partial-file cleanup in the view is best-effort regardless.
                print("[RecordingViewModel] cancelRecording: recorder.stop() error: \(error.localizedDescription)")
            }
        }

        handle = nil
        completedEntry = nil
        liveTranscript = ""
    }

    // AI:
    //   what: teardown() — unconditional release of all background Tasks owned by the view-model
    //   why:  PRD #24 — when RecordingView is dismissed (sheet, Escape, window close),
    //         the view's .onDisappear must guarantee that the periodic `timer` Task and the
    //         `liveStreamTask` are cancelled and nilled, otherwise they outlive the view-model
    //         and linger in the heap. Unlike `stop()` and `cancelRecording()`, this is meant
    //         to be called *defensively* from any state (idle, recording, finalizing) and
    //         must never crash — it mirrors the Swift rule "teardown should be idempotent".
    //         If recording is active it also halts the underlying recorder (best-effort) so a
    //         microphone session is never left orphaned; if a transcription pipeline is
    //         in-flight (`isFinalizing`), the Tasks it depends on are cancelled so the
    //         in-flight Task cannot resume work after dismissal.
    //   ref:  PRD 24-recording-timer-leak
    public func teardown() async {
        cancelTimer()
        cancelLiveStream()

        // AI: If a recorder session is still active at teardown time, release it.
        //     We do NOT call `cancelRecording()` here because that method guards
        //     on `!isFinalizing` and would no-op during in-flight transcription;
        //     teardown is unconditional. We directly stop the recorder (discarding
        //     the partial file the same way `cancelRecording` does) and clear the
        //     handle so `isRecording` reports false for the discarded view-model.
        if handle != nil {
            do {
                _ = try await recorder.stop()
            } catch {
                // Best-effort; the recorder may already be stopped or never started.
                print("[RecordingViewModel] teardown: recorder.stop() error: \(error.localizedDescription)")
            }
            handle = nil
        }

        // AI: Clear any in-flight transcription state so a finalizing view-model
        //     dismissed mid-stream doesn't leave `isFinalizing` stuck true; the
        //     pipeline Tasks were already cancelled above so no background work
        //     continues. `completedEntry` is left as-is so a completed-but-not-yet
        //     dismissed view-model still propagates the entry through onCompleted.
        isFinalizing = false
    }

    /// Deletes a partial .m4a file left behind after a cancelled recording
    /// (`completedEntry == nil`). Called by `RecordingView` on cancel/dismiss.
    /// Errors are caught and logged only — the file may already be removed or
    /// locked, but we must not let cleanup failures surface to the UI (PRD #22).
    nonisolated public static func removePartialFile(at url: URL?) {
        guard let url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("[RecordingViewModel] Failed to remove partial file \(url.path): \(error.localizedDescription)")
        }
    }

    func appendTranscript(text: String) {
        if liveTranscript.isEmpty {
            liveTranscript = text
        } else {
            liveTranscript += " " + text
        }
    }

    // MARK: - Private: Timer

    private func startTimer() {
        timer?.cancel()
        timer = Task { @MainActor in
            while !Task.isCancelled {
                elapsed = handle?.elapsed() ?? 0
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    // AI: PRD #24 — internal test seam that mirrors `startTimer()` exactly but
    //     does NOT require a microphone (which `start()` would need). Lets the
    //     teardown tests drive a real `Task<Void, Never>?` through the public
    //     `teardown()` path so we assert cancellation on the genuine object.
    #if DEBUG
    internal func startTimerForTest() {
        startTimer()
    }
    #endif

    // MARK: - Private: Live Transcript Stream

    private func startLiveStream() {
        // AI: If no transcriber is wired in (e.g., test that wants to skip live
        //     transcription), bail out early. This keeps the recording loop
        //     decoupled from live speech.
        guard let speechTranscriber else { return }
        cancelLiveStream()
        liveStreamTask = Task { @MainActor in
            // AI: liveStream() returns AsyncStream<String> whose yield values are
            //     cumulative partial results — set, don't append. If the stream
            //     finishes (recognizer unavailable or final result), the loop
            //     exits cleanly. Cancellation via stop() tears down the task.
            let stream = await speechTranscriber.liveStream()
            for await text in stream {
                if Task.isCancelled { break }
                liveTranscript = text
            }
        }
    }

    private func cancelLiveStream() {
        liveStreamTask?.cancel()
        liveStreamTask = nil
    }
}
