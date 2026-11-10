#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
OVERWRITE="${OVERWRITE:-0}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\n错误 — %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'HELP'
Shoreline Universal DMG 发布流程

用法
  ./scripts/release.sh [version] [build]
  ./scripts/release.sh --check

默认从 Resources/Info.plist 读取版本号与构建号。
App 和 DMG 均使用 ad-hoc 签名。
--check 执行本地工具预检。

可选环境变量
  DIST_DIR=/path/to/output
  OVERWRITE=1
HELP
}

check_environment() {
  for command in xcrun codesign hdiutil shasum rsync; do
    command -v "$command" >/dev/null 2>&1 || fail "缺少命令 $command"
  done
  [[ -x /usr/libexec/PlistBuddy ]] || fail "缺少 PlistBuddy"
  xcrun --find swiftc >/dev/null
  xcrun --find actool >/dev/null
  xcrun --find lipo >/dev/null
  log "本地工具预检通过"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --check) [[ $# -eq 1 ]] || fail "--check 单独使用"; check_environment; exit 0 ;;
esac
[[ $# -le 2 ]] || fail "参数过多，使用 --help 查看用法"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
BUILD_NUMBER="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "版本号需要一至三段数字"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "构建号需要整数"
check_environment

mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"
FINAL_NAME="Shoreline-$VERSION-universal.dmg"
FINAL_DMG="$DIST_DIR/$FINAL_NAME"
FINAL_SHA="$FINAL_DMG.sha256"
if [[ -e "$FINAL_DMG" || -e "$FINAL_SHA" ]]; then
  [[ "$OVERWRITE" == "1" ]] || fail "同版本产物已存在，覆盖时设置 OVERWRITE=1"
fi

LOCK_DIR="$DIST_DIR/.Shoreline-$VERSION.release-lock"
mkdir "$LOCK_DIR" 2>/dev/null || fail "同版本发布任务已运行，锁目录为 $LOCK_DIR"
WORK_DIR=""
cleanup() {
  local result=$?
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if [[ -n "$WORK_DIR" ]]; then
    if [[ "$result" -eq 0 ]]; then
      rm -rf "$WORK_DIR"
    else
      printf '\n发布中间产物保存在 %s\n' "$WORK_DIR" >&2
    fi
  fi
}
trap cleanup EXIT
WORK_DIR="$(mktemp -d "$DIST_DIR/.release.XXXXXX")"

log "构建 Universal App $VERSION ($BUILD_NUMBER)"
IMAGE_ROOT="$WORK_DIR/image"
mkdir "$IMAGE_ROOT"
APP_PATH="$IMAGE_ROOT/Shoreline.app"
APP_OUTPUT="$APP_PATH" APP_VERSION="$VERSION" APP_BUILD="$BUILD_NUMBER" ./scripts/build.sh
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
printf '%s\n' "$DETAILS" | grep -Fx 'Signature=adhoc' >/dev/null || fail "App 必须使用 ad-hoc 签名"
printf '%s\n' "$DETAILS" | grep -Fx 'TeamIdentifier=not set' >/dev/null || fail "App 不应包含开发者团队身份"
xcrun lipo "$APP_PATH/Contents/MacOS/Shoreline" -verify_arch arm64
xcrun lipo "$APP_PATH/Contents/MacOS/Shoreline" -verify_arch x86_64

log "创建 ad-hoc 签名 DMG"
ln -s /Applications "$IMAGE_ROOT/Applications"
cp docs/INSTALL.md "$IMAGE_ROOT/INSTALL.md"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$IMAGE_ROOT/"
WORK_DMG="$WORK_DIR/$FINAL_NAME"
hdiutil create -volname Shoreline -srcfolder "$IMAGE_ROOT" -format UDZO "$WORK_DMG"
codesign --force --timestamp=none --sign - "$WORK_DMG"
codesign --verify --verbose=2 "$WORK_DMG"
hdiutil verify "$WORK_DMG"

HASH="$(shasum -a 256 "$WORK_DMG")"
printf '%s  %s\n' "${HASH%% *}" "$FINAL_NAME" > "$WORK_DIR/checksum.sha256"
mv -f "$WORK_DMG" "$FINAL_DMG"
mv -f "$WORK_DIR/checksum.sha256" "$FINAL_SHA"
log "打包完成"
printf 'DMG %s\nSHA-256 %s\n' "$FINAL_DMG" "$FINAL_SHA"
cat "$FINAL_SHA"
