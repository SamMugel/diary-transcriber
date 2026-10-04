#!/bin/bash
# sign-developer-id.sh — Developer ID signing for distribution
# Usage: ./scripts/sign-developer-id.sh [path/to/DiaryTranscriber.app]
#
# Requires: "Developer ID Application: Diary Transcriber" certificate in Keychain.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$PROJECT_ROOT/build/release/Build/Products/Release/DiaryTranscriber.app}"
SIGN_IDENTITY="Developer ID Application: Diary Transcriber"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found. Run ./scripts/package.sh first."
  exit 1
fi

echo "developer-ID-signing $APP_PATH..."
codesign -s "$SIGN_IDENTITY" --timestamp --options runtime "$APP_PATH"

echo "verifying signature..."
codesign --verify --verbose=4 "$APP_PATH"

echo "Developer ID signing complete."
