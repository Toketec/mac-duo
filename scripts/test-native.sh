#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/native-check
xcrun swiftc -swift-version 5 Sources/MacDuo/FoldState.swift Sources/MacDuo/FoldRenderer.swift Sources/MacDuo/Overlay.swift Tests/NativeWindow/main.swift -o build/native-check/check -framework AppKit -framework MetalKit -framework MetalPerformanceShaders
./build/native-check/check
