import Foundation

// AI:
//   what: DiaryStore actor — persistent storage for diary entries (audio + transcript + metadata)
//   why:  D-0005 storage layout: single manifest.json index + per-entry .m4a/.md/.json files;
//         actor isolation prevents concurrent manifest corruption per specs/storage.md
//   ref:  specs/storage.md DiaryStore API, D-0005, D-0006

public actor DiaryStore {

    private let folder: URL
    private let manifestURL: URL

    private let fileManager = FileManager.default

    // MARK: - Lifecycle

    public init(folder: URL) {
        self.folder = folder
        self.manifestURL = folder.appending(path: "manifest.json")
    }

    // MARK: - Public API

    public func entries() async throws -> [DiaryEntry] {
        let manifest = try await loadManifest()
        return manifest.entries.sorted { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }
    }

    public func append(entry: DiaryEntry) async throws {
        try await ensureFolder()

        // Write per-entry files atomically (temp + rename).
        try await writeTranscriptFile(entry, text: "")
        try await writePerEntryMetadata(entry)

        // Update manifest atomically.
        var manifest = try await loadManifest()
        manifest.entries.append(entry)
        manifest.entries.sort { lhs, rhs in lhs.startedAt > rhs.startedAt }
        try await saveManifest(manifest)
    }

    public func update(entry: DiaryEntry) async throws {
        try await ensureFolder()

        var manifest = try await loadManifest()
        guard let index = manifest.entries.firstIndex(where: { $0.id == entry.id }) else {
            throw StoreError.entryNotFound(id: entry.id)
        }

        manifest.entries[index] = entry
        try await saveManifest(manifest)
        try await writePerEntryMetadata(entry)
    }

    /// Writes the transcript text into the entry's `.md` file and updates the
    /// manifest entry's `source` and `updatedAt` in place.
    //
    // AI:
    //   what: DiaryStore.setTranscript — atomic write of transcript text + manifest-side metadata update
    //   why:  PRD #18 — the post-recording pipeline must persist the final transcription onto disk
    //         (closing ISSUE-015's gap where transcripts never made it to .md). The write follows the
    //         same atomic pattern as `append` and `saveManifest`: `Data.write(to:, options: .atomic)`
    //         performs temp-write + osrename, so a crash mid-write leaves a consistent prior state
    //         (per acceptance criterion #4). The manifest is then mutation-updated in place with the
    //         new `source` and a fresh `updatedAt`, mirroring `update(entry:)`.
    //   ref:  PRD 18-transcription-post-recording-pipeline, ISSUE-015
    public func setTranscript(for id: UUID, source: TranscriptSource, text: String) async throws {
        try await ensureFolder()

        var manifest = try await loadManifest()
        guard let index = manifest.entries.firstIndex(where: { $0.id == id }) else {
            throw StoreError.entryNotFound(id: id)
        }

        // Atomic write of the transcript text into the entry's .md file.
        var entry = manifest.entries[index]
        let transcriptURL = folder.appending(path: entry.transcriptPath)
        guard let data = text.data(using: .utf8) else {
            throw StoreError.encodingFailed
        }
        try data.write(to: transcriptURL, options: .atomic)

        // Update the manifest entry's source and updatedAt in place.
        entry.source = source
        entry.updatedAt = Date()
        manifest.entries[index] = entry

        try await saveManifest(manifest)
        try await writePerEntryMetadata(entry)
    }

    public func delete(id: UUID) async throws {
        var manifest = try await loadManifest()
        guard let index = manifest.entries.firstIndex(where: { $0.id == id }) else {
            throw StoreError.entryNotFound(id: id)
        }

        let entry = manifest.entries[index]

        try await removeFileIfExists(folder.appending(path: entry.audioPath))
        try await removeFileIfExists(folder.appending(path: "\(filenameBase(for: entry)).json"))
        try await removeFileIfExists(folder.appending(path: entry.transcriptPath))

        manifest.entries.remove(at: index)
        try await saveManifest(manifest)
    }

    public func url(for entry: DiaryEntry) -> URL {
        folder.appending(path: entry.audioPath).standardizedFileURL
    }

    /// Returns the absolute URL of the store's output folder.
    public func folderURL() -> URL {
        folder
    }

    public func data(for entry: DiaryEntry) async throws -> EntryData {
        let audioURL = url(for: entry)
        let transcriptURL = folder.appending(path: entry.transcriptPath)
        let transcriptText = try await loadText(transcriptURL)
        return EntryData(
            audioURL: audioURL,
            transcriptText: transcriptText,
            metadata: entry
        )
    }

    // MARK: - Private: Manifest I/O

    private func loadManifest() async throws -> Manifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return Manifest(schemaVersion: 1, folder: folder.path, entries: [])
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: data)
    }

    private func saveManifest(_ manifest: Manifest) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]

        let data = try encoder.encode(manifest)

        // Atomic write: write to temp file, then rename.
        let tempURL = folder.appending(path: ".manifest.tmp")
        try data.write(to: tempURL, options: .atomic)

        // Overwrite existing manifest via rename.
        _ = try? fileManager.removeItem(at: manifestURL)
        try fileManager.moveItem(at: tempURL, to: manifestURL)
    }

    // MARK: - Private: Per-entry files

    private func writeTranscriptFile(_ entry: DiaryEntry, text: String) async throws {
        let transcriptURL = folder.appending(path: entry.transcriptPath)
        guard let data = text.data(using: .utf8) else {
            throw StoreError.encodingFailed
        }
        try data.write(to: transcriptURL, options: .atomic)
    }

    private func writePerEntryMetadata(_ entry: DiaryEntry) async throws {
        let jsonURL = folder.appending(path: "\(filenameBase(for: entry)).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(entry)
        try data.write(to: jsonURL, options: .atomic)
    }

    private func loadText(_ url: URL) async throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Private: Helpers

    private func ensureFolder() async throws {
        try fileManager.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
    }

    private func removeFileIfExists(_ url: URL) async throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private nonisolated func filenameBase(for entry: DiaryEntry) -> String {
        let filename = entry.audioPath
        if let dotIndex = filename.lastIndex(of: ".") {
            return String(filename[..<dotIndex])
        }
        return filename
    }
}

// AI:
//   what: StoreError — typed errors for DiaryStore failures
//   why:  Swift error handling rule: descriptive typed errors conforming to LocalizedError
//   ref:  .opencode/rules/15-swift-error-handling.mdc

public enum StoreError: LocalizedError {
    case entryNotFound(id: UUID)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .entryNotFound(let id):
            "No diary entry found with id \(id)."
        case .encodingFailed:
            "Failed to encode data to UTF-8."
        }
    }
}
