# FizzDeck for macOS

The native, SwiftUI-first client for FizzDeck.

Download: [FizzDeck 0.5.2 for macOS](https://github.com/CClishan/Fizzdeck/releases/latest) — Apple Silicon, macOS 26+, ad-hoc signed (not notarized).

FizzDeck reads and writes the same local state as the web UI, but runs without Node.js and without a local HTTP server.

[Chinese README](../README.zh-CN.md)

## Requirements

- macOS 26 or later
- Xcode 26 or later with a Swift 6 toolchain

## Build and run

Accept the Xcode license once if needed:

```sh
sudo xcodebuild -license accept
```

Build, launch, and verify:

```sh
./script/build_and_run.sh --verify
```

Run the Swift test baseline:

```sh
swift test
```

The app bundle is written to `dist/FizzDeck.app`.

Other entry points:

```sh
./script/build_and_run.sh          # build and launch
./script/build_and_run.sh --sign-local  # ad-hoc sign, then launch for local notification testing
./script/build_and_run.sh --logs   # launch and stream app logs
./script/build_and_run.sh --debug  # launch the binary under LLDB
```

`--sign-local` is an ad-hoc signature for local testing only. It is not a distribution signature and is never applied by the default `run` or `--verify` modes.

To work in Xcode, open `Package.swift`.

## What is implemented

- Native overview with starred, changed, and running filters
- Attention queue for failing tests, unpushed or behind commits, uncommitted files, and reclaimable disk, with inline actions plus per-project snooze, mute, and restore
- Menu bar pending count with quick access to the overview and recent projects
- Local notifications when a dev server becomes ready or a test fails
- `⌘K` command palette for projects, branches, and actions
- Finder, preferred terminal, and editor quick actions for Cursor, VS Code, Zed, Antigravity, JetBrains IDEs, and top-level or nested Xcode targets, including `⌘⇧T` for the terminal
- Terminal preference for Terminal, iTerm2, Ghostty, or Warp, plus automatic or Codex Desktop resume routing
- Collapsible project groups with automatic path-based classification plus manual group assignment, new-group creation, and restore-to-automatic
- Search across projects, paths, stacks, and branches
- Dashboard and list layouts, with a half-width attention card beside four summary cards
- Group filtering plus multi-select batch rescan and cleanup-command copy across both layouts
- Native Liquid Glass folder manager with nested project discovery, scan-depth control, duplicate protection, and managed roots
- Disk usage and cleanup suggestions
- Git status, ahead/behind state, dirty files, and recent commits
- Branch switching, confirmed fetch, fast-forward pull, and push with inline results
- Project documentation discovery and reading
- Codex, Claude Code, and Grok session list with tool filters, last user request, resume in the preferred terminal or Codex Desktop, and confirmed ending of dedicated CLI processes
- Start/stop and test controls in a floating Liquid Glass action dock
- Port readiness checks and log access
- Background test execution with live output
- Stars, color tags, and notes
- Light and low-saturation charcoal dark appearances with native glass controls and a floating Liquid Glass action dock

## Shared state

FizzDeck keeps its state in `~/.repodeck`, a path retained for backward compatibility with existing installations.

| Path | Purpose |
|---|---|
| `roots.json` | Managed folders and display aliases |
| `state.json` | Stars, tags, groups, notes, and UI state |
| `roots-cache.json` | Scan cache |
| `logs/` | Development server logs |
| `launchers/` | Short-lived resume scripts, cleaned after 24 hours |

The native app and web UI can use the same state without an export step.

## Scope and safety

The app is a local developer tool. It is **not sandboxed**, because it needs access to user-selected folders and must run project scripts. Only add trusted directories.

FizzDeck itself does not upload project data. Commands launched for a project may make their own network requests.

Local notifications require system permission. The `--sign-local` build uses an ad-hoc signature, which is enough to register with Notification Center for local testing; distribution still needs a Developer ID signature and notarization.

Project removal only accepts managed roots, refuses shallow or protected paths, is blocked while a dev server or test is running, and requires typing the directory name. Move to Trash uses the system Trash; permanent deletion first copies the project to `~/.repodeck/trash`.

## Project layout

```text
Sources/FizzDeck/App         App entry point
Sources/FizzDeck/Models      Data models and dashboard filters
Sources/FizzDeck/Services    Scanner, Git, docs, sessions, shell, and process actions
Sources/FizzDeck/Stores      Observable app state
Sources/FizzDeck/Views       SwiftUI screens and components
Sources/FizzDeck/Support     Theme, paths, formatting, and system helpers
Resources/                   Logo and app icon
script/build_and_run.sh      Build and launch entry point
```

## Not implemented yet

- Warp auto-running resume commands; FizzDeck opens the project directory and offers the command to copy
- Ending Codex Desktop sessions; FizzDeck never terminates the shared app-server
- Code signing and notarization
