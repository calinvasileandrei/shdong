#!/bin/sh
# Builds Shdong.app from the SwiftPM executable and signs it (ad-hoc unless SIGN_ID is set).
#   scripts/bundle.sh            → build/Shdong.app (release)
#   SIGN_ID="Developer ID Application: …" scripts/bundle.sh
set -eu
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
swift build -c "$CONFIG" --product Shdong
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Shdong"
APP=build/Shdong.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shdong"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --entitlements Resources/Shdong.entitlements \
  --sign "${SIGN_ID:--}" "$APP"
echo "built $APP"
