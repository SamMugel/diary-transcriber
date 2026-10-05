import Foundation
import Synchronization
#if canImport(Speech)
import Speech
#endif

// AI:
//   what: SpeechTranscriber actor transcribes audio files using Apple's on-device Speech framework
//   why:  D-0004 hybrid transcription: Speech is the primary engine (free, on-device, low-latency);
//         WhisperClient is the fallback when Speech fails or underperforms
//   ref:  specs/transcription.md SpeechTranscriber API, D-0004

public actor SpeechTranscriber {

    private var recognizer: SFSpeechRecognizer?

    // MARK: - Lifecycle

    public init() {
        #if canImport(Speech)
        recognizer = Self.createRecognizer()
        #endif
    }

    // MARK: - Public API

    // AI:
    //   what: liveStream — streams partial transcription results via SFSpeechAudioBufferRecognitionRequest
    //   why:  specs/ui.md RecordingViewModel: "Live transcript updates word-by-word from SpeechTranscriber via AsyncStream";
    //         live recording needs partial results during capture, not a single final pass
    //   ref:  specs/ui.md RecordingViewModel, D-0004, PRD 12 (recording-view)
    //   note: macOS's Speech framework does NOT expose SFSpeechLiveSpeechRecognitionRequest (that class
    //   is iOS/tvOS-only). The macOS-compatible live-API is SFSpeechAudioBufferRecognitionRequest, which
    //   uses the same partial-results callback pattern as transcribe(at:). The stream yields each
    //   bestTranscription snapshot and finishes on isFinal; the underlying SFSpeechRecognitionTask is
    //   held in a Sendable-safe LiveTaskCancel and cancelled on stream termination so the consumer
    //   (RecordingViewModel) tearing down the for-await loop frees the live session. The request is
    //   configured with shouldReportPartialResults = true so the callback delivers intermediate snapshots,
    //   not just the final one. NB: the request is not yet fed live audio buffers in this PRD; that wiring
    //   lives in a follow-up that exposes CMSampleBuffers from AudioRecorder.
    public func liveStream() -> AsyncStream<String> {
        #if canImport(Speech)
        AsyncStream { continuation in
            guard let recognizer, recognizer.isAvailable else {
                // AI: No on-device recognizer (headless CI, missing locale, etc.) — yield zero results and finish.
                continuation.finish()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let holder = LiveTaskCancel()
            holder.set(
                recognizer.recognitionTask(with: request) { result, error in
                    if error != nil { return }
                    guard let result else { return }
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        // AI: Partial results are cumulative, not deltas — replace the live transcript
                        //     with the latest snapshot rather than appending.
                        continuation.yield(text)
                    }
                    if result.isFinal {
                        continuation.finish()
                    }
                }
            )

            // AI: The recognition task runs until cancelled OR until endAudio() is called.
            //     Attach the cancellation to the stream's termination so the consumer
            //     (RecordingViewModel) tearing down the for-await loop frees the live
            //     session. This is the canonical inverse of startLiveStream() —
            //     onTermination matches PRD 12 requirement 4 (live transcript via AsyncStream).
            continuation.onTermination = { _ in
                holder.cancel()
            }
        }
        #else
        // AI: No Speech framework on this platform (Linux CI runner): return a
        //     trivially-finished stream so callers iterating it see zero items.
        AsyncStream { continuation in
            continuation.finish()
        }
        #endif
    }

    public func transcribe(at audioURL: URL) async throws -> Transcript {
        #if canImport(Speech)
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.speechUnavailable
        }

        // Ensure only one recognizer instance exists at a time — actor isolation
        // already serializes access.
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: TranscriptionError.speechError(
                        error.localizedDescription
                    ))
                    return
                }

                guard let result else {
                    continuation.resume(throwing: TranscriptionError.speechError(
                        "Speech recognition returned no results."
                    ))
                    return
                }

                let transcription = result.bestTranscription
                guard !transcription.formattedString.isEmpty else {
                    continuation.resume(throwing: TranscriptionError.speechError(
                        "Speech recognition produced an empty transcript."
                    ))
                    return
                }

                // Confidence: average of per-segment confidences (0 if unknown).
                let confidence = transcription.segments.isEmpty
                    ? nil
                    : transcription.segments.map { Double($0.confidence) }.reduce(0, +)
                        / Double(transcription.segments.count)

                let transcript = Transcript(
                    text: transcription.formattedString,
                    confidence: confidence,
                    source: .speech,
                    isFinal: result.isFinal
                )

                if result.isFinal {
                    continuation.resume(returning: transcript)
                }
            }
        }
        #else
        throw TranscriptionError.speechUnavailable
        #endif
    }

    #if canImport(Speech)
    private nonisolated static func createRecognizer() -> SFSpeechRecognizer? {
        return SFSpeechRecognizer()
    }
    #endif
}

// AI:
//   what: LiveTaskCancel — thread-safe holder for the active SFSpeechRecognitionTask
//   why:  SFSpeechRecognitionTask is not Sendable and lives in the Speech framework;
//         AsyncStream.onTermination runs synchronously on whatever context tears down the stream,
//         not the original creation actor. The holder isolates the single mutable `task` pointer
//         inside a Mutex so cancellation is Sendable-safe and delay-free.
//   ref:  specs/ui.md RecordingViewModel liveTranscript, PRD 12

#if canImport(Speech)
private final class LiveTaskCancel: Sendable {
    // AI: SFSpeechRecognitionTask is an Objective-C class that is not Sendable.
    //     The holder is the single mutator (the recognition-result callback)
    //     and a single consumer (the onTermination handler). Because Mutex<T>
    //     requires T: Sendable in Swift 6, we hold the task behind an
    //     @unchecked Sendable wrapper. The class is `Sendable` but access is
    //     serialized through the mutex, so the concurrency model holds.
    private struct TaskBox: @unchecked Sendable {
        var task: SFSpeechRecognitionTask?
    }

    private let mutex = Mutex(TaskBox())

    func set(_ task: SFSpeechRecognitionTask) {
        mutex.withLock { box in
            box.task = task
        }
    }

    func cancel() {
        mutex.withLock { box in
            box.task?.cancel()
            box.task = nil
        }
    }
}
#endif

// AI:
//   what: TranscriptionError — typed errors for transcription failures
//   why:  D-0004 error taxonomy: speechUnavailable, speechError, whisperError, etc.
//         conforming to LocalizedError per Swift error handling rule 15
//   ref:  specs/transcription.md Error taxonomy table

public enum TranscriptionError: LocalizedError {
    case speechUnavailable
    case speechError(String)
    case whisperError(status: Int)
    case whisperTimeout
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .speechUnavailable:
            "On-device speech recognizer is not available on this device."
        case .speechError(let detail):
            "Speech recognition failed: \(detail)"
        case .whisperError(let status):
            "Whisper API returned HTTP \(status). Check your API key."
        case .whisperTimeout:
            "Whisper API request timed out after 120 seconds."
        case .networkUnavailable:
            "Network unavailable: transcription failed"
        }
    }
}
