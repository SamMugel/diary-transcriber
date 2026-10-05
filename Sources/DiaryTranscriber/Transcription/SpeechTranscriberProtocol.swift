import Foundation

// AI:
//   what: SpeechTranscriberProtocol — abstraction over the concrete SpeechTranscriber actor
//   why:  PRD #36 — TranscriptionServiceTests must drive TranscriptionService with a controllable
//         Speech engine that returns a deterministic Transcript (or throws) WITHOUT instantiating a
//         real SFSpeechRecognizer. On headless CI, SFSpeechRecognizer is nil, so the engine
//         surfaces speechUnavailable and TranscriptionService's Speech branch is exercised only via
//         that single failure mode — leaving the success / empty-result / explicit-error fallback
//         trigger paths untested. Widening the injected collaborator from `SpeechTranscriber` to a
//         protocol lets tests inject an actor that yields or throws on demand, mirroring the exact
//         seam proven by AudioRecorderProtocol (PRD #35). The protocol mirrors the public API of
//         SpeechTranscriber (transcribe / liveStream) verbatim so the concrete actor conforms
//         without body changes; production callers continue to construct `SpeechTranscriber()` and
//         tests inject a stub conforming to this same shape. Both methods are `async` so
//         protocol-typed callers cross actor isolation uniformly — the concrete actor's preexisting
//         method bodies already let external callers `await` them via actor-isolation hoisting;
//         declaring the protocol methods `async` makes that await explicit and stub-authored.
//   ref:  PRD 36-transcription-service-tests, specs/transcription.md SpeechTranscriber API

public protocol SpeechTranscriberProtocol: Sendable {
    /// Transcribes the audio file at `audioURL` using on-device Speech.
    /// Throws `TranscriptionError.speechUnavailable` when no recognizer is present,
    /// or `TranscriptionError.speechError` on a recognition failure / empty result.
    func transcribe(at audioURL: URL) async throws -> Transcript

    /// Streams incremental transcription results while live audio is being captured.
    /// On headless CI where no recognizer is available, the stream finishes immediately
    /// and yields zero values.
    func liveStream() async -> AsyncStream<String>
}
