# Specifications

Living specifications for the **Diary Transcriber** macOS app — a local-first
SwiftUI desktop voice diary. Each document covers one domain topic. All are
drafts, extendable as implementation matures.

## Overview

| Spec | Domain | Purpose |
|---|---|---|
| [product-vision](specs/product-vision.md) | Product | What the app is, who it's for, explicit non-goals |
| [decisions](specs/decisions.md) | Product · Technical | Append-only decision log (D-0001–D-0011) |
| [architecture](specs/architecture.md) | Technical | Folder layout, layering, concurrency model, risks |
| [build-plan](specs/build-plan.md) | Process | Phased MVP → shareable release roadmap |
| [recording](specs/recording.md) | Subsystem | Audio-only AVFoundation capture, permission flow, lifecycle |
| [transcription](specs/transcription.md) | Subsystem | Hybrid Speech + Whisper API fallback orchestration |
| [storage](specs/storage.md) | Subsystem | Folder layout, manifest.json schema, DiaryStore API |
| [ui](specs/ui.md) | Subsystem | SwiftUI views, navigation, view-models, accessibility |
| [packaging](specs/packaging.md) | Subsystem | App bundle, code signing, .dmg distribution |

## How to use these specs

- **Build from them.** Each subsystem doc defines the contract a module must
  meet — implementable without re-litigating product decisions.
- **Extend, don't rewrite.** Add subsections for deeper detail. When a decision
  changes, mark the old one **Superseded** in `decisions.md` and append the new
  one.
- **Review before coding.** A phase in `build-plan.md` should not start until
  the relevant subsystem docs have reviewer sign-off.
