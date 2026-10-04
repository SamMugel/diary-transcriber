import Foundation

// AI:
//   what: Manifest is the Codable schema for manifest.json
//   why:  D-0005 storage layout: single source of truth for the timeline;
//         schemaVersion allows forward migrations per specs/storage.md
//   ref:  specs/storage.md manifest.json schema, D-0005

public struct Manifest: Codable, Sendable {
    public var schemaVersion: Int
    public var folder: String
    public var entries: [DiaryEntry]

    public init(schemaVersion: Int = 1, folder: String, entries: [DiaryEntry] = []) {
        self.schemaVersion = schemaVersion
        self.folder = folder
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, folder, entries
    }
}
