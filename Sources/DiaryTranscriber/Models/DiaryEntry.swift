import Foundation

// AI:
//   what: DiaryEntry value type — the core model for one diary recording
//   why:  D-0005 storage layout: each entry is audio + transcript + metadata indexed
//         by manifest.json; paths are relative to the output folder for portability
//   ref:  specs/storage.md, D-0005, D-0006

public struct DiaryEntry: Hashable, Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var durationSeconds: Double
    public var audioPath: String
    public var transcriptPath: String
    public var source: TranscriptSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        durationSeconds: Double,
        audioPath: String,
        transcriptPath: String,
        source: TranscriptSource = .none,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.audioPath = audioPath
        self.transcriptPath = transcriptPath
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, durationSeconds, audioPath, transcriptPath, source, createdAt, updatedAt
    }
}
