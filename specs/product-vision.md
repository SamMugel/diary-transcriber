# Product Vision

> Status: **Draft — pending reviewer sign-off**

## One-liner

A shareable, local-first macOS desktop app that turns a daily voice recording
into a permanent entry: a transcribed diary the user can revisit and replay.

## Target user

A person who wants a personal journal but finds speaking faster than writing —
and wants the transcript to live alongside the audio for reassurance,
reflection, and permanence. The user is also the likely *distributor*: the app
must be clean enough to share with non-technical friends and family.

## What the product does

1. **Record.** User taps "New entry → Record"; the app captures audio from the
   default microphone into an `.m4a` (AAC) file.
2. **Transcribe.** On-device Speech recognition streams live text into the UI.
   If it errors, times out, or returns low-confidence results, the app falls
   back to the OpenAI Whisper API.
3. **Persist.** Audio, transcript, and metadata are written to a dated folder
   under `~/Documents/Diary/`; an index entry is appended to `manifest.json`.
4. **Revisit.** The timeline lists all entries (newest first), each expandable
   to show the full transcript with audio playback.

## What the product deliberately does NOT do (scope guards)

Explicit non-goals. Any PR adding them should be rejected unless `decisions.md`
is updated first.

- ❌ **No video recording.** Audio-only — see D-0002.
- ❌ **No LLM post-processing.** No summaries, themes, mood detection, or
  recaps. The transcript is the truth.
- ❌ **No semantic search.** No embeddings, reverse index, or "find entries
  about X."
- ❌ **No automation.** No scheduled recordings, launchd plists, or reminders.
- ❌ **No cloud sync.** Entries stay local.
- ❌ **No multi-user / accounts.** Single-user, single-machine.

## Quality bars

- **First run to first entry in < 60 seconds** (including permission prompts).
- **Transcription accuracy ≥ 90%** against a fixed set of 10 test recordings
  (30s–5min), both on-device and via fallback.
- **5-min entry storage footprint ≤ 15 MB** (audio + transcript + index).
- **Timeline renders 1,000 entries in < 500 ms** (virtualized, non-blocking).
