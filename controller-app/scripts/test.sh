#!/bin/sh
# Runs the unit tests. With full Xcode, `swift test` works directly. With only the Command Line
# Tools, SwiftPM's test helper silently runs zero swift-testing tests, so build a small runner
# by hand instead.
set -eu
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools
DEV=$CLT/Library/Developer
if [ "$(xcode-select -p)" != "$CLT" ]; then
  exec swift test "$@"
fi

OUT=.build/clt-tests
mkdir -p "$OUT"
printf 'import Testing\n@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }\n' \
  > "$OUT/Runner.swift"
swiftc -parse-as-library -module-name ShdongCore -emit-library -enable-testing \
  -emit-module -emit-module-path "$OUT/ShdongCore.swiftmodule" \
  -o "$OUT/libShdongCore.dylib" Sources/ShdongCore/*.swift
swiftc -parse-as-library -F "$DEV/Frameworks" -plugin-path "$CLT/usr/lib/swift/host/plugins/testing" \
  -I "$OUT" -L "$OUT" -lShdongCore \
  -Xlinker -rpath -Xlinker "$DEV/Frameworks" -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
  -Xlinker -rpath -Xlinker "$PWD/$OUT" \
  Tests/ShdongCoreTests/*.swift "$OUT/Runner.swift" -o "$OUT/runner" 2>&1 | grep -v "ld: warning" || true
"$OUT/runner" "$@"
