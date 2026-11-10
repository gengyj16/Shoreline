#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
WORK_DIR="$(mktemp -d "$PWD/.build/appicon.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
OUTPUT_DIR="${1:-$PWD/Resources}"
mkdir -p "$OUTPUT_DIR"
xcrun actool Resources/AppIcon/AppIcon.icon --compile "$WORK_DIR" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target 13.0 \
  --output-partial-info-plist "$WORK_DIR/icon-info.plist" --target-device mac \
  --development-region zh_CN > "$WORK_DIR/compile.log" 2>&1 || {
    cat "$WORK_DIR/compile.log" >&2
    exit 1
  }
cp "$WORK_DIR/AppIcon.icns" "$OUTPUT_DIR/"
if [[ $# -gt 0 ]]; then
  cp "$WORK_DIR/Assets.car" "$OUTPUT_DIR/"
fi
printf 'Built app icon in %s\n' "$OUTPUT_DIR"
