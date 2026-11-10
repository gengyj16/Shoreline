#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
# UI tests launch the same bundle ID from DerivedData. Close the running local copy first.
xcrun swift -e 'import AppKit; for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.shoreline.wallpaper") { app.terminate() }'
RESULT="$PWD/.build/NativeTests-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild test -project Shoreline.xcodeproj -scheme Shoreline \
  -destination 'platform=macOS' -derivedDataPath "$PWD/.build/Xcode" \
  -resultBundlePath "$RESULT" -parallel-testing-enabled NO "$@"
xcrun xcresulttool get test-results summary --path "$RESULT" --compact | \
  python3 -c 'import json,sys; result=json.load(sys.stdin); print("Passed", result["passedTests"], "Skipped", result["skippedTests"], "Failed", result["failedTests"]); sys.exit(0 if result["totalTestCount"] > 0 else 1)'
printf '\nTest report %s\n' "$RESULT"
