#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FizzDeck"
BUNDLE_ID="com.a003.fizzdeck"
case "$MODE" in
  run|--build-only|--sign-local|sign-local|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *) echo "usage: [VERSION=0.9.0 BUILD_NUM=23] $0 [run|--build-only|--sign-local|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
MIN_SYSTEM_VERSION="26.0"
VERSION="${VERSION:-0.9.0}"
BUILD_NUM="${BUILD_NUM:-23}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${FIZZDECK_DIST_DIR:-$ROOT_DIR/dist}"
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd -P)"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGE_DIR="$(mktemp -d "$DIST_DIR/.build-XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
APP_CONTENTS="$STAGE_DIR/$APP_NAME.app/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if ! swift build --package-path "$ROOT_DIR"; then
  echo "构建失败。如果提示 Xcode license，请先运行：sudo xcodebuild -license accept" >&2
  exit 1
fi
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/FizzDeck_logo.png" "$APP_RESOURCES/FizzDeck_logo.png"
cp "$ROOT_DIR/Resources/FizzDeck_logo_light.svg" "$APP_RESOURCES/FizzDeck_logo_light.svg"
cp "$ROOT_DIR/Resources/FizzDeck_logo_dark.svg" "$APP_RESOURCES/FizzDeck_logo_dark.svg"
cp "$ROOT_DIR/Resources/FizzDeck.icns" "$APP_RESOURCES/FizzDeck.icns"
cp -R "$ROOT_DIR/Resources/Icons" "$APP_RESOURCES/Icons"
cp -R "$ROOT_DIR/Resources/Fonts" "$APP_RESOURCES/Fonts"
"$ROOT_DIR/script/bundle_intents.sh" "$APP_RESOURCES"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>FizzDeck.icns</string>
  <key>ATSApplicationFontsPath</key>
  <string>Fonts</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUM</string>
  <key>CFBundleURLTypes</key>
  <array><dict><key>CFBundleURLName</key><string>$BUNDLE_ID.project</string><key>CFBundleURLSchemes</key><array><string>fizzdeck</string></array></dict></array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>用于在终端中启动并聚焦正在运行的 AI 会话窗口。</string>
</dict>
</plist>
PLIST

# Only replace a complete bundle. Never quit an independently installed copy.
bundle_pids() {
  ps -ax -o pid=,comm= | awk -v exe="$APP_BUNDLE/Contents/MacOS/$APP_NAME" '{p=$1; sub(/^ *[0-9]+ +/, ""); if ($0 == exe) print p}'
}
if [[ "$MODE" == "--build-only" && -n "$(bundle_pids)" ]]; then
  echo "FizzDeck is running from $APP_BUNDLE; choose another FIZZDECK_DIST_DIR." >&2
  exit 1
fi
if [[ "$MODE" != "--build-only" ]]; then
  pid=$(bundle_pids)
  if [[ -n "$pid" ]]; then
    while IFS= read -r running_pid; do kill -TERM "$running_pid" 2>/dev/null || true; done <<< "$pid"
  fi
fi
if [[ -e "$APP_BUNDLE" ]]; then mv "$APP_BUNDLE" "$STAGE_DIR/previous.app"; fi
if ! mv "$STAGE_DIR/$APP_NAME.app" "$APP_BUNDLE"; then
  [[ ! -e "$STAGE_DIR/previous.app" ]] || mv "$STAGE_DIR/previous.app" "$APP_BUNDLE"
  exit 1
fi
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

sign_local() {
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
}

case "$MODE" in
  --build-only) ;;
  run)
    open_app
    ;;
  --sign-local|sign-local)
    sign_local
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    [[ -n "$(bundle_pids)" ]]
    ;;
esac
