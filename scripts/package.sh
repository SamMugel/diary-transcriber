#!/bin/bash
# package.sh — Build DiaryTranscriber.app (Release configuration)
# Usage: ./scripts/package.sh
#
# Produces: build/release/DiaryTranscriber.app

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/release"
APP_NAME="DiaryTranscriber"

echo "building $APP_NAME (Release)..."
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build 2>&1 | tail -20

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found after build"
  exit 1
fi

# Copy Info.plist and icon into the app bundle.
PLIST_SRC="$PROJECT_ROOT/Resources/Info.plist"
ICON_SRC="$PROJECT_ROOT/Resources/AppIcon.icns"

if [ -f "$PLIST_SRC" ]; then
  cp "$PLIST_SRC" "$APP_PATH/Contents/Info.plist"
fi

if [ -f "$ICON_SRC" ]; then
  mkdir -p "$APP_PATH/Contents/Resources"
  cp "$ICON_SRC" "$APP_PATH/Contents/Resources/"
fi

echo "$APP_NAME.app built at: $APP_PATH"
