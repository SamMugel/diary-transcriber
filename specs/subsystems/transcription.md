# Subsystem: Transcription

> Status: **Draft — pending reviewer sign-off**

## Scope

Convert a recorded `.m4a` audio file into editable text, using Apple's
on-device Speech framework as the primary engine and the OpenAI Whisper API as
a fallback when the primary engine fails or underperforms.

Related: [`subsystems/recording.md`](recording.md) for the handoff,
[`decisions.md` D-0004](../decisions.md).

## Components

```
Transcription/
├── SpeechTranscriber.swift        # Apple Speech (SFSpeechRecognizer)
├── WhisperClient.swift            # OpenAI Whisper API client
└── TranscriptionService.swift     # Orchestrates primary + fallback
```

### `SpeechTranscriber` — primary

- Uses `SFSpeechRecognizer` + `SFSpeechURLRecognitionRequest` to transcribe a
  local file URL. (Full-file transcription; live-streaming is a Phase 2
  enhancement.)
- Never instantiate more than one `SFSpeechRecognizer` at a time.
- Adheres to Live transcription as an "observability" signal only — the final
  text returned at completion is official.

**API:**

```swift
public actor SpeechTranscriber {
    public func transcribe(at audioURL: URL) async throws -> Transcript
}
```

### `WhisperClient` — fallback

- Hits `POST https://api.openai.com/v1/audio/transcriptions`.
- Model: `whisper-1`. Response format: `text` (Phase 1) → `verbose_json` (Phase 2, for segment-level confidence).
- Reads API key from the OS Keychain (never from `manifest.json`) via a
  `KeychainStore` helper in `Storage/`.
- `URLSession` with a 120s timeout. On any non-2xx response, throw a
  `WhisperClientError` that `TranscriptionService` can treat as "fall back
  failed".

**API:**

```swift
public actor WhisperClient {
    public init(apiKey: String)
    public func transcribe(at audioURL: URL) async throws -> Transcript
}
```

### `TranscriptionService` — orchestrator

Public surface for the app. Decides which engine to call and when to call the
fallback.

```swift
public actor TranscriptionService {
    public func transcribe(at audioURL: URL) -> AsyncStream<TranscriptUpdate>
}
```

Returns an `AsyncStream` so the view layer can observe incremental updates.

## Fallback trigger conditions

The service calls `WhisperClient` after `SpeechTranscriber` when **any** of:

1. Speech framework returns no text at all (empty transcript).
2. Speech transcript length < 50% of an expected minimum derived from audio
   duration × average words-per-minute (heuristic). This protects against a
   silent or buggy primary run returning a short string.
3. Speech framework throws or returns an error.
4. Recognition duration exceeds 3× the audio duration (hang protection; logs a
   diagnostic).

If the fallback also fails, the service yields a final `TranscriptUpdate` with
`status: failed` and a user-facing message; the audio file is **retained** on
disk (storage entry still written) and a "Re-transcribe" button appears in
`EntryDetailView`.

## Transcript model (returned by the service)

```swift
public struct Transcript: Hashable, Codable, Sendable {
    public var text: String               // final, cleaned text
    public var confidence: Double?        // 0..1; nil if unknown
    public var source: TranscriptSource   // .speech, .whisper, .none
    public var isFinal: Bool              // false during streaming, true at end
}

public enum TranscriptSource: String, Codable, Sendable {
    case speech, whisper, none
}
```

`TranscriptUpdate` (over `AsyncStream`):
```swift
public enum TranscriptUpdate: Sendable {
    case partial(String)                  // live text delta
    case final(Transcript)                // completed transcription
    case failed(String)                   // human-readable reason; storage entry still written
}
```

## Security

- The OpenAI API key is stored in the OS Keychain under account
  `com.compactifai.diarytranscriber.api-key`. Plain-text storage in
  `manifest.json` is explicitly forbidden.
- Whisper requests are made over HTTPS only.
- Failed requests never log the API key or audio contents to the console.

## Error taxonomy

| Error | Cause | UX |
|---|---|---|
| `speechUnavailable` | `SFSpeechRecognizer` is nil on the device (rare) | Skip to Whisper fallback silently. |
| `speechError` | Speech framework returns an error | Show warning toast; try Whisper. |
| `whisperError(status)` | API returned non-2xx | Show an error with the status; suggest API key check. |
| `whisperTimeout` | Request exceeded 120s | Offer retry; offer to keep audio-only entry. |
| `networkUnavailable` | No internet during fallback | Retain audio; mark entry as "needs transcription". |

## Known constraints / risks

- `SFSpeechRecognizer` on macOS may require network access for the first
  recognition run after install (model download). After that, on-device mode
  works offline.
- The OpenAI Whisper API supports files up to 25 MB. Our 5-min `.m4a` AAC is
  well within this; long entries approaching 30+ minutes may exceed it —
  Phase 2 should add a file-size guard.
- Live streaming transcription during recording (not after-stop) is a Phase 2
  enhancement; Phase 1 transcribes the finalized file.
- Live (during-record) streaming transcription is a Phase 2 enhancement.
  Mandate for MVP: after recording stops, pass the file URL to the
  transcriber.

## Out of scope for v1

- Speaker diarization.
- Multi-language detection / mixed-language handling.
- Live (during-recording) streaming transcription. Phase 1 transcribes the
  finalized file only.
- Custom vocabulary (e.g., names, brands) for recognition accuracy.
