import Foundation

// AI:
//   what: TranscriptSource enum identifying which engine produced a transcript
//   why:  D-0004 hybrid transcription uses both on-device Speech and Whisper API;
//         `.none` marks entries that have no transcript yet or failed all engines
//   ref:  specs/transcription.md, D-0004

public enum TranscriptSource: String, Codable, Sendable {
    case speech, whisper, none
}
