# Subsystem: Packaging & Distribution

> Status: **Draft — pending reviewer sign-off**

## Scope

Yield a code-signed `.app` bundle, wrapped in a `.dmg`, that a non-technical
macOS user can install by double-clicking. Related decision:
[`decisions.md` D-0011](../decisions.md#d-0011) (pending).

## Bundle contents

```
DiaryTranscriber.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── DiaryTranscriber      # executable
    └── Resources/
        ├── Assets.xcassets/
        │   └── AppIcon.icns      # 16–1024px set
        └── en.lproj/             # default English strings (if localized)
```

## Info.plist requirements

| Key | Value | Note |
|---|---|---|
| `CFBundleIdentifier` | `com.compactifai.diarytranscriber` | Reverse-DNS. |
| `CFBundleName` | `DiaryTranscriber` | User-visible name. |
| `CFBundleVersion` | `1` (incremented per build) | Build number. |
| `CFBundleShortVersionString` | `1.0.0` | SemVer. |
| `CFBundleExecutable` | `DiaryTranscriber` | Matches executable name. |
| `LSMinimumSystemVersion` | `14.0` | macOS 14+ (D-0007). |
| `NSMicrophoneUsageDescription` | `Diary Transcriber records your voice to create diary entries.` | Required for microphone access. |
| `NSCameraUsageDescription` | ❌ *Removed* | Audio-only — no camera. |
| `NSMicrophoneUsesSecondVoicePartySpeechRecognition` | `false` | We use Apple Speech on-device; no third-party calls for speech recognition. (The Whisper API path does not use this key.) |
| `LSApplicationCategoryType` | `public.app-category.productivity` | Mac App Store category. |

## Code signing

1. **Adhoc for internal testing.** `codesign -s - --timestamp -f <app>` —
   sufficient for the developer's own machine and ad-hoc testing.
2. **Developer ID for distribution.** Acquire a Developer ID Application
   certificate via Apple Developer Program. Sign with:
   `codesign -s "Developer ID Application: Diary Transcriber" --timestamp --options runtime <app>`.
3. **Notarize.** `xcrun notarytool submit` against Apple's notary service.
   Required for distribution without Gatekeeper warnings.

## `.dmg` packaging

Use [`create-dmg`](https://github.com/create-dmg/create-dmg) from Homebrew, or
`productbuild` from Xcode. Default output:
`DiaryTranscriber-1.0.0.dmg`. Requires the `.app` to be signed first.

## CI / release checklist (manual for v1)

- [ ] Bump `CFBundleVersion` and `CFBundleShortVersionString`.
- [ ] `xcodebuild -scheme DiaryTranscriber -configuration Release build`.
- [ ] Adhoc-test the `.app` on a clean macOS 14 VM.
- [ ] Developer-ID sign.
- [ ] Notarize.
- [ ] Staple ticket to the `.app` (`xcrun stapleTicket`).
- [ ] Bundle into `.dmg`.
- [ ] Publish to GitHub Releases (or equivalent distribution point).
