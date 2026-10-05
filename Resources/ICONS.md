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
# 1. Render the SVG to a 1024×1024 PNG:
rsvg-convert -w 1024 -h 1024 Resources/AppIcon.svg -o Resources/AppIcon-1024.png

# 2. Build the full .icns set (16–1024px) via iconutil:
mkdir -p Resources/AppIcon.iconset
sips -z 16 16   Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_16x16.png
sips -z 32 32   Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_32x32.png
sips -z 64 64   Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_64x64.png
sips -z 128 128 Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_128x128.png
sips -z 256 256 Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_128x128@2x.png
sips -z 512 512 Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512 Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 Resources/AppIcon-1024.png -o Resources/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
rm -rf Resources/AppIcon.iconset

# 3. Verify:
file Resources/AppIcon.icns
# Expected: Mac OS X icon, ... bytes, "ic07" type
```

## Naming conventions

- **填充色 (Fill)**: `#2C2C3E` (MVC dark navy)
- **形状 (Shape)**: Rounded rect, radius = 224px (per macOS Big Sur guidelines)
- **前景色 (Foreground)**: White microphone glyph
