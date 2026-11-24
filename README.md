# FizzDeck

**A local-first project dashboard for macOS.** Scan selected folders, recognize your repositories, inspect Git and disk state, resume AI coding sessions, and launch development servers from one place.

Live landing page: [koroo.top/fizzdeck](https://koroo.top/fizzdeck)

No account, no telemetry, no hosted backend. FizzDeck reads only local project metadata and keeps its state on your Mac.

[中文说明](README.zh-CN.md)

## Native first

FizzDeck ships in two forms that share the same local state:

| Surface | Description |
|---|---|
| **FizzDeck for macOS** (`macos/`) | The primary app. Pure SwiftUI, no Node.js runtime or HTTP server required. |
| **FizzDeck Web UI** | A lightweight local dashboard powered by one Node.js process and a React/Vite SPA. |

The web UI remains useful for browser-based work and destructive project cleanup. The native app is the faster day-to-day client.

## Requirements

### Native app

- macOS 26 or later
- Xcode 26 or later with a Swift 6 toolchain

### Web UI

- A recent Node.js release (Node.js 22+ recommended)

## Quick start

### Native macOS app

If this is the first Xcode build on the machine, accept the license:

```sh
sudo xcodebuild -license accept
```

Build, launch, and verify the app:

```sh
./macos/script/build_and_run.sh --verify
```

For local notification testing, use an ad-hoc signature:

```sh
./macos/script/build_and_run.sh --sign-local
```

The app bundle is written to `macos/dist/FizzDeck.app`. To work in Xcode, open `macos/Package.swift`.

On a fresh install, use **Add project folder** to select the first directory to manage.

### Local web UI

```sh
npm install
node start.mjs
```

This opens `http://127.0.0.1:4770`. Re-running `start.mjs` only opens the page if the server is already running. To use another port:

```sh
PORT=4800 node start.mjs
```

Rebuild the committed browser bundle after changing `src/`:

```sh
npm run build
```

Stop the server:

```sh
./stop.sh
```

On a fresh install, use **Scan folder** in the sidebar to discover and add projects.

## What it does

| Area | Capability |
|---|---|
| Project discovery | Scans managed folders for repositories and project markers such as `.git`, `package.json`, `pom.xml`, and `go.mod`. Skips heavy generated folders such as `node_modules`, `Library`, `dist`, and `build`. |
| Dashboard | Native overview with starred, changed, and running filters; collapsible project groups; dashboard, list, and gallery layouts. |
| Attention queue | Surfaces failing tests, behind-remote and unpushed commits, uncommitted files, and reclaimable disk. Ordered by urgency; each row opens the matching project tab and offers inline push, fast-forward pull, test rerun, or cleanup-command copy. Right-click a row to snooze or mute that project/type; silenced rules can be restored from the header. |
| Menu bar | Keeps the pending-item count visible, opens the overview or a recent project, and sends local notifications when a dev server becomes ready or a test fails. |
| Quick open | `⌘K` searches projects, branches, remote URLs, and actions with recent items, fuzzy matching, and pinned commands. Run project commands and app actions without leaving the keyboard. |
| Project actions | Open a project in Finder, Terminal, or an installed editor (Cursor, VS Code, Zed, and Xcode when a project target exists), or copy its path. `⌘⇧T` opens the current project in Terminal. |
| AI sessions | Reads local Codex and Claude Code session metadata, matches sessions to projects, and copies `codex resume` / `claude --resume` commands. |
| Git | Shows the current branch, ahead/behind state, dirty files, recent commits, and the `origin` URL. Supports opening or copying the remote, branch switching, and confirmed fetch, fast-forward pull, and push with inline results; dirty worktrees are protected. |
| Dev servers | Detects common dev scripts and ports, starts and stops project processes, waits for readiness, and opens the app in a browser. |
| Disk usage | Breaks down project size and reclaimable space across dependencies, build caches, artifacts, temporary files, and AI session history. |
| Cleanup | Provides copy-only cleanup commands. It never executes destructive cleanup automatically. |
| Docs | Discovers and renders project documentation such as `README`, `PRODUCT`, `HANDOFF`, and `AGENTS`. |
| Tests | Detects `test`, `check`, `typecheck`, `mvn test`, and `go test`; streams output and duration. |
| Organization | Stars, color tags, notes, display aliases, and grouped technology badges. |
| Safe removal | The web UI supports remove-from-dashboard, move-to-Trash, and permanent deletion with backups and confirmation. |

## Local data and privacy

FizzDeck does not upload project data or call a FizzDeck-hosted service. Development commands started by FizzDeck may make their own network requests.

The shared data directory is `~/.repodeck`. The path is kept for compatibility with existing installations.

```text
~/.repodeck/
├── roots.json        # managed folders and display aliases
├── state.json        # stars, tags, notes, and UI state
├── roots-cache.json  # scan cache
└── logs/             # dev server logs
```

### Web security boundary

- The server listens only on `127.0.0.1`.
- Non-local origins are rejected.
- Start/stop actions are restricted to managed roots.
- Cleanup commands are copy-only.
- Source files are not read into the dashboard.
- Permanent deletion is blocked for shallow paths, blocked while tests are running, backed up to `~/.repodeck/trash`, and requires typing the directory name.

### Native app boundary

The native app is intentionally **not sandboxed**. It needs access to arbitrary user-selected project folders and must be able to run project scripts. Treat it as a local developer tool: only add folders you trust and review commands before running them.

## Project structure

```text
macos/                  Native SwiftUI app
server.mjs              Scanner, Git, disk usage, sessions, process control, HTTP API
src/                    Web UI source
src/components/ui/      Inline coss UI components
public/                 Vite build output served by server.mjs
start.mjs               Web UI launcher
stop.sh                 Web UI stopper
scan-clean.mjs          CLI disk-usage report
```

## Current limitations

- The native app requires macOS 26+. It is built from source and is not signed or notarized yet.
- The native app focuses on inspection and daily project actions. Destructive project removal is currently handled by the web UI.
- The native theme is intentionally light-only.
- There are no background file watchers yet.
- Local notifications require system permission. The `--sign-local` build uses an ad-hoc signature, which is enough to register with Notification Center for local testing; distribution still needs a Developer ID signature and notarization.
- AI session integration currently covers Codex and Claude Code.
- Port detection is heuristic; unusual development setups may need a mapping in `server.mjs`.
- Initial scans run `du`-style size checks and take roughly a few seconds per large folder. Later loads use the scan cache until a rescan.

## Status

FizzDeck is a personal, source-first macOS tool. The native app and web UI share one data directory, so switching between them does not require an export or migration step.
