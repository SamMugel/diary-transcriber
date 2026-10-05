import Foundation

// AI:
//   what: TranscriptionServiceProtocol — abstraction over the concrete TranscriptionService actor
//   why:  PRD #35 — end-to-end pipeline tests must inject a stub TranscriptionService that yields
//         a deterministic TranscriptUpdate.final without touching SFSpeechRecognizer or the
//         Whisper API. Without a protocol, RecordingViewModel and EntryDetailViewModel hold a
//         concrete `TranscriptionService` actor and CI has no seam to inject a fake. The protocol
//         mirrors the public API of TranscriptionService (transcribe / replaceWhisperClient /
//         hasWhisperClient) so the concrete actor conforms without body changes; production callers
//         continue to construct `TranscriptionService(...)` and tests inject a stub conforming to
//         this same shape. All three methods are `async` so protocol-typed callers cross actor
//         isolation uniformly — the concrete actor's preexisting method bodies already let
//         external callers `await` them via actor-isolation hoisting; declaring the protocol
//         methods `async` makes that await explicit and stub-authored.
//   ref:  PRD 35-end-to-end-record-pipeline-tests, specs/transcription.md TranscriptionService

public protocol TranscriptionServiceProtocol: Sendable {
    /// Streams incremental `TranscriptUpdate`s for the audio at `audioURL`.
    /// The stream completes (`.finish()`) on terminal state: `.final`,
    /// `.failed`, or no-engines-available.
    func transcribe(at audioURL: URL) async -> AsyncStream<TranscriptUpdate>

    /// Hot-swaps the Whisper fallback client in-place. Used by AppEnvironment
    /// when the user commits a new API key in Settings.
    func replaceWhisperClient(_ client: WhisperClient?) async

    /// Test-only accessor reflecting whether a Whisper client is wired.
    func hasWhisperClient() async -> Bool
}
