# App Icon Assets

This directory contains app icon assets for DiaryTranscriber.

## Current files

| File | Description |
|------|-------------|
| `AppIcon.svg` | 1024×1024 vector template. Replace with final design. |
| `Info.plist` | Bundle Info.plist with icon references. |

## Generating the .icns file

To create `AppIcon.icns` from a 1024×1024 PNG:

```bash
# 1. Export a 1024×1024 PNG (name: AppIcon-1024.png)
# 2. Generate the .icns set:
sips -s format icns Resources/AppIcon-1024.png --out Resources/AppIcon.icns

# 3. Verify:
file Resources/AppIcon.icns
# Expected: Mac OS X icon file (.icns) containing ...
```

Or use `iconutil`:

```bash
mkdir AppIcon.iconset
sips -z 16 16 AppIcon-1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32 AppIcon-1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64 AppIcon-1024.png --out AppIcon.iconset/icon_64x64.png
sips -z 128 128 AppIcon-1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256 AppIcon-1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512 AppIcon-1024.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 AppIcon-1024.png --out AppIcon.iconset/icon_1024x1024.png
iconutil -c icns AppIcon.iconset
mv AppIcon.icns Resources/
```

## Naming conventions

- **填充色 (Fill)**: `#2C2C3E` (MVC dark navy)
- **形状 (Shape)**: Rounded rect, radius = 224px (per macOS Big Sur guidelines)
- **前景色 (Foreground)**: White microphone glyph
