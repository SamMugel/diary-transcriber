# Transcription

> Status: **Draft — pending reviewer sign-off**

## Scope

Convert a recorded `.m4a` audio file into text, using Apple's on-device Speech
framework as the primary engine and the OpenAI Whisper API as a fallback when
the primary engine fails or underperforms.

Related: `recording.md` for handoff, D-0004.

## Components

```
Transcription/
├── SpeechTranscriber.swift        # Apple Speech (SFSpeechRecognizer)
├── WhisperClient.swift            # OpenAI Whisper API client
└── TranscriptionService.swift     # Orchestrates primary + fallback
```

### SpeechTranscriber (primary)

- `SFSpeechRecognizer` + `SFSpeechURLRecognitionRequest` to transcribe a local
  file URL (full-file; live-streaming is Phase 2).
- Never instantiate more than one `SFSpeechRecognizer` at a time.

```swift
public actor SpeechTranscriber {
    public func transcribe(at audioURL: URL) async throws -> Transcript
}
```

### WhisperClient (fallback)

- `POST https://api.openai.com/v1/audio/transcriptions`, model `whisper-1`.
- API key read from OS Keychain (never `manifest.json`).
- `URLSession` with 120s timeout. Non-2xx throws `WhisperClientError`.

```swift
public actor WhisperClient {
    public init(apiKey: String)
    public func transcribe(at audioURL: URL) async throws -> Transcript
}
```

### TranscriptionService (orchestrator)

Decides which engine to call and when to fall back.

```swift
public actor TranscriptionService {
    public func transcribe(at audioURL: URL) -> AsyncStream<TranscriptUpdate>
}
```

## Fallback trigger conditions

Service calls `WhisperClient` after `SpeechTranscriber` when **any** of:

1. Speech returns no text (empty transcript).
2. Transcript length < 50% of an expected minimum derived from audio duration ×
   average words-per-minute (heuristic).
3. Speech throws or returns an error.
4. Recognition duration exceeds 3× the audio duration (hang protection).

If the fallback also fails, the service yields `TranscriptUpdate.failed`; the
audio file is retained on disk and a "Re-transcribe" button appears in
`EntryDetailView`.

## Models

```swift
public struct Transcript: Hashable, Codable, Sendable {
    public var text: String
    public var confidence: Double?        // 0..1; nil if unknown
    public var source: TranscriptSource   // .speech, .whisper, .none
    public var isFinal: Bool
}

public enum TranscriptSource: String, Codable, Sendable {
    case speech, whisper, none
}

public enum TranscriptUpdate: Sendable {
    case partial(String)
    case final(Transcript)
    case failed(String)                   // human-readable; entry still saved
}
```

## Security

- OpenAI API key stored in OS Keychain under
  `com.compactifai.diarytranscriber.api-key`.
- Whisper requests over HTTPS only.
- Never log API key or audio contents to the console.

## Error taxonomy

| Error | Cause | UX |
|---|---|---|
| `speechUnavailable` | `SFSpeechRecognizer` nil on device | Skip to Whisper silently. |
| `speechError` | Speech framework error | Warning toast; try Whisper. |
| `whisperError(status)` | API returned non-2xx | Error with status; suggest API key check. |
| `whisperTimeout` | Request exceeded 120s | Offer retry or audio-only entry. |
| `networkUnavailable` | No internet during fallback | Retain audio; mark as "needs transcription." |

## Known constraints

- `SFSpeechRecognizer` on macOS may require network access for the first run
  after install (model download), then works offline.
- Whisper API supports files up to 25 MB. A 5-min `.m4a` is well within this;
  30+ min entries may exceed it — add a file-size guard in Phase 2.

## Out of scope for v1

- Speaker diarization.
- Multi-language detection.
- Live during-recording streaming (Phase 2).
- Custom vocabulary.
