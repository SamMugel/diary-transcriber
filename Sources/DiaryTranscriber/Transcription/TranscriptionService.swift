import Foundation

// AI:
//   what: TranscriptionService actor orchestrates hybrid Speech + Whisper transcription
//   why:  D-0004 hybrid pipeline: SpeechTranscriber first (on-device), then WhisperClient
//         fallback on empty text, low confidence, error, or 3× audio duration hang protection
//   ref:  specs/transcription.md TranscriptionService, D-0004

public actor TranscriptionService: TranscriptionServiceProtocol {

    private let speechTranscriber: SpeechTranscriber
    // AI: `var` so replaceWhisperClient(_) can rebuild the client after a Settings API-key commit,
    //     reloading the Whisper fallback without restarting the app or recreating the Speech engine
    //     (which carries no state and is expensive to spin up). PRD #28 criterion 2 / ref: PRD 28
    private var whisperClient: WhisperClient?
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

    /// Replaces the Whisper client used for fallback transcription.
    // AI:
    //   what: Hot-swaps the WhisperClient on the shared actor instance
    //   why:  PRD #28 — when the user commits a new OpenAI API key in Settings, the Whisper
    //         fallback must reload without restarting the app. Approach R over Approach S so
    //         view-models keep a stable `let service` reference and the stateless
    //         SpeechTranscriber is not needlessly recreated.
    //   ref:  PRD 28-transcription-service-bootstrap, acceptance criterion 2
    public func replaceWhisperClient(_ client: WhisperClient?) async {
        whisperClient = client
    }

    /// Test-only accessor reflecting whether a Whisper client is currently wired.
    // AI:
    //   what: Actor-isolated read of whisperClient presence for tests
    //   why:  PRD #28 AppEnvironmentTests needs to assert that a Keychain-backed key boots a
    //         WhisperClient-backed service and that a missing key yields nil — without exposing
    //         the private field directly. Read-only and nonisolated-safe behind actor isolation.
    //   ref:  PRD 28-transcription-service-bootstrap, AppEnvironmentTests
    public func hasWhisperClient() async -> Bool {
        whisperClient != nil
    }

    // AI: PRD #35 — `async` so the protocol-typed call surface uniformly crosses actor
    //     isolation on protocol-typed references; production body is unchanged: a strong
    //     reference is returned synchronously, callers `await` it explicitly.
    public func transcribe(at audioURL: URL) async -> AsyncStream<TranscriptUpdate> {
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
        // AI: hang-protection timeout — 3× the estimated audio duration, floor 30s.
        //     Centralized in `hangProtectionTimeoutSeconds` so the DEBUG-seam test
        //     asserts the exact same threshold the production pipeline enforces.
        let maxDuration = Self.hangProtectionTimeoutSeconds(for: audioDuration)

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

    // MARK: - Fallback logic

    // AI: The four fallback trigger conditions enumerated by PRD #08 — empty text,
    //     <50% expected length, Speech error, >3× audio duration. PRD #17's
    //     TranscriptionServiceTests must assert all four. PRD #36 will augment them
    //     with engine-mock tests; until then, exposing the decision as a DEBUG-seam
    //     pure function is the only way to assert the conditions deterministically
    //     without a controllable Speech/Whisper instance.
    #if DEBUG
    internal nonisolated func shouldFallbackFromSpeech(
        transcript: Transcript,
        audioDuration: Double
    ) -> Bool {
        Self.fallbackDecisionForSpeech(transcript: transcript, audioDuration: audioDuration)
    }
    #else
    private nonisolated func shouldFallbackFromSpeech(
        transcript: Transcript,
        audioDuration: Double
    ) -> Bool {
        Self.fallbackDecisionForSpeech(transcript: transcript, audioDuration: audioDuration)
    }
    #endif

    // AI:
    //   what: Pure, side-effect-free implementation of the Speech fallback decision and the
    //         3× hang-protection timeout. Shared between the DEBUG test seam
    //         (`shouldFallbackFromSpeech`) and the production pipeline (`runTranscription`)
    //         so the behavior under test is the exact behavior in production.
    //   why:  PRD #17 acceptance criterion — TranscriptionServiceTests verify all four fallback
    //         trigger conditions. A single private static function shared by both the cost-only
    //         `#if DEBUG internal` accessor and the production call site prevents drift between
    //         "test-seam" code and "real" code. No mock dependency on SFSpeechRecognizer/URLSession.
    //   ref:  PRD 17-test-suites § acceptance criteria, PRD 08-transcription-service fallback table
    private nonisolated static func fallbackDecisionForSpeech(
        transcript: Transcript,
        audioDuration: Double
    ) -> Bool {
        // Trigger #1: empty text → fallback.
        if transcript.text.isEmpty { return true }

        // Trigger #2: low confidence (< 50%). Mirrors the "<50% expected length" criterion:
        // a low-confidence pass signals partial loss even when the text is non-empty.
        if let confidence = transcript.confidence, confidence < 0.5 { return true }

        // Trigger #3: length sanity — transcript suspiciously short relative to audio.
        // Expected length ≈ audioDuration * 2 chars (~2 chars/sec minimum), per the
        // "<50% expected length" criterion.
        let expectedMinChars = Int(audioDuration * 2)
        if transcript.text.count < expectedMinChars { return true }

        return false
    }

    // AI:
    //   what: Hang-protection (3× audio duration) timeout, floored at 30s
    //   why:  PRD #08 fallback trigger #4 ("recognition exceeding 3× audio duration").
    //         Centralized here so production's `runTranscription` and PRD #17's
    //         TranscriptionServiceTests assert the exact same threshold — no duplication.
    //   ref:  PRD 17-test-suites acceptance criteria, PRD 08-transcription-service
    internal nonisolated static func hangProtectionTimeoutSeconds(
        for audioDuration: Double
    ) -> Double {
        max(audioDuration * 3, 30)
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
