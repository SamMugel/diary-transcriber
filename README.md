# Diary Transcriber

A local-first macOS desktop app for daily voice journaling. Speak a diary entry,
and the app records the audio, transcribes it, and files it in a timeline you
can browse and replay.

## Status

**Feature-complete (MVP).** PRDs 01–40 are implemented and the build is clean
with all tests passing. Transcription is wired into recording:
`AppEnvironment` constructs the `TranscriptionService` with a `WhisperClient`
backed by an OpenAI API key stored in Keychain; `finishRecording` persists the
resulting transcript via `DiaryStore.setTranscript`. PRDs 41–42 are follow-up
QA fixes for packaging and documentation polish.

## Features

- **Record** an audio-only diary entry from your microphone (`.m4a` / AAC).
- **Transcribe** using Apple's on-device Speech framework, with an OpenAI
  Whisper API fallback for low-quality or failed recognition.
- **Store** entries as plain files under `~/Documents/Diary/`, indexed by a
  shared `manifest.json`.
- **Browse** past entries in a SwiftUI timeline; tap any entry to read the full
  transcript and replay the audio.
- **Edit** transcripts inline; changes save automatically.

## Requirements

- macOS 15.0 or newer (Sequoia).
- Swift 6 (strict concurrency).
- Xcode 16+ / SwiftPM.
- An OpenAI API key (optional, for Whisper fallback transcription).

## Install

### From source (developer)

```bash
git clone https://github.com/sam.mugel/diary-transcriber.git
cd diary-transcriber
swift build
```

### From a release .dmg

1. Download `DiaryTranscriber-1.0.0.dmg` from the [Releases](../../releases) page.
2. Double-click the `.dmg` to mount it.
3. Drag `DiaryTranscriber.app` to your Applications folder.
4. Eject the DMG.

## Run

### Command line (development)

```bash
swift run DiaryTranscriber
```

### From Xcode

1. Open `Package.swift` in Xcode.
2. Select the `DiaryTranscriber` scheme.
3. Build and Run (⌘R).

### From the app bundle

Double-click `DiaryTranscriber.app` in Finder.

## Configure

On first launch:

- **Output folder**: Defaults to `~/Documents/Diary/`. Change in Settings
  (gear button → Output folder → choose folder).
- **Transcription engine**: On-device Speech is enabled by default. For
  Whisper API fallback, enter your OpenAI API key in Settings.
  - API key is stored in your macOS Keychain, never in plaintext.
  - The key is never included in error messages or logs.

## Build & package

### Build (debug)

```bash
swift build
```

### Build (release)

```bash
swift build -c release
```

### Package as .app

```bash
./scripts/package.sh
```

This runs `xcodebuild` with the Release configuration and produces
`DiaryTranscriber.app` in `build/release/`.

### Code signing

#### Adhoc (for internal testing)

```bash
codesign -s - --timestamp -f build/release/DiaryTranscriber.app
```

#### Developer ID (for distribution)

```bash
codesign -s "Developer ID Application: Diary Transcriber" \
  --timestamp --options runtime \
  build/release/DiaryTranscriber.app
```

### Create .dmg

```bash
./scripts/create-dmg.sh
```

This produces `DiaryTranscriber-1.0.0.dmg` in `build/release/`.

## Troubleshooting

### Microphone permission denied

macOS may block microphone access if run from Terminal the first time.
Go to **System Settings → Privacy & Security → Microphone** and verify
that Terminal (or Xcode) is allowed. For the .app bundle, the permission
prompt appears on first launch.

### Speech recognition not available

On-device Speech requires an active macOS system. If running on a headless CI
machine where `SFSpeechRecognizer.isAvailable` returns `false`, the
app will fall back to the Whisper API automatically. Set your OpenAI
API key in Settings to enable Whisper fallback.

### Build fails with "swift-tools-version 6.0"

Ensure you have Swift 6.0 or newer (Xcode 16+):

```bash
swift --version
```

If using Xcode 16 but the command-line `swift` is older, install via
[swift.org](https://swift.org/download/) or use `xcrun swift`.

### Tests hang

Tests that interact with the file system or require a microphone may be slow
on first run. If tests appear to hang, wait up to 30 seconds for the
FileSystemWatcher tests to detect file changes. In CI environments, use:

```bash
swift test --parallel
```

### Whisper API errors (HTTP 401)

This means your API key is missing, empty, or invalid. Go to Settings → enter
a valid OpenAI API key. The key is stored in Keychain and never written to
disk in plaintext.

## Project layout

```
diary-transcriber/
├── App/                     # SwiftUI @main App entry
├── Sources/DiaryTranscriber/
│   ├── Models/              # DiaryEntry, Transcript, TranscriptSource, etc.
│   ├── Storage/             # DiaryStore, FileSystemWatcher, Manifest
│   ├── Recording/           # AudioRecorder, PermissionManager
│   ├── Transcription/       # SpeechTranscriber, WhisperClient, TranscriptionService
│   ├── Playback/            # AudioPlayer
│   └── Views/               # ContentView, EntryDetailView, RecordingView, SettingsView
├── Resources/               # Info.plist, AppIcon
├── Tests/                   # XCTest suites
├── PRD/                     # Product Requirements Documents
├── specs/                   # Product vision, architecture, decisions
├── scripts/                 # Build & packaging scripts
└── README.md                # This file
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Decision log

All product and technical decisions are recorded in
[`specs/decisions.md`](specs/decisions.md). Key decisions:

- D-0001 Shareable macOS desktop voice diary, not a CLI.
- D-0002 Audio-only recording (video removed).
- D-0003 `.m4a` (AAC) format.
- D-0004 Hybrid transcription (on-device Speech + Whisper API fallback).
- D-0005 Plain folder + JSON index storage.
- D-0007 Swift 6 + macOS 14+ baseline.
- D-0009 No LLM post-processing (transcript is the product).
