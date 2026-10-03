# Subsystem: Recording

> Status: **Draft — pending reviewer sign-off**

## Scope

Capture audio from the selected microphone and write it to an `.m4a` (AAC)
file on disk. No transcription happens here; no video.

Related: [`subsystems/transcription.md`](transcription.md) for the handoff to
the transcription layer, [`subsystems/storage.md`](storage.md) for the folder
layout, [`decisions.md` D-0002 · D-0003](../decisions.md) for audio-only and
AAC format.

## API mandate

- Use **AVFoundation** (`AVCaptureSession` + `AVCaptureAudioFileOutput`) for
  audio capture and file writing. Matches the existing codebase's AVFoundation
  usage and gives us access to input/output connection routing.
- Alternative: `AVAudioEngine` for fine-grained processing. **Not required** for
  MVP — only resort to it if AAC bit-rate tuning is needed.

## Input selection

- Default: `AVCaptureDevice.default(for: .audio)`.
- Override via the user-chosen input in `SettingsView` (stores the device's
  `uniqueID`).
- Device resolution reuses the partial-name / unique-ID matching pattern from
  the legacy `selectDevice(...)`; corrected for the `AVCaptureDevice` async
  life-cycle.

## Recording lifecycle

The recorder is a `final class` (or `actor`) that exposes:

```swift
func start() async throws -> RecordingHandle
func stop() async throws -> URL
```

- `start()`:
  1. Validate microphone permission via `PermissionManager`.
  2. Configure `AVCaptureSession` with a single audio input.
  3. Add `AVCaptureAudioFileOutput`, set output format to `.m4a`.
     - Container: `.mov` (still works for audio-only AAC) or `.m4a` (preferred;
       verify supported).
  4. Create parent directory if missing.
  5. Replace any existing file at the target path.
  6. `session.startRunning()` then `output.startRecording(to: url)`.
- `stop()`:
  1. Idempotent — early return if not recording.
  2. `output.stopRecording()` — this is an *asynchronous* finalization.
  3. The `didFinishRecordingTo` callback is the **hard handoff point**:
     storage entry must not be written, transcription must not begin, until the
     output file is closed on disk. See `subsystems/storage.md` § Handoff.

## Permission flow

`PermissionManager` is a small `@MainActor` helper:

1. Check `AVCaptureDevice.authorizationStatus(for: .audio)`.
2. If `.notDetermined`, request access without blocking the UI thread — use
   async/await wrapping `AVCaptureDevice.requestAccess(for:)` as a
   `withCheckedContinuation`.
3. If `.denied` or `.restricted`, throw a typed `RecorderError` that the UI maps
   to a "Open System Settings → Privacy → Microphone" deep-link button.
4. Handle first-launch edge case: AVFoundation may need an app restart after
   the user grants permission. Show a friendly dialog ("Please restart the
   app to apply microphone access").

## Output file naming

See [`subsystems/storage.md`](storage.md). Pattern:
`~/Documents/Diary/{YYYY-MM-DD}-{HHMMss}.m4a`. The recorder owns the path
construction so the `RecordingView` view-model only passes a `Date` and the
`DiaryStore` returns the resolved path.

## Error handling

| Error | Cause | Recovery |
|---|---|---|
| `permissionDenied` | Mic access denied | Deep-link to System Settings; retry when granted. |
| `noDevice` | No microphone found | Use default; surface a warning toast. |
| `cannotAddOutput` | Session reject | Retry once with a fresh session; if still failing, log diagnostics. |
| `recordingFailed` | `didFinishRecordingTo` fired with error | Stash the partial file (if any) as `.h4a.partial` for later recovery; surface a "Save error" dialog. |

## Layout and concurrency

- Runs on a dedicated `DispatchQueue` or `actor` separate from `@MainActor`.
- Audio sample buffers are *not* periodically sampled for transcription in
  MVP — transcription launches after recording stops (full-file pass to
  Speech/Whisper). Streaming transcription adds complexity to Phase 1; listed
  as a `D-NNNN` decision pending.
- `RecordingHandle` (returned by `start()`) lets the UI observe: elapsed time,
  current audio level meter (optional), and a `Stop` callback.

## Out of scope for v1

- Input gain control / normalization.
- Multi-microphone mixing.
- Backgrounded-applewdriving-edge-case recording continuation.
- Live audio waveform visualization.
