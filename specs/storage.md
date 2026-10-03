# Storage

> Status: **Draft — pending reviewer sign-off**

## Scope

Persist diary entries (audio + transcript + metadata) to local disk and expose
them to the UI via `DiaryStore`. Plain folder + JSON index — no database.

Related: D-0005 · D-0006, `recording.md`, `transcription.md`.

## Folder layout

```
~/Documents/Diary/
├── manifest.json
├── 2026-10-03-0905.m4a                   # audio
├── 2026-10-03-0905.md                    # transcript (markdown)
├── 2026-10-03-0905.json                  # per-entry metadata snapshot
├── 2026-10-04-0812.m4a
├── 2026-10-04-0812.md
└── 2026-10-04-0812.json
```

- Filenames derived from recording start timestamp in local time:
  `YYYY-MM-DD-HHMMss`.
- `manifest.json` is the single source of truth for the timeline; per-entry
  `.json` is a lazy-loaded snapshot for recovery.

## Entry model

```swift
public struct DiaryEntry: Hashable, Codable, Sendable {
    public var id: UUID
    public var startedAt: Date              // recording start (UTC)
    public var durationSeconds: Double
    public var audioPath: String            // relative to ~/Documents/Diary
    public var transcriptPath: String       // relative; .md
    public var source: TranscriptSource     // speech, whisper, none
    public var createdAt: Date
    public var updatedAt: Date              // last edit (default = createdAt)
}
```

Paths are relative to the configured output folder; resolved to absolute on
demand via `func url(for entry:) -> URL`.

## manifest.json schema

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

`schemaVersion` allows forward migrations.

## DiaryStore API

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

- **Append** writes files + updates `manifest.json` atomically
  (write-to-temp + `osrename`).
- **Entries** returns the list sorted newest-first.

## Handoff: recording → storage → transcription

Enforced by the view-model (Phase 1) or a dedicated `EntryPipeline` (Phase 2):

1. Recorder writes audio to `targetURL`.
2. `AudioRecorder.didFinishRecordingTo(url:)` fires (handoff point).
3. `DiaryStore.append(...)` writes `.md` placeholder, updates `manifest.json`,
   returns new `DiaryEntry`.
4. `TranscriptionService.transcribe(at: url)` is called; pipeline subscribes to
   `AsyncStream<TranscriptUpdate>`.
5. On `partial`, `.md` and manifest update in-place. On `final`, transcript is
   finalized.
6. On `failed`, entry remains on disk with `source = .none` and empty transcript.

All transcript writes are text writes, not full-file rewrites; synchronized on
the `DiaryStore` actor so the manifest is never corrupted by concurrent updates.

## Concurrent writer safety

- Only one writer (`DiaryStore` actor) updates `manifest.json` at a time.
- Per-entry `.json` may be slightly out of date; re-synced on read if mtime is
  newer than the manifest entry's `updatedAt`.

## Folder relocation

Setting: `outputFolder` in `SettingsView`, stored in `UserDefaults`. Existing
entries are **not moved**; the store opens a new empty manifest. Merge is Phase 4.

## Removal & garbage collection

- `delete(id:)` removes `.m4a`, `.md`, `.json`, and the manifest row.
- Orphaned files surfaced as a "Recovery" banner: "3 files in folder but not in
  index — Import?"

## Out of scope for v1

- Encryption at rest.
- Multi-folder aggregation.
- Cloud backup / sync.
- Undo / version history.
