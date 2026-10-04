import Foundation

// AI:
//   what: TranscriptUpdate enum streaming incremental transcription results
//   why:  TranscriptionService yields partial, final, or failed states to the
//         view-model via AsyncStream; this is the discriminated union for that channel
//   ref:  specs/transcription.md

public enum TranscriptUpdate: Sendable {
    case partial(String)
    case final(Transcript)
    case failed(String)
}
