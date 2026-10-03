# UI

> Status: **Draft — pending reviewer sign-off**

## Scope

SwiftUI desktop app. The user can start an entry, see the live transcript,
browse past entries, replay audio, and adjust settings. No TUI, no CLI.

Related: D-0008, `architecture.md` § Layering.

## Window model

- Single main window. `WindowGroup` default size `900 × 660`, minimum `720 × 540`.
- No menu bar customization for MVP; default menu + About panel.
- `SettingsView` is a `Sheet` from the toolbar.

## Navigation

```
ContentView (timeline)
├── toolbar: "New Entry" (primary), "Settings" (secondary), "Refresh"
└── content:
    ├── RecordingView (presented as sheet when recording)
    ├── EntryDetailView (selected entry, pushed)
    └── EmptyState (no entries yet)
```

## Views

### ContentView

- `@State`-owned `ListViewModel`.
- Toolbar: `New Entry` primary button → calls VM `startRecording()`. Becomes
  **Cancel** when recording.
- List of entries (newest first), each row: date/time, source badge
  (speech/whisper/none), duration, one-line excerpt (~120 chars).
- Selection navigates to `EntryDetailView` via `NavigationStack`.

### EntryDetailView

- Full transcript as scrollable text view.
- Audio playback: play/pause, scrubber, timecode.
- If `source = .none`, show "Re-transcribe" button.
- Inline transcript editing via `TextEditor`, saved to `.md` and manifest on blur.

### RecordingView

- Modal sheet, not dismissible while recording.
- Big Start → Stop button toggle.
- Live transcript appears word-by-word (actor-updated `@State` text).
- Optional: audio level meter and elapsed timer.
- On Stop: "Finalizing…" until pipeline signals done, then auto-dismiss.

### SettingsView

- **General.** Output folder (`NSOpenPanel`), default mic (`Picker`).
- **Transcription.** "Use on-device Speech first" (default on), "Fall back to
  Whisper API" (default on), API key field (Keychain; shown as dots).
- **About.** App version, link to GitHub/docs.

## View-models

Each view has a `@MainActor @Observable` view-model, dependencies injected via
constructor:

- `ListViewModel`: `entries`, `isRecording`.
- `RecordingViewModel`: `liveTranscript`, `elapsed`, `isFinalizing`.
- `EntryDetailViewModel`: `entry`, `audioPlayer`, `transcriptText`.
- `SettingsViewModel`: API key, output folder, mic ID.

## Accessibility

- VoiceOver labels on every control.
- Timeline uses `LazyVStack`; entry rows exposed as semantic buttons.
- Transcript text is selectable (`.textSelection(.enabled)`).
- `⌘R` keyboard shortcut to toggle recording.
- Dark-mode support via system semantic colors.

## States & error handling

| State | UI |
|---|---|
| No entries | Illustrated empty state with "Record your first entry" button. |
| Recording | Modal sheet, live transcript. |
| Finalizing | Non-dismissible progress view in `RecordingView`. |
| Transcription failed | `EntryDetailView` shows "Re-transcribe" button + error. |
| Mic permission denied | Toast + "Open System Settings" button. |
| Disk full | Toast + "Choose a different folder" button. |
| Invalid API key | Toast: "Open Settings to set your API key." |

## Out of scope for v1

- Search / filter through past entries.
- Tags / folders / collections.
- Drag-and-drop reordering.
- Onboarding tour.
- Keyboard-only timeline navigation.
