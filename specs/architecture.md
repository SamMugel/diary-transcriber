# Architecture

> Status: **Draft — pending reviewer sign-off**

## Repository layout (target state)

```
diary-transcriber/
├── App/
│   └── DiaryTranscriberApp.swift          # @main App entry; window scene
├── Sources/DiaryTranscriber/
│   ├── Models/
│   │   ├── DiaryEntry.swift               # id, date, duration, audioPath,
│   │   │                                    transcriptPath, source
│   │   └── Transcript.swift               # liveText, finalText, confidence
│   ├── Storage/
│   │   ├── DiaryStore.swift               # folder + manifest.json read/write
│   │   └── FileSystemWatcher.swift        # keeps timeline live-synced
│   ├── Recording/
│   │   ├── AudioRecorder.swift            # AVFoundation audio-only → .m4a
│   │   └── PermissionManager.swift        # microphone auth (async/await)
│   ├── Transcription/
│   │   ├── SpeechTranscriber.swift        # SFSpeechRecognizer, streaming
│   │   ├── WhisperClient.swift            # URLSession client
│   │   └── TranscriptionService.swift     # orchestrates primary + fallback
│   ├── Playback/
│   │   └── AudioPlayer.swift              # AVAudioPlayer wrapper (Observable)
│   └── Views/
│       ├── ContentView.swift              # timeline + New entry button
│       ├── EntryRowView.swift             # timeline row, expands on select
│       ├── EntryDetailView.swift          # full transcript + playback
│       ├── RecordingView.swift            # live transcript + Stop button
│       └── SettingsView.swift             # API key, folder, microphone picker
├── Resources/
│   ├── Info.plist                         # bundle metadata + mic usage
│   └── Assets.xcassets/                   # app icon
├── Tests/
│   ├── DiaryStoreTests.swift
│   └── SpeechTranscriberTests.swift
├── specs/                                 # ← this folder
├── Package.swift                          # SwiftPM manifest (preferred)
├── README.md
└── build.sh                               # rewritten for app-bundle build
```

## Layering & dependency direction

```
Views ───────► Storage  ◄─────── Models
  │              ▲
  ▼              │
Recording ──► TranscriptionService
                  │
                  ├─► SpeechTranscriber
                  └─► WhisperClient
```

- `Models` has *no* dependencies — pure data structs only.
- `Storage` depends on `Models`. Knows nothing about UI or AVFoundation.
- `Recording` depends on `Models` (for `Transcript` accumulators). Pure AVFoundation.
- `Transcription` depends on `Models`. Speech + Whisper clients may not depend
  on each other; `TranscriptionService` orchestrates both.
- `Playback` depends on `Models`. `AVAudioPlayer` wrapper, observable.
- `Views` depends on everything above — this is the only SwiftUI-aware layer.

**Forbidden deps:**
- No layer may `import SwiftUI` except `Views`.
- `Storage`, `Recording`, `Transcription` must be `public` testable with plain
  Swift XCTest — no assumption of a view-layer to do their work.

## Concurrency model

- Swift 6 strict concurrency throughout (`-strict-concurrency=complete`).
- Long-running work (`AudioRecorder`, `SpeechTranscriber`, `WhisperClient`)
  runs on a dedicated `actor` or `Task` detached from the main thread.
- UI binding via `@MainActor` view-models; only immutable snapshots cross
  boundaries.
- Use `AsyncStream` to publish transcript deltas from the transcription layer
  up to the view layer.

## Build system

- **Preferred:** SwiftPM (`Package.swift`) with an Xcode project wrapping it.
  Xcode invokes `swift build` for tests and `xcodebuild` for bundle + signing.
- `build.sh` is a thin wrapper that invokes the SwiftPM/Xcode target and copies
  the resulting `.app` to the repo root for ad-hoc testing.

## Reuse plan for current code

Only one piece of the existing code has known reuse value:

| Existing | Reuse | Notes |
|---|---|---|
| `Info.plist` `NSMicrophoneUsageDescription` | ✅ Pattern | Carries forward into the app bundle's `Info.plist`. Camera description is dropped (audio-only — see `D-0002`). |
| `requestPermission(...)` | ⚠️ Concept | Rewritten against async/await; the synchronous semaphore pattern does not fit SwiftUI. |
| `selectDevice(...)` | ⚠️ Pattern | Simplified — only audio devices matter now. |
| `AVCaptureMovieFileOutput` recording | ❌ Removed | Replaced by audio-only `AVAudioFileOutput` (or `AVAudioEngine` + `AVAudioFile`). |
| `SIGINT`/`SIGTERM` handlers | ❌ Removed | UI lifecycle replaces signal handling. |
| `RunLoop.main.run()` loop | ❌ Removed | `@main App` + SwiftUI scene replaces it. |
| `webcam-record.swift` (whole file) | ❌ Removed | Lives in git history for reference until Phase 4 prunes it. |

## Known risks

- **`SFSpeechRecognizer` limits:** macOS on-device recognition is constrained;
  long entries (3+ min) may degrade. **Mitigation:** Whisper fallback has a
  fixed timeout and confidence threshold (see `subsystems/transcription.md`).
- **Whisper API key management:** The key must be stored in the OS **Keychain**,
  never in `manifest.json` or `~/Documents/Diary/` plain text. Add a Keychain
  wrapper in `Storage/`.
- **Audio file finalization race:** `AVAudioFileOutput` finalizes
  asynchronously. Transcription and manifest writes must wait for the
  `didFinishRecordingTo` callback *before* starting. Define a hard handoff
  contract in `subsystems/recording.md`.
- **App backgrounding during recording:** If the user backgrounds the app,
  AVFoundation may kill the session. **Decision needed:** pause recording and
  surface a resume banner, or warn before backgrounding. → See
  [D-0012] (TO BE ADDED).
- **First-launch permission UX:** macOS may require a restart of the app after
  granting microphone access for AVFoundation. Document this in a one-time
  onboarding screen.
