#!/bin/sh
# Builds Shdong.app from the SwiftPM executable and signs it (ad-hoc unless SIGN_ID is set).
#   scripts/bundle.sh            → build/Shdong.app (release, universal arm64 + x86_64)
#   SIGN_ID="Developer ID Application: …" scripts/bundle.sh
set -eu
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
# One build per architecture, merged with lipo (works with only the Command Line Tools).
BINS=""
for ARCH in arm64 x86_64; do
  TRIPLE="$ARCH-apple-macosx13.0"
  SCRATCH=".build/$ARCH"  # separate cache per arch; a shared one breaks on rebuild
  swift build -c "$CONFIG" --triple "$TRIPLE" --scratch-path "$SCRATCH" --product Shdong
  BINS="$BINS $(swift build -c "$CONFIG" --triple "$TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)/Shdong"
done
APP=build/Shdong.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create $BINS -output "$APP/Contents/MacOS/Shdong"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --entitlements Resources/Shdong.entitlements \
  --sign "${SIGN_ID:--}" "$APP"
echo "built $APP"
