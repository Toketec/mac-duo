#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/performance
xcrun swiftc -O -swift-version 5 Sources/MacDuo/FoldState.swift Sources/MacDuo/FoldRenderer.swift Sources/MacDuo/Overlay.swift Tests/Performance/main.swift -o build/performance/check -framework AppKit -framework MetalKit -framework MetalPerformanceShaders
./build/performance/check | tee build/performance/result.json
