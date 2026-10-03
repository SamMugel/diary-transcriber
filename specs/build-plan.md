# Build Plan

> Status: **Draft — pending reviewer sign-off**

Three phases, each producing a usable (if incomplete) app.

## Phase 1 — Foundation (MVP: record + transcribe)

**Goal:** User can record a voice entry, see a live transcript, and find the
audio + transcript on disk after quitting.

**Tasks:**
1. SwiftPM package layout + Xcode project (Swift 6 strict concurrency).
2. `Models/`: `DiaryEntry`, `Transcript`.
3. `Storage/DiaryStore`: writes entries to
   `~/Documents/Diary/{YYYY-MM-DD}-{HHMMss}.{m4a,md}` and updates
   `manifest.json`.
4. `Recording/AudioRecorder`: AVFoundation audio-only → `.m4a`.
5. `Transcription/SpeechTranscriber`: streaming `SFSpeechRecognizer`.
6. `RecordingView`: Start/Stop button + live transcript preview.
7. `ContentView` shell with a "New Entry" button.

**Exit criteria:** Record → live transcript → file on disk. No Whisper fallback
yet; if Speech fails, audio is stashed for retry.

## Phase 2 — Complete experience

**Goal:** A daily-habit-ready app: timeline, playback, Whisper fallback, settings.

**Tasks:**
1. `Transcription/WhisperClient` + `TranscriptionService` (fallback per
   `transcription.md`).
2. `Playback/AudioPlayer`.
3. `ContentView` timeline, `EntryDetailView`.
4. `SettingsView`: API key (Keychain), output folder, mic picker.
5. `Storage/FileSystemWatcher` for live timeline sync.

**Exit criteria:** User can record, close, re-open, see it in the timeline with
playback. Whisper fallback kicks in when on-device Speech fails.

## Phase 3 — Shareable release

**Goal:** Code-signed `.app` in a `.dmg` that a non-technical friend can install.

**Exit criteria:**
1. App icon (1024×1024 + full `.icns` set).
2. Polished `Info.plist` with proper bundle ID, version, macOS 14+ minimum,
   `NSMicrophoneUsageDescription`.
3. Code signing (adhoc + Developer ID).
4. `.dmg` via `create-dmg` or `productbuild`.
5. Tests: `DiaryStoreTests`, `SpeechTranscriberTests`.
6. README rewritten as user guide.

## Phase 4 — Future (out of scope for v1)

- Cloud sync (iCloud Drive, Dropbox, S3).
- Backup / export (`.zip`, `.epub`, PDF).
- Searchable transcript index (SQLite FTS5).
- LLM-assisted reflection, themes, weekly recap.
