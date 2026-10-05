import Foundation

// AI:
//   what: WhisperClientProtocol — abstraction over the concrete WhisperClient actor
//   why:  PRD #36 — TranscriptionServiceTests must drive TranscriptionService's Whisper fallback
//         path with a controllable client that returns a deterministic Transcript (or throws)
//         WITHOUT issuing a real URLSession POST to api.openai.com. Without a protocol,
//         TranscriptionService holds a concrete `WhisperClient?` and CI has no seam to inject a
//         fake; the fallback's success / explicit-error / timeout branches are exercised only via
//         the bogus-file + fake-key path, which is non-deterministic (URLSession may surface a TLS
//         or transport error before the test asserts). Widening the injected collaborator to a
//         protocol lets tests inject an actor that yields or throws on demand, mirroring the exact
//         seam proven by AudioRecorderProtocol (PRD #35). The protocol mirrors the public API of
//         WhisperClient (transcribe) verbatim so the concrete actor conforms without body changes;
//         production callers continue to construct `WhisperClient(apiKey:)` and tests inject a stub
//         conforming to this same shape. The method is `async` so protocol-typed callers cross
//         actor isolation uniformly — the concrete actor's preexisting method body already lets
//         external callers `await` it via actor-isolation hoisting; declaring the protocol method
//         `async` makes that await explicit and stub-authored.
//   ref:  PRD 36-transcription-service-tests, specs/transcription.md WhisperClient API

public protocol WhisperClientProtocol: Sendable {
    /// Transcribes the audio file at `audioURL` via the OpenAI Whisper API.
    /// Throws `TranscriptionError.whisperError(status:)` on a non-2xx response,
    /// `TranscriptionError.networkUnavailable` on a transport/TLS failure, and
    /// `TranscriptionError.whisperTimeout` when the request exceeds the client's
    /// outer timeout budget.
    func transcribe(at audioURL: URL) async throws -> Transcript
}
