# Subsystem: UI

> Status: **Draft — pending reviewer sign-off**

## Scope

SwiftUI desktop app. The user can start an entry, see the live transcript,
browse past entries, replay audio, and adjust settings. No TUI, no CLI.

Related: [`decisions.md` D-0008](../decisions.md),
[`architecture.md` Dependency Direction](../architecture.md).

## Window model

- Single main window. `Window` in a `WindowGroup` with default size
  `900 × 660`, minimum `720 × 540`.
- Beginning: no menu bar customization; the app's default menu + About panel.
- `SettingsView` is a `Sheet` presented from the toolbar, not its own window
  (Phase 1). May become a `SettingsScene` (Swift 6) or separate window later.

## Navigation

```
ContentView (timeline)
├── toolbar: "New Entry" (primary), "Settings" (secondary), "Refresh"
├── sidebar or segmented control: "All entries" | "This week" | "This month"
└── content:
    ├── RecordingView (presented as sheet when recording)
    ├── EntryDetailView (selected entry, pushed)
    └── EmptyState ("Record your first entry")
```

## Views

### `DiaryTranscriberApp` (`App/`)

- `@main` App, `winsdowsGroup`, macOS 14+ scene.
- Registers the `PermissionManager` and `TranscriptionService` as
  `@State`-owned dependencies.

### `ContentView`

- `@State`-owned `RecordingViewModel` or `ListViewModel`.
- Top toolbar: `New Entry` primary button (calls the VM `startRecording()`).
  The button becomes **Cancel** when recording is active.
- Desired state: a list of entries grouped by date (newest first), each row
  shows: date/time, source (speech/whisper/none badge), duration, one-line
  transcript excerpt (first ~120 chars).
- Selection navigates to `EntryDetailView` via `NavigationStack`.

### `EntryRowView`

- Pitch-style row; tap to expand inline, double-tap to push detail view.
- Source icon: apple logo (speech), cloud (whisper), muted pencil (none).
- Hover actions (Phase 2): Play audio, Delete.

### `EntryDetailView`

- Full transcript as a scrollable text view.
- Audio playback: play/pause button, scrubber, timecode display.
- If `source = .none`, show "Re-transcribe" button.
- Edit transcript: inline editing via `TextEditor`, save to the `.md` and
  manifest on blur.

### `RecordingView`

- Modal sheet, not dismissible while recording.
- Big Start button → Stop button toggle.
- Live transcript text appears word-by-word (actor-updated `@State` text).
- Optional: audio level meter view and elapsed timer.
- On Stop: transitions to "Finalizing…" until the recorder + store + transcription
  pipeline signals done, then auto-dismisses.

### `SettingsView`

- `Form` sections:
  1. **General.** Output folder (choose button → `NSOpenPanel`), default mic
     (`Picker` based on available audio devices).
  2. **Transcription.** "Use on-device Speech first" toggle (default on),
     "Fall back to Whisper API" toggle (default on), API key field (stored in
     Keychain on set; shown as dots).
  3. **About.** App version, link to GitHub or docs.

## View-models

Each view has a corresponding `@MainActor` `@Observable` view-model, with
dependencies injected via the environment. View-models own:

- `ContentView`: `entries: [EntryRowData]`, `isRecording: Bool`.
- `RecordingViewModel`: `liveTranscript: String`, `elapsed: TimeInterval`, `isFinalizing: Bool`.
- `EntryDetailViewModel`: `entry: DiaryEntry`, `audioPlayer: AudioPlayer?`, `transcriptText: String`.
- `SettingsViewModel`: API key, output folder, mic ID.

## Concurrency / threading

- All view-models are `@MainActor`.
- Long-running work (recording, transcription) happens in `actor`s and hands
  back immutable snapshots via `AsyncStream` or `checkedContinuation`.
- The app `internal func perform(_ closure:)` helper may be used to escape
  heavy work off `@MainActor` post-Swift-6 strict-concurrency migration.

## Accessibility

- Voiceover labels on every control.
- Timeline list uses `LazyVStack` and exposes entry rows as semantic buttons.
- Transcript text is selectable (`Text(...).textSelection(.enabled)`).
- Record/Stop button has a high-pressure state; keyboard shortcut `⌘R` to toggle.
- System Settings deep-link for microphone permission via `URL(string:
  "x-apple.system.settings:com.apple.application.notifications.NotificationsSettingsExtension")`
  (or equivalent) — document the exact deep link in Phase 2.
- High-contrast mode / dark-mode support through system semantic colors.

## States & error handling

| State | UI |
|---|---|
| No entries yet | Illustrated empty state with a "Record your first entry" button. |
| Recording | Modal sheet, live transcript. |
| Finalizing | Non-dismissible progress view in `RecordingView`. |
| Transcription failed | `EntryDetailView` shows "Re-transcribe" button + last error message. |
| Mic permission denied | Toast + "Open System Settings" button. |
| Disk full | Toast + "Choose a different folder" button. |
| Whisper API key invalid | Toast: "Open Settings to set your API key." |

## Out of scope for v1

- Search / filter through past entries.
- Tags / folders / collections.
- Drag-and-drop reordering of timeline.
- Onboarding tour / tutorial overlay.
- Keyboard-only navigation for the timeline.
