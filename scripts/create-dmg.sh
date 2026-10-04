#!/bin/bash
# create-dmg.sh — Build a .dmg installer from the signed .app
# Usage: ./scripts/create-dmg.sh
#
# Produces: build/release/DiaryTranscriber-1.0.0.dmg
# Requires: create-dmg (brew install create-dmg), or hdiutil as fallback.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/release"
APP_NAME="DiaryTranscriber"
VERSION="1.0.0"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found. Run ./scripts/package.sh first."
  exit 1
fi

# Ensure .app is signed before packaging.
if ! codesign --verify "$APP_PATH" 2>/dev/null; then
  echo "warning: $APP_PATH is not signed. Running adhoc sign..."
  codesign -s - --timestamp -f "$APP_PATH"
fi

echo "creating .dmg at $DMG_PATH..."

# Try create-dmg first; fall back to hdiutil.
if command -v create-dmg &> /dev/null; then
  create-dmg \
    --volname "$APP_NAME" \
    --window-size 400 300 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 100 100 \
    "$DMG_PATH" \
    "$APP_PATH"
else
  # Fallback: use hdiutil to create a simple DMG.
  TEMP_DMG="$BUILD_DIR/temp-${APP_NAME}.dmg"
  hdiutil create \
    -ov \
    -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -fs APFS \
    "$TEMP_DMG"

  # Compress and finalize.
  hdiutil convert "$TEMP_DMG" -format UDBZ -o "$DMG_PATH"
  rm -f "$TEMP_DMG"
fi

echo ""
echo "Created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
