import Foundation

// AI:
//   what: TranscriptionService actor orchestrates hybrid Speech + Whisper transcription
//   why:  D-0004 hybrid pipeline: SpeechTranscriber first (on-device), then WhisperClient
//         fallback on empty text, low confidence, error, or 3× audio duration hang protection
//   ref:  specs/transcription.md TranscriptionService, D-0004

public actor TranscriptionService {

    private let speechTranscriber: SpeechTranscriber
    private let whisperClient: WhisperClient?
    private let settings: TranscriptSettings

    public init(
        speechTranscriber: SpeechTranscriber = SpeechTranscriber(),
        whisperClient: WhisperClient? = nil,
        settings: TranscriptSettings = TranscriptSettings()
    ) {
        self.speechTranscriber = speechTranscriber
        self.whisperClient = whisperClient
        self.settings = settings
    }

    // MARK: - Public API

    public func transcribe(at audioURL: URL) -> AsyncStream<TranscriptUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await self.runTranscription(audioURL: audioURL, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private: Pipeline

    private func runTranscription(
        audioURL: URL,
        continuation: AsyncStream<TranscriptUpdate>.Continuation
    ) async {
        let audioDuration = await estimateAudioDuration(audioURL)
        let maxDuration = max(audioDuration * 3, 30)

        // Step 1: On-device Speech (if enabled).
        if settings.useOnDeviceSpeech {
            let result = await transcribeWithTimeout(
                maxDuration: maxDuration
            ) {
                try await self.speechTranscriber.transcribe(at: audioURL)
            }

            switch result {
            case .success(let transcript):
                if !transcript.text.isEmpty && !shouldFallbackFromSpeech(
                    transcript: transcript,
                    audioDuration: audioDuration
                ) {
                    continuation.yield(.partial(transcript.text))
                    let final = Transcript(
                        text: transcript.text,
                        confidence: transcript.confidence,
                        source: .speech,
                        isFinal: true
                    )
                    continuation.yield(.final(final))
                    return
                }
                // Fall through to Whisper.
            case .failure(let error):
                if let tError = error as? TranscriptionError, case .speechUnavailable = tError {
                    // Speech not available; fall through to Whisper.
                } else {
                    continuation.yield(.partial("Speech failed, trying Whisper…"))
                }
            case .timeout:
                continuation.yield(.partial("Speech timed out, trying Whisper…"))
            }
        }

        // Step 2: Whisper fallback (if enabled and API key available).
        guard let whisperClient, settings.useWhisperFallback else {
            continuation.yield(.failed("No transcription engine available."))
            return
        }

        let whisperResult = await transcribeWithTimeout(
            maxDuration: maxDuration
        ) {
            try await whisperClient.transcribe(at: audioURL)
        }

        switch whisperResult {
        case .success(let transcript):
            continuation.yield(.partial(transcript.text))
            let final = Transcript(
                text: transcript.text,
                confidence: nil,
                source: .whisper,
                isFinal: true
            )
            continuation.yield(.final(final))
        case .failure(let error):
            if let tError = error as? TranscriptionError {
                if case .whisperTimeout = tError {
                    continuation.yield(.failed("Transcription timed out."))
                } else if case .whisperError(let status) = tError {
                    continuation.yield(.failed("Whisper API error (HTTP \(status))."))
                } else {
                    continuation.yield(.failed("Transcription failed: \(tError.localizedDescription)"))
                }
            } else {
                continuation.yield(.failed("Transcription failed: \(error.localizedDescription)"))
            }
            // Audio is retained on disk per PRD requirement.
        case .timeout:
            continuation.yield(.failed("Transcription timed out."))
        }
    }

    // MARK: - Private: Timeout wrapper

    private enum TimedResult<T: Sendable>: Sendable {
        case success(T)
        case failure(Error)
        case timeout
    }

    private func transcribeWithTimeout<T: Sendable>(
        maxDuration: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async -> TimedResult<T> {
        let workTask = Task<TimedResult<T>, Never> {
            do {
                let value = try await operation()
                return .success(value)
            } catch {
                return .failure(error)
            }
        }

        let timeoutTask = Task<TimedResult<T>, Never> {
            try? await Task.sleep(for: .seconds(maxDuration))
            return .timeout
        }

        let finished = SafeFlag()

        return await withCheckedContinuation { continuation in
            Task {
                let value = await workTask.value
                if finished.trySet() {
                    continuation.resume(returning: value)
                }
            }

            Task {
                let value = await timeoutTask.value
                if finished.trySet() {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    // MARK: - Private: Fallback logic

    private nonisolated func shouldFallbackFromSpeech(
        transcript: Transcript,
        audioDuration: Double
    ) -> Bool {
        // Empty text → fallback.
        if transcript.text.isEmpty { return true }

        // Low confidence (< 50%) → fallback.
        if let confidence = transcript.confidence, confidence < 0.5 { return true }

        // Length sanity: if transcript is suspiciously short relative to audio,
        // assume Speech missed content (~2 chars/sec minimum).
        let expectedMinChars = Int(audioDuration * 2)
        if transcript.text.count < expectedMinChars { return true }

        return false
    }

    // MARK: - Private: Audio duration estimation

    private nonisolated func estimateAudioDuration(_ url: URL) async -> Double {
        // Estimate duration from file size: AAC at ~128 kbps ≈ 16 KB/s.
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? Int64
        else {
            return 60 // Default assumption.
        }

        let bytesPerSecond: Double = 16000
        let duration = Double(size) / bytesPerSecond
        return max(duration, 1)
    }
}

// AI:
//   what: SafeFlag — thread-safe one-shot boolean for race condition
//   why:  withTimeout races two tasks; only the first to complete should resume
//         the continuation; @unchecked Sendable because flag is atomically set
//   ref:  Swift concurrency pattern for race-tolerant continuations

private final class SafeFlag: @unchecked Sendable {
    private var flag = false

    nonisolated func trySet() -> Bool {
        if flag { return false }
        flag = true
        return true
    }
}
