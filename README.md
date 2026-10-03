# Diary Transcriber

A local-first macOS desktop app for daily voice journaling. Speak a diary entry,
and the app records the audio, transcribes it, and files it in a timeline you
can browse and replay.

## Status

**In design.** The app described below is the target product. Spec documents
under [`specs/`](specs/) define the full vision, decisions, architecture, and
subsystem contracts. The code currently in this repository is a **legacy CLI
webcam recorder** (see [Legacy CLI](#legacy-cli-recorder-still-in-repo)) and
will be removed once the SwiftUI app is built.

- ✅ Product vision finalized — see [`specs/product-vision.md`](specs/product-vision.md).
- ✅ Architecture & decisions logged — [`specs/architecture.md`](specs/architecture.md), [`specs/decisions.md`](specs/decisions.md).
- ✅ Build plan & phases — [`specs/build-plan.md`](specs/build-plan.md).
- 🚧 Implementation: not started.

## What the product will do

- **Record** an audio-only diary entry from your microphone (`.m4a` / AAC).
- **Transcribe** it using Apple's on-device Speech framework, with an OpenAI
  Whisper API fallback for low-quality or failed recognition.
- **Store** entries as plain files under `~/Documents/Diary/`, indexed by a
  shared `manifest.json`.
- **Browse** past entries in a SwiftUI timeline; tap any entry to read the full
  transcript and replay the audio.

### Out of scope (explicit non-goals)

- No video recording · no LLM post-processing (no summaries, themes, mood) · no
  semantic search · no automation / scheduling · no cloud sync · no
  multi-user. See [`specs/product-vision.md`](specs/product-vision.md).

## Requirements (target release)

- macOS 14+ (Sonoma or newer).
- Swift 6 (strict concurrency).
- Xcode 16+ (for building the SwiftUI app).
- An OpenAI API key (optional, for Whisper fallback transcription).

## Build & run

*Not yet implemented.* See [`specs/build-plan.md`](specs/build-plan.md) for the
phased build-out. Legacy build instructions below for reference only — they
build the old CLI recorder, not the new app.

## Legacy CLI recorder (still in repo)

The repository currently contains a small command-line webcam + microphone
recorder that predates the diary app vision. It is **not** the diary transcriber.

| File | What it is |
|---|---|
| [`webcam-record.swift`](webcam-record.swift) | Single-file CLI Swift script. Records video + audio via AVFoundation to a `.mov` file. |
| [`build.sh`](build.sh) | Compiles the CLI recorder with `swiftc`, embedding `Info.plist` into the binary so macOS permissions work. |
| [`Info.plist`](Info.plist) | Minimal metadata + `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`. |

### Legacy usage (reference only)

```bash
./build.sh
./webcam-record --list-devices
./webcam-record -o recording.mov --duration 30
```

These files will be deleted at the end of Phase 3 of the build plan, once the
SwiftUI app replaces them. They remain in git history for reference.

## What stays from the legacy code

- `NSMicrophoneUsageDescription` string → carries forward into the app bundle's
  newer `Info.plist`.
- The `selectDevice(...)` matching pattern (exact name / partial / unique ID)
  → simplified to audio devices only.

Everything else — the video recording, signal handlers, RunLoop, CLI argument
parser — is superseded by the SwiftUI app. See
[`specs/architecture.md` § Reuse plan](specs/architecture.md).

## Project layout

The repository will be reorganized into:

```
diary-transcriber/
├── App/                  # SwiftUI @main App
├── Sources/DiaryTranscriber/  # Models, Storage, Recording, Transcription, Playback, Views
├── Resources/            # Info.plist, app icon
├── Tests/                # XCTest suites
├── specs/                # ← these spec documents
└── README.md             # this file (will become the user guide)
```

Full target layout in [`specs/architecture.md`](specs/architecture.md).

## Decision log

All product and technical decisions are recorded in
[`specs/decisions.md`](specs/decisions.md). The key ones:

- D-0001 Shareable macOS desktop voice diary, not a CLI.
- D-0002 Audio-only recording (video removed).
- D-0003 `.m4a` (AAC) format.
- D-0004 Hybrid transcription (on-device Speech + Whisper API fallback).
- D-0005 Plain folder + JSON index storage.
- D-0007 Swift 6 + macOS 14+ baseline.
- D-0009 No LLM post-processing (transcript is the product).

## License

TBD.
