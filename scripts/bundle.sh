#!/usr/bin/env bash
# Builds the SPM executable and wraps it in build/Resize.app (a menu bar app with no Dock icon).
set -euo pipefail
CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c "$CONFIG" --package-path "$ROOT" >&2
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Resize"
APP="$ROOT/build/Resize.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Resize"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Ad-hoc signing with a fixed identifier keeps the Accessibility grant stable across rebuilds more often.
codesign --force --sign - --identifier dev.xingyulong.Resize "$APP" >&2
echo "$APP"
