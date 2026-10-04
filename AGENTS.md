# Project conventions

- `AGENTS.md` holds high-level, always-on project instructions.
- `opencode.json` loads `.opencode/rules/*.md`.
- `.opencode/rules/` contains one rule per file, named `NN-<kebab-case>.md`.
- `.mdc` files are glob-scoped, frontmatter-bearing Cursor-style rules that also follow the `NN-<kebab-case>` prefix (continuing from `10-` after the `.md` workflow rules occupy `01-`–`09-`) and keep the `.mdc` extension to distinguish them from always-on `.md` workflow rules.
- `.opencode/skills/` contains one directory per skill, each with a `SKILL.md`.
- A rule file contains only `# <Rule Name>` followed by a concise, imperative rule.
- Reuse or update existing rules and skills; do not duplicate.
- Do not create alternative rule or skill locations.
- Preserve these conventions unless explicitly instructed otherwise.

## Build commands

- **Build:** `swift build`
- **Test:** `swift test`
- **Lint:** `swift build` (treat warnings as failures)
- **Package:** `xcodebuild -scheme DiaryTranscriber -configuration Release build`

## Toolchain

- Swift 6+ with strict concurrency (`-strict-concurrency=complete`).
- macOS 14+ (Sonoma) deployment target.
- Xcode 16+.
- Dependencies: Apple AVFoundation, Speech framework; OpenAI Whisper API via URLSession.

## Source layout

See `specs/architecture.md` for the canonical folder structure:

```
App/                  # @main App entry
Sources/DiaryTranscriber/
  Models/             # DiaryEntry, Transcript, TranscriptSource, TranscriptUpdate
  Storage/            # DiaryStore, FileSystemWatcher
  Recording/          # AudioRecorder, PermissionManager
  Transcription/      # SpeechTranscriber, WhisperClient, TranscriptionService
  Playback/           # AudioPlayer
  Views/              # ContentView, EntryDetailView, RecordingView, SettingsView
Resources/            # Info.plist, Assets.xcassets
Tests/                # XCTest suites
```
