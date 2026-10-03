# Recording

> Status: **Draft — pending reviewer sign-off**

## Scope

Capture audio from the selected microphone and write it to an `.m4a` (AAC)
file on disk. No transcription happens here; no video.

Related: `transcription.md` for handoff, `storage.md` for folder layout,
D-0002 · D-0003 for audio-only and AAC format.

## API

- **AVFoundation** (`AVCaptureSession` + `AVCaptureAudioFileOutput`) for
  audio capture and file writing.
- Alternative: `AVAudioEngine` for fine-grained processing. **Not required**
  for MVP.

## Input selection

- Default: `AVCaptureDevice.default(for: .audio)`.
- Override via user-chosen input in `SettingsView` (stores device `uniqueID`).
- Device resolution: partial-name / unique-ID matching.

## Recording lifecycle

The recorder is a `final class` or `actor` exposing:

```swift
func start() async throws -> RecordingHandle
func stop() async throws -> URL
```

- `start()`:
  1. Validate microphone permission via `PermissionManager`.
  2. Configure `AVCaptureSession` with a single audio input.
  3. Add `AVCaptureAudioFileOutput`, set output format to `.m4a`.
  4. Create parent directory if missing; replace existing file if present.
  5. `session.startRunning()` then `output.startRecording(to: url)`.
- `stop()`:
  1. Idempotent — early return if not recording.
  2. `output.stopRecording()` — asynchronous finalization.
  3. `didFinishRecordingTo` callback is the **hard handoff point**: storage
     entry and transcription must not start until the output file is closed.

## Permission flow

`PermissionManager` is a `@MainActor` helper:

1. Check `AVCaptureDevice.authorizationStatus(for: .audio)`.
2. If `.notDetermined`, request via `AVCaptureDevice.requestAccess(for:)`
   wrapped in `withCheckedContinuation`.
3. If `.denied` or `.restricted`, throw a typed `RecorderError` that the UI
   maps to a "Open System Settings → Privacy → Microphone" deep-link button.
4. First-launch edge case: AVFoundation may need an app restart after granting
   permission. Show a friendly dialog.

## Error handling

| Error | Cause | Recovery |
|---|---|---|
| `permissionDenied` | Mic access denied | Deep-link to System Settings; retry. |
| `noDevice` | No microphone found | Use default; surface warning. |
| `cannotAddOutput` | Session reject | Retry with fresh session. |
| `recordingFailed` | `didFinishRecordingTo` error | Stash partial file as `.m4a.partial` for recovery. |

## Concurrency

- Runs on a dedicated `actor` separate from `@MainActor`.
- Audio sample buffers are not sampled for transcription in MVP — transcription
  launches after recording stops (full-file pass to Speech/Whisper).
- `RecordingHandle` lets the UI observe: elapsed time, audio level (optional),
  and a Stop callback.

## Out of scope for v1

- Input gain control / normalization.
- Multi-microphone mixing.
- Backgrounded-app recording continuation.
- Live audio waveform visualization.
