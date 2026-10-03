# Decision Log

Append-only. Each decision has a stable ID (`D-NNNN`), date, status, and
rationale. When a decision is changed, mark its status **Superseded** and add a
new decision that references it — do not edit the original entry.

Legend:
- ✅ **Accepted** — active, builds should conform.
- 🟡 **Pending** — preliminarily accepted; awaits reviewer sign-off.
- ⛫ **Superseded** — replaced by a later decision.

---

## D-0001 — Product vision: shareable desktop voice diary
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Build a shareable macOS desktop app for daily voice journaling.
  Local-first, audio-only, no LLM post-processing, no automation.
- **Rationale:** User wants a personal habit tool polished enough to share with
  friends. Manual + local adds reliability and privacy. Voice is faster than
  writing for the target user.
- **Supersedes:** —

## D-0002 — Recording modality: audio-only
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Records audio only; video recording is removed.
- **Rationale:** Diary entries are voice; video adds storage cost and friction
  without value for this use case. Affects: AVFoundation wiring, Info.plist,
  manifest schema.
- **Supersedes:** —

## D-0003 — Audio format: `.m4a` (AAC)
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Write recordings as AAC in an `.m4a` container.
- **Rationale:** Native to macOS, small (~3–10 MB per 5-min), lossless-ish
  quality, supported by both Apple Speech and the Whisper API. WAV is 5–10×
  larger for low marginal quality gain.
- **Supersedes:** —

## D-0004 — Transcription: hybrid (on-device Speech + Whisper API fallback)
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Use `SFSpeechRecognizer` streaming on-device. Fall back to the
  OpenAI Whisper API (`whisper-1`) when on-device Speech errors, times out, or
  returns low-confidence text.
- **Rationale:** On-device is private and free; Whisper API is the accuracy
  backstop. See [`subsystems/transcription.md`](subsystems/transcription.md) for
  the trigger conditions.
- **Supersedes:** —

## D-0005 — Storage layout: plain folder + JSON index
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Entries live as plain files in `~/Documents/Diary/`, organized
  by date. A shared `manifest.json` indexes every entry with id, date,
  duration, audio path, transcript path, and source (on-device vs. Whisper).
- **Rationale:** Plain-folder keeps entries backup-friendly and Finder-visible.
  JSON index is simpler than SQLite for a read-mostly timeline and a single
  writer process.
- **Supersedes:** —

## D-0006 — Storage location: `~/Documents/Diary/`
- **Date:** 2026-10-03
- **Status:** 🟡 Pending
- **Decision:** Default to `~/Documents/Diary/`; expose a setting to relocate.
- **Rationale:** Visible and backup-friendly; matches the "shareable personal
  app" vision of being user-discoverable.
- **Supersedes:** —

## D-0007 — Platform baseline: Swift 6 / macOS 14+
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Target Swift 6 strict concurrency and macOS 14+ (Sonoma).
- **Rationale:** Cleaner async/await + Sendable ergonomics; recent SwiftUI
  APIs (`TimelineView`, `.monospaced`, `SettingsLink`) simplify the UI. Macs on
  macOS 14 or earlier are a shrinking minority for a new app and not worth the
  cost of compile-time branching for MVP.
- **Supersedes:** —

## D-0008 — UI: SwiftUI desktop app
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Build a SwiftUI desktop app with a timeline (past entries) and
  recording flow. No CLI.
- **Rationale:** A shareable personal app needs a native window, not a CLI. The
  existing `webcam-record.swift` CLI is legacy reference until replaced.
- **Supersedes:** —

## D-0009 — No LLM post-processing
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** No summaries, no themes, no mood detection. The transcript is
  the product.
- **Rationale:** Scope guard — the goal is transcription + archival, not a
  reflection helper. Re-evaluate post-MVP.
- **Supersedes:** —

## D-0010 — Automation: manual only
- **Date:** 2026-10-03
- **Status:** ✅ Accepted
- **Decision:** Recording is always started by the user; no scheduling or
  reminders.
- **Rationale:** Lower complexity for MVP; prevents the app being intrusive on a
  user's day.
- **Supersedes:** —

## D-0011 — Packaging: code-signed `.app` + `.dmg`
- **Date:** 2026-10-03
- **Status:** 🟡 Pending
- **Decision:** Distribute as a code-signed `.app` bundle wrapped in a `.dmg`.
- **Rationale:** A shareable app needs to install without scary "unidentified
  developer" warnings.
- **Supersedes:** —
