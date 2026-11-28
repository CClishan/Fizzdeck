#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FizzDeck"
BUNDLE_ID="com.a003.fizzdeck"
MIN_SYSTEM_VERSION="26.0"
VERSION="${VERSION:-0.9.3}"
BUILD_NUM="${BUILD_NUM:-26}"
CONFIG="release"
SKIP_FINDER_LAYOUT=0
OUTPUT_DMG=""
SIGN_IDENTITY=""
NOTARIZE=0
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

need_value() {
  if [[ $# -lt 2 ]]; then
    echo "ERROR: $1 requires a value." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      need_value "$@"
      OUTPUT_DMG="$2"
      shift 2
      ;;
    --version)
      need_value "$@"
      VERSION="$2"
      shift 2
      ;;
    --build-num)
      need_value "$@"
      BUILD_NUM="$2"
      shift 2
      ;;
    --sign-identity)
      need_value "$@"
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --notarize)
      NOTARIZE=1
      shift
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
      cat <<'HELP'
usage: package_dmg.sh [options]

Options:
  --output <path>          Custom DMG output path
  --version <ver>          App version (default: 0.9.3, env: VERSION)
  --build-num <num>        Bundle build number (default: 26, env: BUILD_NUM)
  --sign-identity <id>     Developer ID Application identity
                           (or set DEVELOPER_ID_APP)
  --notarize               Submit the signed DMG with notarytool and staple it
                           (requires DEVELOPER_ID_APP/--sign-identity and NOTARY_PROFILE)
  --debug                  Build the debug configuration
  --skip-finder-layout     Skip the Finder .DS_Store layout pass
  -h, --help               Show this help

Without --sign-identity or DEVELOPER_ID_APP, the script keeps the default
ad-hoc signature and verifies it with codesign --verify --deep --strict.
HELP
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="${DEVELOPER_ID_APP:-}"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "ERROR: --notarize requires --sign-identity or DEVELOPER_ID_APP." >&2
    exit 2
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "ERROR: --notarize requires the NOTARY_PROFILE environment variable." >&2
    exit 2
  fi
fi

if [[ -z "$OUTPUT_DMG" ]]; then
  mkdir -p "$DIST_DIR"
  OUTPUT_DMG="$DIST_DIR/$APP_NAME-$VERSION-arm64.dmg"
else
  mkdir -p "$(dirname "$OUTPUT_DMG")"
fi
rm -f "$OUTPUT_DMG.sha256"

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
cp -R "$ROOT_DIR/Resources/Fonts" "$APP_RESOURCES/Fonts"
cp -R "$ROOT_DIR/Resources/en.lproj" "$ROOT_DIR/Resources/zh-Hans.lproj" "$APP_RESOURCES/"
"$ROOT_DIR/script/bundle_intents.sh" "$APP_RESOURCES"

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
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
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

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing $APP_NAME.app with Developer ID (Hardened Runtime)..."
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$STAGE_APP"
  codesign --verify --deep --strict "$STAGE_APP"
else
  echo "Signing $APP_NAME.app (ad-hoc)..."
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$STAGE_APP"
  codesign --verify --deep --strict "$STAGE_APP"
fi

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
  if [[ -z "$MOUNT_POINT" ]]; then
    echo "ERROR: Failed to mount writable DMG for layout" >&2
    exit 1
  fi
  DISK_NAME="$(basename "$MOUNT_POINT")"
  echo "Writing headless DMG layout (.DS_Store) on $DISK_NAME..."
  chflags hidden "$MOUNT_POINT/.background" "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true

  UV_BIN=""
  if command -v uv >/dev/null 2>&1; then
    UV_BIN="$(command -v uv)"
  elif [[ -x "$HOME/.local/bin/uv" ]]; then
    UV_BIN="$HOME/.local/bin/uv"
  fi

  if [[ -n "$UV_BIN" ]]; then
    "$UV_BIN" run --quiet --with ds_store --with mac_alias python3 "$SCRIPT_DIR/write_dmg_dsstore.py" "$MOUNT_POINT" "$APP_NAME"
  else
    python3 "$SCRIPT_DIR/write_dmg_dsstore.py" "$MOUNT_POINT" "$APP_NAME"
  fi

  if [[ ! -s "$MOUNT_POINT/.DS_Store" ]]; then
    echo "ERROR: .DS_Store was not generated or is empty at $MOUNT_POINT/.DS_Store" >&2
    exit 1
  fi

  sync
  sleep 0.5
  hdiutil detach "$MOUNT_POINT" -quiet
  MOUNT_POINT=""
fi

echo "Compressing final UDZO DMG..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$OUTPUT_DMG" >/dev/null
hdiutil verify "$OUTPUT_DMG" >/dev/null

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing final DMG with Developer ID..."
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
  codesign --verify --verbose=2 "$OUTPUT_DMG"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "Submitting DMG for notarization (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling notarization ticket..."
  xcrun stapler staple "$OUTPUT_DMG"
  xcrun stapler validate "$OUTPUT_DMG"
  spctl -a -vvv -t open --context context:primary-signature "$OUTPUT_DMG"
fi

echo "DMG ready: $OUTPUT_DMG"
(
  cd "$(dirname "$OUTPUT_DMG")"
  shasum -a 256 "$(basename "$OUTPUT_DMG")" > "$(basename "$OUTPUT_DMG").sha256"
)
cat "$OUTPUT_DMG.sha256"
