# Subsystem: Storage

> Status: **Draft — pending reviewer sign-off**

## Scope

Persist diary entries (audio + transcript + metadata) to local disk and expose
them to the UI via a `DiaryStore`. Plain folder + JSON index — no database.

Related: [`decisions.md` D-0005 · D-0006](../decisions.md),
[`subsystems/recording.md`](recording.md),
[`subsystems/transcription.md`](transcription.md).

## Folder layout

```
~/Documents/Diary/
├── manifest.json
├── 2026-10-03-0905.m4a                   # audio
├── 2026-10-03-0905.md                    # transcript (markdown)
�-── 2026-10-03-0905.json                  # per-entry metadata snapshot
├── 2026-10-04-0812.m4a
├── 2026-10-04-0812.md
└── 2026-10-04-0812.json
```

- Filenames are derived from the **recording start** timestamp in the local
  time zone: `YYYY-MM-DD-HHMMss`.
- `manifest.json` is the single source of truth for the timeline view; the
  per-entry `.json` is a lazy-loaded snapshot used when the manifest is stale
  or during recovery.

## Entry model

```swift
public struct DiaryEntry: Hashable, Codable, Sendable {
    public var id: UUID                     // stable, set at creation
    public var startedAt: Date              // recording start (UTC)
    public var durationSeconds: Double      // measured by AVFoundation
    public var audioPath: String            // relative to ~/Documents/Diary
    public var transcriptPath: String       // relative; .md
    public var source: TranscriptSource     // speech, whisper, none
    public var createdAt: Date              // entry creation time
    public var updatedAt: Date              // last edit (default = createdAt)
}
```

`relative` paths in `audioPath`/`transcriptPath` are relative to the configured
output folder (`~/Documents/Diary` by default; user-relocatable). The store
resolves them to absolute paths on demand via `func url(for entry:) -> URL`.

## `manifest.json` schema

```json
{
  "schemaVersion": 1,
  "folder": "~/Documents/Diary",
  "entries": [
    {
      "id": "8f6c1b2a-3f4d-4e9c-b8a7-2a1c3f4e5d60",
      "startedAt": "2026-10-03T09:05:00Z",
      "durationSeconds": 124.7,
      "audioPath": "2026-10-03-0905.m4a",
      "transcriptPath": "2026-10-03-0905.md",
      "source": "speech",
      "createdAt": "2026-10-03T09:07:15Z",
      "updatedAt": "2026-10-03T09:07:15Z"
    }
  ]
}
```

- Top-level `"folder"` is persisted for self-consistency; the store uses it for
  cross-family path resolution.
- `"schemaVersion": 1` allows forward migrations if the shape changes later.

## `DiaryStore` API

```swift
public actor DiaryStore {
    public init(folder: URL)

    public func entries() async throws -> [DiaryEntry]
    public func append(entry: DiaryEntry) async throws
    public func update(entry: DiaryEntry) async throws
    public func delete(id: UUID) async throws

    public func url(for entry: DiaryEntry) -> URL
    public func data(for entry: DiaryEntry) async throws -> EntryData
}
```

- **Append** writes the file (audio + transcript) and updates `manifest.json`
  in a single atomic operation (write-to-temp + `osrename`).
- **Entries** returns the whole list sorted newest-first; expected size for
  personal use is <= a few thousand rows, well within `< 500 ms` budget (see
  `product-vision.md`).

## Handoff: recording → storage → transcription

Strict sequence, enforced by the view-model (Phase 1) or a dedicated
`EntryPipeline` class (Phase 2):

1. **Recorder** writes audio to `targetURL`.
2. `AudioRecorder.didFinishRecordingTo(url:)` fires (the handoff point).
3. `DiaryStore.append(...)` writes the `.md` placeholder (transcript empty),
   updates `manifest.json`, and returns the new `DiaryEntry`.
4. `TranscriptionService.transcribe(at: url)` is called; `EntryPipeline`
   subscribes to the `AsyncStream<TranscriptUpdate>`.
5. As updates land (`partial`), the `.md` and `manifest` can be updated in-place.
   On `final`, the transcript text is finalized.
6. On `failed`, the entry remains on disk with `source = .none` and an empty
   transcript — the user may retry later from the entry detail view.

All transcript writes are *text* writes, not full-file rewrites, where possible;
synchronize on the `DiaryStore` actor so the manifest is never corrupted by a
concurrent view-model update.

## Concurrent writer safety

- Only one writer (`DiaryStore` actor) updates `manifest.json` at a time.
- `manifest.json` is the authoritative file. The per-entry `.json` is written
  after the manifest and may be slightly out of date; it is re-synced on read
  if the mtime is newer than the manifest entry's `updatedAt`.

## Folder relocation

- Setting: `outputFolder` in `SettingsView`. Stored in
  `UserDefaults`/AppStorage.
- On relocation, existing entries are **not moved automatically**; the store
  opens a new empty manifest at the new location. A "merge" feature is Phase 4.

## Removal & garbage collection

- `delete(id:)` removes the `.m4a`, `.md`, `.json`, and the manifest row.
- Orphaned files (in folder but not in manifest) are surfaced as a "Recovery"
  banner in `ContentView`: "3 files found in folder but not in index — Import?"

## Apocryphal stuff (not for v1)

- Encryption at rest (per-entry or whole-volume).
- Multi-folder aggregation.
- Cloud-backed backup / sync.
- Undo / version history of edits.
