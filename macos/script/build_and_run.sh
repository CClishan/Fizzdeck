#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FizzDeck"
BUNDLE_ID="com.a003.fizzdeck"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if ! swift build --package-path "$ROOT_DIR"; then
  echo "构建失败。如果提示 Xcode license，请先运行：sudo xcodebuild -license accept" >&2
  exit 1
fi
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/FizzDeck_logo.png" "$APP_RESOURCES/FizzDeck_logo.png"
cp "$ROOT_DIR/Resources/FizzDeck_logo_light.svg" "$APP_RESOURCES/FizzDeck_logo_light.svg"
cp "$ROOT_DIR/Resources/FizzDeck_logo_dark.svg" "$APP_RESOURCES/FizzDeck_logo_dark.svg"
cp "$ROOT_DIR/Resources/FizzDeck.icns" "$APP_RESOURCES/FizzDeck.icns"
cp -R "$ROOT_DIR/Resources/Icons" "$APP_RESOURCES/Icons"

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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.3</string>
  <key>CFBundleVersion</key>
  <string>5</string>
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

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

sign_local() {
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
}

case "$MODE" in
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
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--sign-local|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
