# Decision Log

Append-only. Each decision has a stable ID (`D-NNNN`), date, status, and
rationale. When a decision is changed, mark its status **Superseded** and add a
new decision that references it — do not edit the original entry.

Legend: ✅ **Accepted** · 🟡 **Pending** · ⛫ **Superseded**

---

## D-0001 — Product vision: shareable desktop voice diary
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Build a shareable macOS desktop app for daily voice journaling.
  Local-first, audio-only, no LLM post-processing, no automation.
- **Rationale:** User wants a personal habit tool polished enough to share with
  friends. Manual + local adds reliability and privacy. Voice is faster than
  writing for the target user.
- **Supersedes:** —

## D-0002 — Recording modality: audio-only
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Records audio only; video recording is removed.
- **Rationale:** Diary entries are voice; video adds storage cost and friction
  without value for this use case.
- **Supersedes:** —

## D-0003 — Audio format: `.m4a` (AAC)
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Write recordings as AAC in an `.m4a` container.
- **Rationale:** Native to macOS, small (~3–10 MB per 5-min), supported by both
  Apple Speech and the Whisper API. WAV is 5–10× larger for low marginal gain.
- **Supersedes:** —

## D-0004 — Transcription: hybrid (on-device Speech + Whisper API fallback)
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Use `SFSpeechRecognizer` streaming on-device. Fall back to the
  OpenAI Whisper API (`whisper-1`) when on-device Speech errors, times out, or
  returns low-confidence text.
- **Rationale:** On-device is private and free; Whisper API is the accuracy
  backstop. See `transcription.md` for trigger conditions.
- **Supersedes:** —

## D-0005 — Storage layout: plain folder + JSON index
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Entries live as plain files in `~/Documents/Diary/`, organized
  by date. A shared `manifest.json` indexes every entry with id, date,
  duration, audio path, transcript path, and source.
- **Rationale:** Plain-folder keeps entries backup-friendly and Finder-visible.
  JSON index is simpler than SQLite for a read-mostly timeline and a single
  writer process.
- **Supersedes:** —

## D-0006 — Storage location: `~/Documents/Diary/`
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Default to `~/Documents/Diary/`; expose a setting to relocate.
- **Rationale:** Visible and backup-friendly; matches the "shareable personal
  app" vision.
- **Supersedes:** —

## D-0007 — Platform baseline: Swift 6 / macOS 14+
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Target Swift 6 strict concurrency and macOS 14+ (Sonoma).
- **Rationale:** Cleaner async/await + Sendable ergonomics; recent SwiftUI APIs
  simplify the UI. Older macOS versions are a shrinking minority for a new app.
- **Supersedes:** —

## D-0008 — UI: SwiftUI desktop app
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Build a SwiftUI desktop app with a timeline (past entries) and
  recording flow. No CLI.
- **Rationale:** A shareable personal app needs a native window, not a CLI.
- **Supersedes:** —

## D-0009 — No LLM post-processing
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** No summaries, themes, mood detection, or recaps. The transcript
  is the product.
- **Rationale:** Scope guard. Re-evaluate post-MVP.
- **Supersedes:** —

## D-0010 — Automation: manual only
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Recording is always started by the user; no scheduling or
  reminders.
- **Rationale:** Lower complexity for MVP; prevents intrusiveness.
- **Supersedes:** —

## D-0011 — Packaging: code-signed `.app` + `.dmg`
- **Date:** 2026-10-03 · **Status:** ✅ Accepted
- **Decision:** Distribute as a code-signed `.app` bundle wrapped in a `.dmg`.
- **Rationale:** A shareable app needs to install without Gatekeeper warnings.
- **Supersedes:** —

## D-0012 — Strict-concurrency enforcement: `.swiftLanguageMode(.v6)`
- **Date:** 2026-10-04 · **Status:** ✅ Accepted
- **Decision:** Enforce Swift 6 strict concurrency via `.swiftLanguageMode(.v6)`
  in `Package.swift` on all three targets (executable, library, test). No
  `.unsafeFlags(["-strict-concurrency=complete"])` is added; the Swift 6
  language mode turns on strict-concurrency checking by default.
- **Rationale:** `.swiftLanguageMode(.v6)` is equivalent to passing
  `-strict-concurrency=complete` and is the canonical, toolchain-stable way to
  opt in. Adding `.unsafeFlags` would be redundant and could clash on toolchains
  where the flag default differs. An inline comment next to each
  `swiftLanguageMode(.v6)` setting records this choice in `Package.swift`.
- **Supersedes:** — (refines D-0007)

## D-0013 — Platform baseline: macOS 15.0+ (PRD 20)
- **Date:** 2026-10-04 · **Status:** ✅ Accepted
- **Decision:** Bump the macOS deployment target from 14.0 (Sonoma) to 15.0
  (Sequoia) in `Package.swift`.
- **Rationale:** PRD 20 (Recording Output Delegate Deadlock Fix) requires
  replacing `@unchecked Sendable` fields with a `Mutex<DelegateState>` from the
  Swift 6.0 `Synchronization` module. `Synchronization.Mutex` is part of the
  Swift stdlib but is only present in the macOS 15.0+ ABI overlay; building
  against `.macOS(.v14)` fails to link `Mutex` even under `.swiftLanguageMode(.v6)`.
  The only way to satisfy the PRD's "no `@unchecked Sendable`" requirement
  without a degraded fallback path is to bump the platform to 15.0. This leaves
  older macOS 14 users unsupported until a back-port strategy is agreed; track
  the trade-off in AGENTS.md's platform baseline.
- **Supersedes:** — (refines D-0007, D-0010 platform-baseline wording)

## D-0014 — ATS exception for api.openai.com (PRD 40)
- **Date:** 2026-10-05 · **Status:** 🟡 Pending (accepted as implemented; risk
  flagged for follow-up)
- **Decision:** `NSAppTransportSecurity` in `Resources/Info.plist` sets
  `NSAllowsArbitraryLoads=false` and scopes an exception to `api.openai.com`
  only, pinning `NSExceptionRequiresForwardSecrecy=true` and
  `NSExceptionMinimumTLSVersion="TLSv1.2"`. `WhisperClient.classifyURLError`
  maps transport (`notConnectedToInternet`, `cannotFindHost`,
  `cannotConnectToHost`, `networkConnectionLost`, `dnsLookupFailed`,
  `dataNotAllowed`) and TLS (`secureConnectionFailed`,
  `serverCertificateUntrusted`, `serverCertificateHasBadDate`,
  `serverCertificateNotYetValid`) `URLError.Code`s to
  `TranscriptionError.networkUnavailable`, whose `errorDescription` reads
  `"Network unavailable: transcription failed"`. The failure surfaces via the
  PRD #25 error banner in `ListViewModel.finishRecording` (entry still
  persisted; audio never lost).
- **Rationale:** PRD 40 (ATS Handling Audit) requires that ATS be minimal and
  TLS-rejected connections surface as a user-visible error rather than a silent
  hang. OpenAI's Whisper endpoint speaks TLS 1.2+ with forward secrecy, so the
  exception is safe under current OpenAI config.
- **Risk:** OpenAI may rotate endpoints, IP ranges, or certificate authorities
  without notice. If the exception domain becomes stale or the TLS pin rejects a
  rotation, Whisper requests fail as TLS-rejected errors. The
  `classifyURLError` mapping flags these as `networkUnavailable` so the user
  sees the failure, but the exception itself must be updated if OpenAI
  introduces additional API hostnames. Track via the PRD #40 ATS audit; re-run
  `ATSHandlingAuditTests.testATS_isScopedToOpenAIDomain` when OpenAI announces
  endpoint changes.
- **Supersedes:** —
