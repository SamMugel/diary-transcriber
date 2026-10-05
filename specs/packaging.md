# Packaging & Distribution

> Status: **Draft — pending reviewer sign-off**

## Scope

Yield a code-signed `.app` bundle, wrapped in a `.dmg`, that a non-technical
macOS user can install by double-clicking. Related: D-0011.

## Bundle contents

```
DiaryTranscriber.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── DiaryTranscriber      # executable
    └── Resources/
        └── Assets.xcassets/
            └── AppIcon.icns      # 16–1024px set
```

## Info.plist

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `com.compactifai.diarytranscriber` |
| `CFBundleName` | `DiaryTranscriber` |
| `CFBundleVersion` | `1` (incremented per build) |
| `CFBundleShortVersionString` | `1.0.0` |
| `CFBundleExecutable` | `DiaryTranscriber` |
| `LSMinimumSystemVersion` | `15.0` |
| `NSMicrophoneUsageDescription` | `Diary Transcriber records your voice to create diary entries.` |
| `LSApplicationCategoryType` | `public.app-category.productivity` |

## Code signing

1. **Adhoc (internal testing).** `codesign -s - --timestamp -f <app>`.
2. **Developer ID (distribution).** Acquire a Developer ID Application
   certificate, sign with `codesign -s "Developer ID Application: Diary
   Transcriber" --timestamp --options runtime <app>`.
3. **Notarize.** `xcrun notarytool submit` against Apple's notary service.

## .dmg packaging

Use [`create-dmg`](https://github.com/create-dmg/create-dmg) or `productbuild`.
Default output: `DiaryTranscriber-1.0.0.dmg`. Requires signed `.app` first.

## Release checklist

- [ ] Bump `CFBundleVersion` and `CFBundleShortVersionString`.
- [ ] `xcodebuild -scheme DiaryTranscriber -configuration Release build`.
- [ ] Adhoc-test on a clean macOS 15 VM.
- [ ] Developer-ID sign.
- [ ] Notarize.
- [ ] Staple ticket (`xcrun stapleTicket`).
- [ ] Bundle into `.dmg`.
- [ ] Publish to GitHub Releases.
