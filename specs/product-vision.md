# Product Vision

> Status: **Draft — pending reviewer sign-off**

## One-liner

A shareable, local-first macOS desktop app that turns a daily voice recording
into a permanent entry: an transcribed diary that the user can revisit and replay.

## Target user

A person who wants to keep a personal written journal but finds speaking faster
than writing — and wants the transcript to live alongside the audio for
reassurance, reflection, and permanence. The user is also the product's likely
*distributor*: the app must be clean enough to share with friends and family who
are not technical.

## What the product does

1. **Record.** User taps "New entry → Record"; the app captures audio from the
   system's default microphone into an `.m4a` (AAC) file.
2. **Transcribe.** While recording, on-device Speech recognition streams live
   text into the UI. If the on-device engine errors, times out, or produces a
   low-confidence result, the app falls back to the OpenAI Whisper API.
3. **Persist.** The audio, transcript, and metadata are written to a dated
   folder under `~/Documents/Diary/`, and an index entry is appended to a shared
   `manifest.json`.
4. **Revisit.** The timeline view lists all past entries (newest first), each
   expandable to show the full transcript with audio playback controls.

## What the product deliberately does NOT do (scope guards)

These are explicit non-goals. They are documented to prevent scope creep — any
pr that adds them should be rejected unless `decisions.md` is updated first.

- ❌ **No video recording.** Audio-only — see D-0002.
- ❌ **No LLM post-processing.** No summaries, no themes, no mood detection, no
  weekly recaps. The transcript is the truth.
- ❌ **No semantic search.** No embeddings, no "find me entries about work", no
  reverse index.
- ❌ **No automation.** No scheduled recordings, no launchd plists, no
  reminders. The user always starts recording manually.
- ❌ **No cloud sync.** Entries stay local. (Cloud sync may be revisited post-MVP
  but is out of scope for the first shareable release.)
- ❌ **No multi-user / accounts.** Single-user, single-machine.

## Quality bars

- **First run to first entry in < 60 seconds.** Permission prompts included —
  the app must guide the user through them.
- **Single-entry transcription accuracy** ≥ 90% measured against a fixed set of
  10 test recordings spanning 30s–5min, both on-device and via fallback.
- **5-minute entry storage footprint** ≤ 15 MB (audio + transcript + index).
- **Timeline renders 1,000 entries** in < 500 ms (virtualized list, no blocking
  I/O on the main thread).
