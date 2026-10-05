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

    private let recorder: AudioRecorder
    private let speechTranscriber: SpeechTranscriber?
    // AI: PRD #28 — shared TranscriptionService injected from AppEnvironment. Optional + nil-default
    //     so existing tests that construct `RecordingViewModel()` keep compiling. #28 only wires it
    //     here; stop() is unchanged (the actual transcription call lands in #18).
    private let transcriptionService: TranscriptionService?
    private(set) var handle: RecordingHandle?
    private var timer: Task<Void, Never>?
    private var liveStreamTask: Task<Void, Never>?

    /// The resulting DiaryEntry after recording stops, or nil if recording
    /// has not completed (or was cancelled).
    public private(set) var completedEntry: DiaryEntry?

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
            handle = try await recorder.start()
            startTimer()
            startLiveStream()
        } catch {
            // Surface error to the view for display.
            permissionMessage = error.localizedDescription
            liveTranscript = "Error: \(error.localizedDescription)"
        }
    }

    public func stop() async {
        guard handle != nil, !isFinalizing else { return }
        isFinalizing = true
        cancelTimer()
        cancelLiveStream()

        do {
            let audioURL = try await recorder.stop()
            let entry = DiaryEntry(
                startedAt: handle!.startedAt,
                durationSeconds: handle!.elapsed(),
                audioPath: audioURL.path,
                transcriptPath: audioURL.deletingPathExtension()
                    .appendingPathExtension("md").path,
                source: .none
            )
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
