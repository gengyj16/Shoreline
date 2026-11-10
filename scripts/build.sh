#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
STAGING_DIR="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/Shoreline.app"
OUTPUT="${APP_OUTPUT:-$PWD/dist/Shoreline.app}"
mkdir -p "$(dirname "$OUTPUT")"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for architecture in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macos13.0" \
    -module-cache-path "$PWD/.build/ModuleCache" \
    Sources/*.swift -o "$STAGING_DIR/Shoreline-$architecture" \
    -framework Cocoa -framework SwiftUI -framework WebKit -framework ApplicationServices
done
xcrun lipo -create "$STAGING_DIR/Shoreline-arm64" "$STAGING_DIR/Shoreline-x86_64" \
  -output "$APP/Contents/MacOS/Shoreline"
xcrun lipo "$APP/Contents/MacOS/Shoreline" -verify_arch arm64
xcrun lipo "$APP/Contents/MacOS/Shoreline" -verify_arch x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
  [[ "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { printf 'Invalid APP_VERSION\n' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${APP_BUILD:-}" ]]; then
  [[ "$APP_BUILD" =~ ^[0-9]+$ ]] || { printf 'Invalid APP_BUILD\n' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP/Contents/Info.plist"
fi
./scripts/build-icon.sh "$APP/Contents/Resources"
rsync -a --delete Resources/Themes/ "$APP/Contents/Resources/Themes/"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
codesign --force --options runtime --timestamp=none --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
rsync -a --delete "$APP/" "$OUTPUT/"
codesign --verify --deep --strict --verbose=2 "$OUTPUT"
printf 'Architectures: %s\n' "$(xcrun lipo -archs "$OUTPUT/Contents/MacOS/Shoreline")"
printf '\nBuilt %s\nRun with: open "%s"\n' "$OUTPUT" "$OUTPUT"
