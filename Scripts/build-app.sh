#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hermes Status Widget"
APP_DIR="$ROOT/dist/$APP_NAME.app"
BUILT_APP="$ROOT/.xcode-derived/Build/Products/Debug/$APP_NAME.app"

cd "$ROOT"
xcodebuild \
  -project HermesStatusWidget.xcodeproj \
  -scheme HermesStatusWidget \
  -configuration Debug \
  -derivedDataPath .xcode-derived \
  build

rm -rf "$APP_DIR"
mkdir -p "$ROOT/dist"
cp -R "$BUILT_APP" "$APP_DIR"

codesign \
  --force \
  --sign - \
  --entitlements "$ROOT/Widget/HermesStatusWidgetExtension.entitlements" \
  --timestamp=none \
  --generate-entitlement-der \
  "$APP_DIR/Contents/PlugIns/HermesStatusWidgetExtension.appex"

codesign \
  --force \
  --sign - \
  -o runtime \
  --timestamp=none \
  "$APP_DIR"

/usr/bin/pluginkit -r "$BUILT_APP/Contents/PlugIns/HermesStatusWidgetExtension.appex" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -u "$BUILT_APP" >/dev/null 2>&1 || true

echo "$APP_DIR"
