#!/bin/bash
# package.sh — Build DiaryTranscriber.app (Release configuration)
# Usage: ./scripts/package.sh
#
# Produces: build/release/DiaryTranscriber.app

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Change to the project root so xcodebuild can discover the .xcodeproj/workspace
# regardless of where this script was invoked from (e.g. `cd /tmp && package.sh`).
if ! cd "$PROJECT_ROOT"; then
  echo "error: cannot cd to project root: $PROJECT_ROOT" >&2
  exit 1
fi

BUILD_DIR="$PROJECT_ROOT/build/release"
APP_NAME="DiaryTranscriber"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

echo "building $APP_NAME (Release)..."
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build 2>&1 | tail -5

BINARY="$BUILD_DIR/Build/Products/Release/$APP_NAME"

if [ ! -f "$BINARY" ]; then
  echo "error: $BINARY not found after build"
  exit 1
fi

# Assemble .app bundle from the bare executable.
echo "assembling $APP_NAME.app..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BINARY" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

# Copy Info.plist and icon into the app bundle.
PLIST_SRC="$PROJECT_ROOT/Resources/Info.plist"
ICON_SRC="$PROJECT_ROOT/Resources/AppIcon.icns"

if [ -f "$PLIST_SRC" ]; then
  cp "$PLIST_SRC" "$APP_PATH/Contents/Info.plist"
fi

if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP_PATH/Contents/Resources/"
fi

echo "$APP_NAME.app built at: $APP_PATH"
