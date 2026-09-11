#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcrun swiftc Sources/MacDuo/FoldState.swift Tests/main.swift -o build/state-tests
./build/state-tests
'build/Mac Duo.app/Contents/MacOS/MacDuo' --diagnose
'build/Mac Duo.app/Contents/MacOS/MacDuo' --render-previews build/previews
codesign --verify --strict 'build/Mac Duo.app'
