#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/Mac Duo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
  Sources/MacDuo/*.swift -o "$APP/Contents/MacOS/MacDuo" \
  -framework AppKit -framework IOKit -framework MetalKit -framework MetalPerformanceShaders -framework ScreenCaptureKit -framework Carbon
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fold.metal "$APP/Contents/Resources/Fold.metal"
codesign --force --sign - --identifier local.macduo.app "$APP"
print -r -- "$APP"
