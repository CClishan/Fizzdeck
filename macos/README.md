# FizzDeck for macOS

The native, SwiftUI-first client for FizzDeck.

Download: [Latest public release](https://github.com/CClishan/Fizzdeck/releases/latest) — Apple Silicon, macOS 26+. Public DMGs use ad-hoc signing unless the release notes explicitly name a Developer ID notarized build.

FizzDeck reads and writes the same local state as the web UI, but runs without Node.js and without a local HTTP server.

[Chinese README](../README.zh-CN.md)

**v0.8.0 (Build 16).** Doctor rechecks a focused project when its dependency or environment files change. See which process owns a development port, run a build or test on demand, and review 14 or 30 days of estimated AI costs and commits.

**Local release candidate: [v0.9.0 (Build 23)](../docs/releases/v0.9.0.md).** The app ships four Obel Mono weights for Latin text and digits, with native Chinese typography. Open Recap from Workbench or Conversations to compare 7d, 30d, 90d, or all indexed history. Agent time and test outcomes appear only when the source log records enough evidence. Free or unpriced sessions are counted separately. Copy Markdown or an anonymous light/dark PNG; recap polish is off by default and sends only aggregate figures per approval.

The download link points to the latest public DMG. System Shortcuts require a build signed with an Apple Team ID; the default ad-hoc DMG has none. Project opening, handoff cards and health checks can also be used in the app. See [verification details](../docs/SYSTEM_INTEGRATION.md).

## Requirements

- Apple Silicon
- macOS 26 or later
- Xcode 26 or later with a Swift 6 toolchain

## What is implemented

### Remember

- Plain-language mode, enabled by default, with a professional Git terminology switch
- A cross-project conversation timeline with first request, touched files, status, and cost
- Chinese-capable local search over conversations, including short-query fallback, from the Conversations workspace and `⌘K`
- Clipboard-only handoff cards with secret redaction

### Rewind

- A quiet pre-conversation mark stored as temporary Git objects without moving branches or writing commits
- Conversation diff review, per-file or whole-worktree restore, and undo feedback
- New files created after a conversation are kept by default during restore
- Inline “save a version” with rule-based or optional AI commit messages
- Pre-push checks for unignored `.env` files and tracked-file secret patterns

### Run

- Sidebar Doctor for focused projects: run state, dependencies, ports, secrets, and version protection
- Idle-project cleanup that defaults to moving reclaimable directories to the system Trash
- Inline local-environment and Git-identity checks
- Run-tab preflight with install, port-conflict, `.env`, and version-protection actions
- Log-error explanations and a copyable agent-help prompt

### Optional AI summaries

- Off by default
- Agent CLI without an API key, OpenAI-compatible API with the key stored in macOS Keychain, or a local model
- Minimal redacted fields only, isolated agent working directory, and silent fallback to rule-based summaries

### Project detail

Four tabs, shared by plain-language and professional modes:

| Tab | Contents |
|---|---|
| **Progress** | “Where did I leave off?”, conversation timeline and marks, touched files, restore entry |
| **Run** | Doctor issues, services, scripts, tests, logs, error help |
| **Version** | Branch, changes, diffs, staging, inline version save, push, advanced Git |
| **Project info** | Intro, note, stack, disk usage, cleanup entry, compact document list with preview |

## Build and run

Accept the Xcode license once if needed:

```sh
sudo xcodebuild -license accept
```

Build, launch, and verify:

```sh
./script/build_and_run.sh --verify
```

The local build defaults to `0.9.0`, Build `23`. Both values can be overridden:

```sh
VERSION=0.9.0 BUILD_NUM=23 ./script/build_and_run.sh --build-only
```

Run the Swift test baseline:

```sh
swift test
```

The app bundle is written to `dist/FizzDeck.app`.

Other entry points:

```sh
./script/build_and_run.sh              # build and launch
./script/build_and_run.sh --sign-local # ad-hoc sign, then launch for local notification testing
./script/build_and_run.sh --logs       # launch and stream app logs
./script/build_and_run.sh --debug      # launch the binary under LLDB
```

To work in Xcode, open `Package.swift`.

## Package a DMG

Default ad-hoc package:

```sh
./script/package_dmg.sh
```

Output:

```text
dist/FizzDeck-0.9.0-arm64.dmg
dist/FizzDeck-0.9.0-arm64.dmg.sha256
```

The checksum file is standard `shasum -a 256` output containing only the DMG filename. Custom version, build number, and output path are available:

```sh
./script/package_dmg.sh \
  --version 0.8.0 \
  --build-num 16 \
  --output dist/FizzDeck-0.8.0-arm64.dmg
```

Run `./script/package_dmg.sh --help` for all options.

## Signing and notarization

### Default: ad-hoc

Without a Developer ID identity, the script keeps the existing behavior:

- ad-hoc signs the staged app
- runs `codesign --verify --deep --strict`
- packages and verifies the DMG
- writes the `.sha256` file

No signing or notarization error is raised in this path.

### Developer ID

Pass the identity with `--sign-identity` or provide `DEVELOPER_ID_APP`:

```sh
export DEVELOPER_ID_APP="Developer ID Application: <your name> (<TEAMID>)"
./script/package_dmg.sh --sign-identity "$DEVELOPER_ID_APP"
```

When an identity is present, the staged app is signed with:

```text
--options runtime --timestamp
```

The final DMG is signed as well. Nothing is hardcoded in the repository.

### Notarization

Store notarization credentials in a Keychain profile once:

```sh
xcrun notarytool store-credentials "$NOTARY_PROFILE"
```

Follow the prompts for the Apple ID, team ID, and app-specific password. The profile name is stored in the keychain; no credentials belong in this repository.

Then package, submit, staple, and verify:

```sh
export DEVELOPER_ID_APP="Developer ID Application: <your name> (<TEAMID>)"
export NOTARY_PROFILE="<notarytool profile name>"
./script/package_dmg.sh --notarize
```

The notarized path runs:

```sh
xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"
spctl -a -vvv -t open --context context:primary-signature "$OUTPUT_DMG"
```

## Release verification

### 1. Local preflight

```sh
bash -n macos/script/build_and_run.sh
bash -n macos/script/package_dmg.sh
swift build --package-path macos --product FizzDeck
swift test --package-path macos
```

If `src/landing` changed:

```sh
npm run build
```

### 2. Build and inspect the DMG

```sh
./macos/script/package_dmg.sh
hdiutil verify macos/dist/FizzDeck-0.9.0-arm64.dmg
mkdir -p /tmp/fizzdeck-verify
hdiutil attach -nobrowse -readonly -mountpoint /tmp/fizzdeck-verify macos/dist/FizzDeck-0.9.0-arm64.dmg
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /tmp/fizzdeck-verify/FizzDeck.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /tmp/fizzdeck-verify/FizzDeck.app/Contents/Info.plist
codesign --verify --deep --strict /tmp/fizzdeck-verify/FizzDeck.app
hdiutil detach /tmp/fizzdeck-verify
cd macos/dist && shasum -a 256 -c FizzDeck-0.9.0-arm64.dmg.sha256
```

Expected values: version `0.9.0`, build `23`.

### 3. In-app update: v0.5.3 or v0.7.4 → v0.8.0

Run this once from each old version, on a Mac that can keep the existing `~/.repodeck` state:

1. Install the old app into `/Applications` and publish the new v0.8.0 DMG plus its `.sha256` to a test release or the final release.
2. Launch the old app and open **Settings → About**.
3. Click check for updates and confirm the app finds `v0.8.0`.
4. Start the download and watch the progress state; confirm it fetches both the DMG and checksum.
5. Let FizzDeck verify SHA-256, mount the DMG, verify the bundle identifier and code signature, replace the app atomically, and relaunch.
6. Confirm the relaunched app reads `0.8.0` and Build `16`:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/FizzDeck.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/FizzDeck.app/Contents/Info.plist
```

7. Confirm projects, stars, notes, and the previous update setting survived the update.
8. Open the app once more from Finder and confirm it launches without a blank window or repeated update prompt.
9. Repeat the same steps starting from the other old version (`v0.5.3` and `v0.7.4`).

Do not claim the update is release-ready if either starting version fails, or if the checksum, bundle ID, or version check is skipped.

### 4. Notarized release verification

```sh
./macos/script/package_dmg.sh --notarize
xcrun stapler validate macos/dist/FizzDeck-0.8.0-arm64.dmg
spctl -a -vvv -t open --context context:primary-signature macos/dist/FizzDeck-0.8.0-arm64.dmg
```

For the installed notarized app:

```sh
spctl -a -vvv -t exec /Applications/FizzDeck.app
codesign --display --verbose=4 /Applications/FizzDeck.app
```

### 5. Release assets

Upload both:

```text
FizzDeck-0.8.0-arm64.dmg
FizzDeck-0.8.0-arm64.dmg.sha256
```

After publishing, verify the release tag, filenames, checksum, and in-app update once from a clean install.

## Local Agent conversation sources (Build 20)

FizzDeck reads conversations in place. Conversations from managed projects appear in the timeline, Chinese search, file history, and conversation counts.

| Tool | Source and limits |
|---|---|
| Cursor | `~/.cursor/projects/*/agent-transcripts/`; only local projects with an explicit `workspacePath` or a unique match in Cursor's `workspace.json`. Ambiguous folders and assistant-only transcripts are skipped. The existing workspace summary remains a fallback when no transcript is imported. |
| OpenCode | `~/.local/share/opencode/opencode.db`; reads the SQLite session, message, and part tables. Active WAL reads require the existing sidecars. Older JSON storage and custom data directories are outside this build. |
| Windsurf | Workspace detection remains available. FizzDeck does not import default Cascade conversation history or configure hooks. |

Cursor and OpenCode imports do not estimate cost or token usage and do not offer a resume command.

## Shared state

FizzDeck keeps its state in `~/.repodeck`, a path retained for backward compatibility with existing installations.

| Path | Purpose |
|---|---|
| `roots.json` | Managed folders and display aliases |
| `state.json` | Stars, tags, groups, notes, and UI state |
| `scan-cache.json` | Scan cache |
| `marks.json` | Conversation marks |
| `session-search.sqlite` | Cross-project FTS5 conversation index |
| `summaries/` | Optional AI summary cache |
| `logs/` | Development server logs |
| `launchers/` | Short-lived resume scripts, cleaned after 24 hours |

The native app and web UI can use the same state without an export step.

## Scope and safety

The app is a local developer tool. It is **not sandboxed**, because it needs access to user-selected folders and must run project scripts. Only add trusted directories.

FizzDeck itself does not upload project data. Commands launched for a project may make their own network requests.

Local notifications require system permission. The `--sign-local` build uses an ad-hoc signature, which is enough to register with Notification Center for local testing.

Project removal only accepts managed roots, refuses shallow or protected paths, is blocked while a dev server or test is running, and requires typing the directory name. Move to Trash uses the system Trash; permanent deletion first copies the project to `~/.repodeck/trash`.

## Project layout

```text
Sources/FizzDeck/App         App entry point
Sources/FizzDeck/Models      Data models and dashboard filters
Sources/FizzDeck/Services    Scanner, Git, docs, sessions, Doctor, summaries, and process actions
Sources/FizzDeck/Stores      Observable app state
Sources/FizzDeck/Views       SwiftUI screens and components
Sources/FizzDeck/Support     Theme, paths, formatting, copy, and system helpers
Resources/                   Logo and app icon
script/build_and_run.sh      Build and launch entry point
script/package_dmg.sh        Packaging, signing, notarization, and checksum entry point
```

See [system integration and release automation](../docs/SYSTEM_INTEGRATION.md) for the URL scheme, local Apple Development signing instructions, CI secrets, and scale benchmark. All three Shortcuts actions ran in the macOS editor with a development signature. The ad-hoc bundle was discoverable but could not execute the health action.

## Current boundaries

- Warp resume commands still need to be copied; FizzDeck opens the project directory rather than injecting a command.
- Ending Codex Desktop sessions is intentionally unsupported; FizzDeck never terminates the shared app-server.
- Developer ID signing and notarization are implemented in the packaging script, but public releases remain ad-hoc until credentials are supplied at build time.
- Conversation marks depend on temporary Git objects and normally expire after about 14 days unless pinned.

License: see [LICENSE](../LICENSE). Local use and builds are free; third-party assets keep their own terms.
