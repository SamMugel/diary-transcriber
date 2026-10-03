# Build Plan

> Status: **Draft — pending reviewer sign-off**

Three phases. Each phase produces a usable (if incomplete) app — no phase
unblocks only on "everything done".

## Phase 1 — Foundation (MVP: "record + transcribe")

**Goal:** User can record a voice entry, see a live transcript, and find the
audio + transcript on disk after quitting.

**Tasks:**
1. Create SwiftPM package layout + Xcode project (Swift 6 strict concurrency).
2. Implement `Models/`: `DiaryEntry`, `Transcript`.
3. Implement `Storage/DiaryStore`: writes entries to
   `~/Documents/Diary/{YYYY-MM-DD}-{HHMMss}.{m4a,md}` and updates
   `manifest.json`.
4. Implement `Recording/AudioRecorder`: AVFoundation audio-only → `.m4a`.
5. Implement `Transcription/SpeechTranscriber`: streaming `SFSpeechRecognizer`.
6. Minimal `RecordingView`: Start/Stop button + live transcript preview.
7. `ContentView` shell with a "New Entry" button that opens `RecordingView`.

**Exit criteria:**
- Roundtrip works: record → live transcript → file on disk.
- No Whisper fallback yet; if Speech fails, user sees an error and the audio is
  stashed for later retry.

## Phase 2 — Complete experience

**Goal:** A daily-habit-ready app: timeline view, playback, Whisper fallback,
settings.

**Tasks:**
1. Implement `Transcription/WhisperClient` + `TranscriptionService` (fallback
   trigger per `subsystems/transcription.md`).
2. Implement `Playback/AudioPlayer`.
3. Build out `ContentView` timeline, `EntryRowView`, `EntryDetailView`.
4. `SettingsView`: API key (Keychain), output folder, microphone picker.
5. `Storage/FileSystemWatcher` to keep timeline live-synced.

**Exit criteria:**
- A user can record today's entry, close the app, re-open, and see it in the
  timeline with playback.
- Whisper fallback kicks in when on-device Speech fails on a test recording.

## Phase 3 — Shareable release

**Goal:** A code-signed `.app` in a `.dmg` that a non-technical friend can
install.

**Exit criteria:**
1. App icon (1024×1024 + full `.icns` set).
2. Polished `Info.plist` with proper bundle identifiers, version, macOS 14+
   minimum, and the `NSMicrophoneUsageDescription` string.
3. Code signing (adhoc + Developer ID for distribution).
4. `.dmg` via `create-dmg` (or `productbuild`).
5. Tests: `DiaryStoreTests`, `SpeechTranscriberTests` (mocked API).
6. README rewritten as the user guide for the app (not the CLI recorder).

## Phase 4 — Future (out of scope for v1)

- Cloud sync (iCloud Drive, Dropbox, S3).
- Backup / export (`Diary` folder → `.zip`, `.epub`, PDF).
- Searchable transcript index (SQLite FTS5).
- Shared family/user multi-account.
- LLM-assisted reflection, themes, weekly recap.
