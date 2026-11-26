#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FizzDeck"
BUNDLE_ID="com.a003.fizzdeck"
MIN_SYSTEM_VERSION="26.0"
VERSION="0.3.0"
BUILD_NUM="6"
CONFIG="release"
SKIP_FINDER_LAYOUT=0
OUTPUT_DMG=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DMG="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-num)
      BUILD_NUM="$2"
      shift 2
      ;;
    --debug)
      CONFIG="debug"
      shift
      ;;
    --skip-finder-layout)
      SKIP_FINDER_LAYOUT=1
      shift
      ;;
    -h|--help)
      echo "usage: $0 [--output <path>] [--version <ver>] [--build-num <num>] [--debug] [--skip-finder-layout]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUTPUT_DMG" ]]; then
  mkdir -p "$DIST_DIR"
  OUTPUT_DMG="$DIST_DIR/$APP_NAME-$VERSION-arm64.dmg"
else
  mkdir -p "$(dirname "$OUTPUT_DMG")"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fizzdeck-dmg.XXXXXX")"
STAGE_APP="$WORK_DIR/$APP_NAME.app"
DMG_ROOT="$WORK_DIR/dmg-root"
BG_TMP="$WORK_DIR/bg"
RW_DMG="$WORK_DIR/$APP_NAME-rw.dmg"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mount | grep -q "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" -quiet -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Building $APP_NAME ($CONFIG)..."
SWIFT_FLAGS=(--package-path "$ROOT_DIR" -c "$CONFIG")
if [[ -n "${SWIFT_SCRATCH_PATH:-}" ]]; then
  SWIFT_FLAGS+=(--scratch-path "$SWIFT_SCRATCH_PATH")
fi
if [[ "${SWIFT_DISABLE_SANDBOX:-0}" == "1" ]]; then
  SWIFT_FLAGS+=(--disable-sandbox)
fi

swift build "${SWIFT_FLAGS[@]}"
BUILD_BINARY="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/$APP_NAME"

APP_CONTENTS="$STAGE_APP/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"
cp "$ROOT_DIR/Resources/FizzDeck_logo.png" "$APP_RESOURCES/FizzDeck_logo.png"
cp "$ROOT_DIR/Resources/FizzDeck_logo_light.svg" "$APP_RESOURCES/FizzDeck_logo_light.svg"
cp "$ROOT_DIR/Resources/FizzDeck_logo_dark.svg" "$APP_RESOURCES/FizzDeck_logo_dark.svg"
cp "$ROOT_DIR/Resources/FizzDeck.icns" "$APP_RESOURCES/FizzDeck.icns"
cp -R "$ROOT_DIR/Resources/Icons" "$APP_RESOURCES/Icons"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
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
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUM</string>
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

echo "Signing $APP_NAME.app (ad-hoc)..."
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"

echo "Rendering Retina DMG background..."
swift "$SCRIPT_DIR/render_dmg_bg.swift" "$BG_TMP"

mkdir -p "$DMG_ROOT/.background"
cp -R "$STAGE_APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$BG_TMP/background.tiff" "$DMG_ROOT/.background/background.tiff"
cp "$ROOT_DIR/Resources/FizzDeck.icns" "$DMG_ROOT/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$DMG_ROOT" || true
fi

echo "Creating writable DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null

if [[ "$SKIP_FINDER_LAYOUT" -eq 0 ]]; then
  MOUNT_POINT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/\/Volumes\// { idx = index($0, "/Volumes/"); print substr($0, idx); exit }')"
  if [[ -n "$MOUNT_POINT" ]]; then
    DISK_NAME="$(basename "$MOUNT_POINT")"
    echo "Configuring Finder layout on $DISK_NAME..."
    osascript <<APPLESCRIPT || echo "Warning: Finder AppleScript layout skipped (no Automation permission)." >&2
tell application "Finder"
  tell disk "$DISK_NAME"
    open
    set current view of container window of it to icon view
    set toolbar visible of container window of it to false
    set statusbar visible of container window of it to false
    set the bounds of container window of it to {120, 120, 780, 540}
    set viewOptions to the icon view options of container window of it
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 108
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of it to {180, 196}
    set position of item "Applications" of it to {480, 196}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT
    sync
    hdiutil detach "$MOUNT_POINT" -quiet
    MOUNT_POINT=""
  fi
fi

echo "Compressing final UDZO DMG..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$OUTPUT_DMG" >/dev/null
hdiutil verify "$OUTPUT_DMG" >/dev/null
echo "DMG ready: $OUTPUT_DMG"
shasum -a 256 "$OUTPUT_DMG"
