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
    private var timer: Task<Void, Never>?
    private var liveStreamTask: Task<Void, Never>?

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
