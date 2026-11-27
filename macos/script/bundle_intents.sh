#!/usr/bin/env bash
# SwiftPM produces an executable, not an application bundle. Extract the App
# Intents metadata into Contents/Resources before the bundle is signed.
set -euo pipefail
resources=${1:?Contents/Resources required}
root=$(cd "$(dirname "$0")/.." && pwd)
source_file="$root/Sources/FizzDeck/App/ProjectIntents.swift"
work=$(mktemp -d "${TMPDIR:-/tmp}/fizz-intents.XXXXXX")
trap 'rm -rf "$work"' EXIT
sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc=$(xcrun --find swiftc)
toolchain=$(cd "$(dirname "$swiftc")/../.." && pwd)
triple="$(uname -m)-apple-macosx26.0"
# This also works with the native SwiftPM driver (which may not materialize
# Xcode's .swiftconstvalues). Only the intents file is typechecked as primary.
find "$root/Sources/FizzDeck" -name '*.swift' > "$work/other-sources"
printf '%s\n' "$source_file" > "$work/intent-source"
printf '%s\n' "$work/intents.swiftconstvalues" > "$work/const-list"
# Only gather the conformances this module exposes; Xcode 26 and 27 ship
# different default protocol-list files.
printf '%s\n' '["AppIntent","AppEntity","EntityQuery","EntityStringQuery","AppShortcutsProvider"]' > "$work/protocols"
"$swiftc" -frontend -typecheck -module-name FizzDeck -target "$triple" -sdk "$sdk" -swift-version 5 \
  -plugin-path "$toolchain/usr/lib/swift/host/plugins" \
  -primary-file "$source_file" -filelist "$work/other-sources" \
  -const-gather-protocols-file "$work/protocols" \
  -emit-const-values-path "$work/intents.swiftconstvalues"
xcrun appintentsmetadataprocessor --module-name FizzDeck --toolchain-dir "$toolchain" --sdk-root "$sdk" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" --platform-family macOS \
  --deployment-target 26.0 --target-triple "$triple" --source-file-list "$work/intent-source" \
  --swift-const-vals-list "$work/const-list" --output "$resources" --force
# A successful processor exit with an empty action catalog is not a working shortcut.
/usr/bin/python3 - "$resources/Metadata.appintents/extract.actionsdata" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    catalog = json.load(f)
actions = catalog['actions']
required = {'OpenFizzProjectIntent', 'CopyFizzHandoffIntent', 'FocusedFizzDoctorIntent'}
if required.difference(actions):
    sys.exit('Missing FizzDeck App Intents: ' + ', '.join(sorted(required.difference(actions))))
if len(catalog.get('autoShortcuts', [])) < len(required) or not catalog.get('entities') or not catalog.get('queries'):
    sys.exit('Shortcut phrases, project entity or entity query missing from bundle')
PY
