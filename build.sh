#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:-$SCRIPT_DIR/webcam-record}"

xcrun swiftc \
  -O \
  -framework Foundation \
  -framework AVFoundation \
  -Xlinker -sectcreate \
  -Xlinker __TEXT \
  -Xlinker __info_plist \
  -Xlinker "$SCRIPT_DIR/Info.plist" \
  "$SCRIPT_DIR/webcam-record.swift" \
  -o "$OUTPUT"

chmod +x "$OUTPUT"
echo "Built: $OUTPUT"
echo "Run:   $OUTPUT --list-devices"
