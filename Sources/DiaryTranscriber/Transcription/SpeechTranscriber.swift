import Foundation
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
            "No internet connection available for transcription."
        }
    }
}
