# Architecture

> Status: **Draft — pending reviewer sign-off**

## Repository layout (target)

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
│       ├── EntryDetailView.swift          # full transcript + playback
│       ├── RecordingView.swift            # live transcript + Stop button
│       └── SettingsView.swift             # API key, folder, mic picker
├── Resources/
│   ├── Info.plist                         # bundle metadata + mic usage
│   └── Assets.xcassets/                   # app icon
├── Tests/
│   ├── DiaryStoreTests.swift
│   └── SpeechTranscriberTests.swift
├── specs/                                 # ← this folder
├── Package.swift                          # SwiftPM manifest
└── README.md
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

- `Models` — no dependencies; pure data structs.
- `Storage` — depends on `Models` only. No UI or AVFoundation imports.
- `Recording` — depends on `Models`. Pure AVFoundation.
- `Transcription` — depends on `Models`. Speech and Whisper clients do not
  depend on each other; `TranscriptionService` orchestrates both.
- `Playback` — depends on `Models`.
- `Views` — the only SwiftUI-aware layer; depends on everything above.

**Forbidden deps:** No layer imports `SwiftUI` except `Views`. `Storage`,
`Recording`, and `Transcription` must be testable with plain XCTest.

## Concurrency model

- Swift 6 strict concurrency (`-strict-concurrency=complete`).
- Long-running work (`AudioRecorder`, `SpeechTranscriber`, `WhisperClient`)
  runs on a dedicated `actor` detached from the main thread.
- UI binding via `@MainActor` view-models; only immutable snapshots cross
  boundaries.
- `AsyncStream` publishes transcript deltas from the transcription layer to
  the view layer.

## Build system

SwiftPM (`Package.swift`) with an Xcode project wrapping it. Xcode invokes
`swift build` for tests and `xcodebuild` for bundle + signing.

## Known risks

- **`SFSpeechRecognizer` limits:** macOS on-device recognition may degrade on
  long entries (3+ min). **Mitigation:** Whisper fallback has a fixed timeout
  and confidence threshold (see `transcription.md`).
- **Whisper API key management:** Must be stored in OS Keychain, never in
  `manifest.json` or plain text.
- **Audio file finalization race:** `AVAudioFileOutput` finalizes
  asynchronously. Transcription and manifest writes must wait for the
  `didFinishRecordingTo` callback before starting (see `recording.md`).
- **App backgrounding during recording:** AVFoundation may kill the session.
  Decision needed: pause + resume banner, or warn before backgrounding.
- **First-launch permission UX:** macOS may require an app restart after
  granting microphone access. Document in a one-time onboarding screen.
