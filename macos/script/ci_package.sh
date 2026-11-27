#!/usr/bin/env bash
# Tag builds on ephemeral GitHub-hosted macOS runners only.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || exit 2
script_dir=$(cd "$(dirname "$0")" && pwd)
args=(--skip-finder-layout)
if [[ -n "${DEVELOPER_ID_APP:-}${CERTIFICATE_P12_BASE64:-}${CERTIFICATE_PASSWORD:-}${NOTARY_KEY_BASE64:-}${NOTARY_KEY_ID:-}${NOTARY_ISSUER_ID:-}" ]]; then
  : "${DEVELOPER_ID_APP:?}" "${CERTIFICATE_P12_BASE64:?}" "${CERTIFICATE_PASSWORD:?}" "${NOTARY_KEY_BASE64:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"
  umask 077
  signing_dir=$(mktemp -d "$RUNNER_TEMP/fizz-signing.XXXXXX")
  keychain="$signing_dir/build.keychain-db"
  trap 'security delete-keychain "$keychain" >/dev/null 2>&1 || true; rm -rf "$signing_dir"' EXIT
  unlock=$(openssl rand -hex 24)
  security create-keychain -p "$unlock" "$keychain"
  security unlock-keychain -p "$unlock" "$keychain"
  security set-keychain-settings -lut 3600 "$keychain"
  security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
  printf %s "$CERTIFICATE_P12_BASE64" | base64 -D > "$signing_dir/identity.p12"
  security import "$signing_dir/identity.p12" -k "$keychain" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign > /dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$unlock" "$keychain" > /dev/null
  printf %s "$NOTARY_KEY_BASE64" | base64 -D > "$signing_dir/key.p8"
  export NOTARY_PROFILE=FizzDeck-CI
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --key "$signing_dir/key.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  args+=(--notarize)
fi
"$script_dir/package_dmg.sh" "${args[@]}"
