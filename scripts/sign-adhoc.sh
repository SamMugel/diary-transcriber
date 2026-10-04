#!/bin/bash
# sign-adhoc.sh — Adhoc-sign the built .app for internal testing
# Usage: ./scripts/sign-adhoc.sh [path/to/DiaryTranscriber.app]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$PROJECT_ROOT/build/release/Build/Products/Release/DiaryTranscriber.app}"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found. Run ./scripts/package.sh first."
  exit 1
fi

echo "adhoc-signing $APP_PATH..."
codesign -s - --timestamp -f "$APP_PATH"

echo "verifying signature..."
codesign --verify --verbose=4 "$APP_PATH"

echo "adhoc signing complete."
