#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/.build/ModuleCache" \
  Sources/Settings.swift Sources/DesktopIcons.swift Sources/Diagnostics.swift Sources/Wallpaper.swift Tests/SmokeTests.swift \
  -o .build/SmokeTests -framework Cocoa -framework SwiftUI -framework WebKit -framework ApplicationServices
.build/SmokeTests "$PWD"
