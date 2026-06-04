#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hermes Status Widget"
APP_DIR="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/debug/HermesStatusWidget"

cd "$ROOT"
swift build

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/HermesStatusWidget"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

chmod +x "$APP_DIR/Contents/MacOS/HermesStatusWidget"

echo "$APP_DIR"
