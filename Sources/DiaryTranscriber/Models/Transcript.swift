import Foundation

// AI:
//   what: Transcript value type representing a transcription result
//   why:  Carries the text, optional confidence score, source engine, and finality flag
//   ref:  specs/transcription.md, D-0004

public struct Transcript: Hashable, Codable, Sendable {
    public var text: String
    public var confidence: Double?
    public var source: TranscriptSource
    public var isFinal: Bool

    public init(
        text: String,
        confidence: Double? = nil,
        source: TranscriptSource = .none,
        isFinal: Bool = false
    ) {
        self.text = text
        self.confidence = confidence
        self.source = source
        self.isFinal = isFinal
    }

    private enum CodingKeys: String, CodingKey {
        case text, confidence, source, isFinal
    }
}
