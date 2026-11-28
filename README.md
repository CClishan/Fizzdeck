# FizzDeck

**A local-first macOS workbench for vibe coders.**

When AI writes your projects, three things get lost: where you left off, how to undo a bad change, and why a project that used to run no longer starts. FizzDeck brings local projects, AI conversations, and run checks into one native window—in plain language.

Live site: [koroo.top/fizzdeck](https://koroo.top/fizzdeck)

Download: [Latest public release](https://github.com/CClishan/Fizzdeck/releases/latest) — Apple Silicon, macOS 26+.

No account, no telemetry, and no FizzDeck-hosted backend. Project metadata, session indexes, and settings stay on your Mac.

[中文说明](README.zh-CN.md)

**Release candidate: [v0.9.0 (Build 23)](docs/releases/v0.9.0.md).** Manage Git worktrees, pass context with three handoff cards, and search Cursor and OpenCode conversations. The new Workbench and cross-agent recap include raster and ASCII share cards. Latin text uses bundled Obel Mono; Chinese keeps the macOS system font. The candidate is local; [v0.8.0 (Build 16)](https://github.com/CClishan/Fizzdeck/releases/tag/v0.8.0) remains the public download.

The download link points to the latest public DMG. System Shortcuts require a build signed with an Apple Team ID; the default ad-hoc DMG has none. Project opening, handoff cards and health checks can also be used in the app. See [verification details](docs/SYSTEM_INTEGRATION.md).

## Three problems, solved first

### Remember

- **Plain-language mode is on by default.** Commit, Stash, and Pull become “save a version,” “put changes aside,” and “bring down the new cloud changes”; switch back to Git terminology whenever you want.
- **A cross-project conversation timeline.** Codex, Claude, and other AI sessions are grouped by day with the first request, touched files, final status, and cost.
- **Search that works in Chinese.** A local SQLite FTS5 index covers conversations across projects, with a short-query fallback for one- or two-character searches. Results open from the search box or `⌘K`.
- **A clipboard-only handoff card.** Turn project state and recent conversations into Markdown for any agent. Nothing is written into the project, and secrets are redacted before copying.
- **Cross-agent recap.** Choose 7d, 30d, 90d, or all indexed history. Compare sessions, recorded agent time, estimated cost, and tokens; see project trends, active days and streaks, and the turns and test results each log supports. Copy Markdown or a light/dark PNG with project names hidden by default. Optional recap polish sends only aggregate figures after you approve that request.

### Rewind

- **A quiet mark before AI starts.** FizzDeck records the worktree as temporary Git objects without moving branches, writing commits, or changing what appears in `git log`.
- **See what changed and restore it.** Compare before and after, restore selected files, or return the whole worktree to the conversation start. Files created after the conversation are listed but kept by default.
- **Save a real version inline.** Turn the current changes into a normal Git commit, with a rule-based message or optional AI polish.
- **Block secrets before push.** Check whether `.env` is ignored and whether tracked files contain common secret patterns. Risky pushes stop first and are explained in plain language.

### Run

- **Doctor in the sidebar.** Focused projects are checked for run state, dependencies, ports, secrets, and version protection; each problem aims to offer a concrete next step.
- **Idle-project cleanup.** Find reclaimable dependency, cache, and build space. The default action moves it to the system Trash, where it can be recovered or regenerated.
- **Local environment and Git identity.** Check Node, Git, and agent CLI status inline, and fix a missing Git name or email without opening a terminal.
- **Preflight on the Run tab.** See blockers first. Missing dependencies, port conflicts, and missing `.env` files can be handled in place.
- **Error help from logs.** Turn an error into a plain-language explanation or a ready-to-paste agent prompt instead of reading the whole stack yourself.

### Optional AI summaries (off by default)

- Choose **Agent CLI (no key)**, **OpenAI-compatible API (key in macOS Keychain)**, or a **local model (Ollama / LM Studio)**.
- Only send the project name, file names, change counts, and a redacted one-line intent—not full conversations or source code.
- Agent CLI summaries run in an isolated working directory so FizzDeck’s own sessions do not pollute project lists.
- Timeouts, missing logins, and offline failures fall back silently to rule-based summaries.

## Four project tabs

| Tab | What it is for |
|---|---|
| **Progress** | “Where did I leave off?”, the daily conversation timeline, conversation marks, touched files, and restore actions; switch to all raw sessions when needed. |
| **Run** | Doctor issues, start/stop controls, scripts, tests, and live logs; errors can be explained or copied as an agent prompt. |
| **Version** | Branch, changes, diffs, staging, inline “save a version,” push, and branch actions; advanced Git stays on the same tab. |
| **Project info** | Intro, note, stack, disk usage, cleanup entry, and a compact list of README / AGENTS / HANDOFF docs with preview. |

## Install

### Default build: ad-hoc signature

The repository’s default package is ad-hoc signed and not Apple-notarized. On first launch:

1. Download the DMG and its `.sha256` file from the same GitHub release. In the download directory, run `shasum -a 256 -c FizzDeck-0.8.0-arm64.dmg.sha256` and check for `OK`.
2. Open the DMG, drag FizzDeck to Applications, then try opening the app.
3. If macOS blocks it and you trust the download, open **System Settings → Privacy & Security** and choose **Open Anyway** for FizzDeck.

### Build a Developer ID + notarized package

Signing identity and notarization credentials are injected with environment variables or arguments. The repository contains no certificates, Apple IDs, or app-specific passwords.

```sh
export DEVELOPER_ID_APP="Developer ID Application: <your name> (<TEAMID>)"
export NOTARY_PROFILE="<notarytool keychain profile>"
./macos/script/package_dmg.sh --notarize
```

Or pass the identity explicitly:

```sh
./macos/script/package_dmg.sh \
  --sign-identity "$DEVELOPER_ID_APP" \
  --notarize
```

`--notarize` submits the DMG with `xcrun notarytool submit --keychain-profile "$NOTARY_PROFILE" --wait`, then runs `stapler staple`, `stapler validate`, and `spctl` verification. See [macos/README.md](macos/README.md) for all options and credential setup.

## Quick start

### Build the native app

Accept the Xcode license once if needed:

```sh
sudo xcodebuild -license accept
```

Build, launch, and verify the process:

```sh
./macos/script/build_and_run.sh --verify
```

The default version is `0.9.0`, Build `23`. Override it when needed:

```sh
VERSION=0.9.0 BUILD_NUM=23 ./macos/script/build_and_run.sh --build-only
```

The app bundle is written to `macos/dist/FizzDeck.app`. To work in Xcode, open `macos/Package.swift`.

Run tests:

```sh
swift test --package-path macos
```

### Package a DMG

```sh
./macos/script/package_dmg.sh
```

The default output is `macos/dist/FizzDeck-0.9.0-arm64.dmg`, plus a matching `FizzDeck-0.9.0-arm64.dmg.sha256`. The checksum is standard `shasum -a 256` output for in-app updates and GitHub Releases.

### Local web UI

The lightweight browser companion shares `~/.repodeck` with the native app:

```sh
npm install
node start.mjs
```

This opens `http://127.0.0.1:4770`. Rebuild after changing `src/`:

```sh
npm run build
```

Stop the server:

```sh
./stop.sh
```

## Local data and privacy

FizzDeck does not upload project data or call a FizzDeck-hosted service. Development commands it starts may make their own network requests.

Shared state remains in `~/.repodeck` for compatibility:

Development builds check a focused project’s configured upstream at most once per 24 hours. This contacts its Git host without pushing or changing the working tree. Project scripts still run only on request.

```text
~/.repodeck/
├── roots.json          # managed folders and display aliases
├── state.json          # stars, tags, groups, notes, and UI state
├── scan-cache.json     # scan cache
├── marks.json          # pre-conversation marks
├── session-search.sqlite # cross-project conversation FTS5 index
├── summaries/          # optional AI summary cache
└── logs/               # dev server logs
```

The native app is intentionally not sandboxed: it needs access to user-selected folders and must run project scripts. Only add trusted folders and review commands before running them.

## Project layout

```text
macos/                  SwiftUI app, resources, scripts, and tests
server.mjs              Web UI scanning, Git, process control, and HTTP API
src/                    Web UI source
src/landing/            Public landing page source
public/                 Built browser assets served by server.mjs
start.mjs               Web UI launcher
stop.sh                 Web UI stopper
```

## Current boundaries

- The native app targets Apple Silicon and macOS 26+. Public DMGs use an ad-hoc signature unless a release explicitly provides a Developer ID notarized build.
- Conversation marks depend on Git objects and usually survive about 14 days. Pinned marks last longer; non-Git projects only get plain marks.
- Restore overwrites or deletes the tracked changes you select. Files created after a conversation are kept by default and require a separate confirmation to delete.
- Optional AI summaries are off by default. A failed provider only affects the polished summary; rules still work.
- The web UI is a lightweight companion and does not replace native menu bar, notifications, terminal preferences, or notarized distribution.

## Status

FizzDeck is a source-first personal tool. The native app is the primary client; the web UI and bilingual landing page remain supporting surfaces.

License: see [LICENSE](LICENSE). Local use and builds are free; third-party assets keep their own terms.

Bundled assets: [Obel Mono (SIL OFL 1.1)](macos/Resources/Fonts/OFL.txt) · [Kubai Icons (MIT)](macos/Resources/Icons/LICENSE).
