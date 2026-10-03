# Diary Transcriber — Specifications

Living specifications for the **Diary Transcriber** macOS app. These documents
define the product vision, architecture decisions, and subsystem contracts. They
are intentionally "basic" starting points — each section may be extended with
deeper detail, edge cases, and acceptance criteria as the implementation
matures.

## Document index

| Document | Purpose |
|---|---|
| [`product-vision.md`](product-vision.md) | What the product is, who it is for, what it does — and what it deliberately does *not* do (scope guards). |
| [`decisions.md`](decisions.md) | Decision log capturing every product + technical choice the team has agreed to, with rationale. Append-only. |
| [`architecture.md`](architecture.md) | Folder layout, module boundaries, dependency direction, reuse plan. |
| [`build-plan.md`](build-plan.md) | Phased roadmap from MVP to shareable `.app`/`.dmg`. |
| [`subsystems/recording.md`](subsystems/recording.md) | Audio-only recording: format, API, permission flow, lifecycle. |
| [`subsystems/transcription.md`](subsystems/transcription.md) | On-device Speech + Whisper API fallback orchestration. |
| [`subsystems/storage.md`](subsystems/storage.md) | Entry model, folder layout, `manifest.json` schema, file lifecycle. |
| [`subsystems/ui.md`](subsystems/ui.md) | SwiftUI views, navigation, recording flow, timeline, settings. |
| [`subsystems/packaging.md`](subsystems/packaging.md) | App bundle, code signing, `.dmg` distribution. |

## How to use these specs

- **Build from them.** Each subsystem doc defines the contract a module must
  meet; they are written to be implementable without re-litigating product
  decisions.
- **Extend, don't rewrite.** When a subsystem needs more detail, add a new
  subsection. When a decision changes, mark the old one **Superseded** in
  `decisions.md` and append the new one — do not silently edit history.
- **Review before coding.** A phase in `build-plan.md` should not start until
  the relevant subsystem docs have a reviewer sign-off line dated at top.

Open gaps and known risks are tracked in
[`architecture.md` § Known Risks](architecture.md#known-risks).
