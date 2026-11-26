# FizzDeck

**A local-first project dashboard for macOS.** Scan selected folders, recognize your repositories, inspect Git and disk state, resume AI coding sessions, and launch development servers from one place.

Live landing page: [koroo.top/fizzdeck](https://koroo.top/fizzdeck)

Download: [FizzDeck 0.4.0 for macOS](https://github.com/CClishan/Fizzdeck/releases/latest) — Apple Silicon, macOS 26+, ad-hoc signed (not notarized).

No account, no telemetry, no hosted backend. FizzDeck reads only local project metadata and keeps its state on your Mac.

[中文说明](README.zh-CN.md)

## Native first

FizzDeck ships in two forms that share the same local state:

| Surface | Description |
|---|---|
| **FizzDeck for macOS** (`macos/`) | The primary app. Pure SwiftUI, no Node.js runtime or HTTP server required. |
| **FizzDeck Web UI** | A lightweight local dashboard powered by one Node.js process and a React/Vite SPA. |

Both clients share local state. The native app is the faster day-to-day client, including confirmed project removal.

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

Run the Swift test baseline:

```sh
swift test --package-path macos
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
| Project discovery | A native folder manager lists existing folders, scans a selected parent directory for nested projects, and recognizes `.git`, `package.json`, `CLAUDE.md`, `AGENTS.md`, Xcode, Gradle, Cargo, Go, Python, and other project markers. Skips heavy generated folders and prevents duplicate or parent/child additions. |
| Dashboard | Native overview with starred, changed, and running filters; a half-width attention card beside four summary cards; collapsible project groups; dashboard and list layouts. |
| Project grouping | Default groups are inferred from path keywords. Move any project to an existing or new group from its context menu, or restore automatic classification at any time. |
| Batch actions | Filter by project group, then select projects across card or list views to rescan only those folders or copy one combined set of cleanup commands. Batch actions never delete files. |
| Attention queue | Surfaces failing tests, behind-remote and unpushed commits, uncommitted files, and reclaimable disk. Ordered by urgency; each row opens the matching project tab and offers inline push, fast-forward pull, test rerun, or cleanup-command copy. Right-click a row to snooze or mute that project/type; silenced rules can be restored from the header. |
| Menu bar | Keeps the pending-item count visible, opens the overview or a recent project, and sends local notifications when a dev server becomes ready or a test fails. |
| Quick open | `⌘K` searches projects, branches, remote URLs, and actions with recent items, fuzzy matching, and pinned commands. Run project commands and app actions without leaving the keyboard. |
| Project actions | Open a project in Finder, the preferred terminal (Terminal, iTerm2, Ghostty, or Warp), or an installed editor (Cursor, VS Code, Zed, Antigravity, JetBrains IDEs, and Xcode including nested targets), or copy its path. `⌘⇧T` opens the current project in the preferred terminal. |
| AI sessions | Lists matched Codex and Claude Code sessions with tool filters, shows the last user request, and copies `codex resume` / `claude --resume` commands. Dedicated CLI processes can be ended after confirmation; the shared Codex Desktop app-server is never terminated. |
| Git | Shows the current branch, ahead/behind state, dirty files, recent commits, and the `origin` URL. Supports opening or copying the remote, branch switching, and confirmed fetch, fast-forward pull, and push with inline results; dirty worktrees are protected. |
| Dev servers | Detects common dev scripts and ports; a floating Liquid Glass action dock provides run, test, logs, preview, and copy-command actions. |
| Disk usage | Breaks down project size and reclaimable space across dependencies, build caches, artifacts, temporary files, and AI session history. |
| Cleanup | Provides copy-only cleanup commands. It never executes destructive cleanup automatically. |
| Docs | Discovers and renders project documentation such as `README`, `PRODUCT`, `HANDOFF`, and `AGENTS`. |
| Tests | Detects `test`, `check`, `typecheck`, `mvn test`, and `go test`; streams output and duration. |
| Organization | Stars, color tags, notes, aliases, grouped technology badges, and automatic or manual project groups. |
| Safe removal | Both clients support remove-from-dashboard. Native and web can move a project to Trash or permanently delete it after backing up to `~/.repodeck/trash`, blocking shallow paths and running services/tests, and requiring the directory name. |

## Local data and privacy

FizzDeck does not upload project data or call a FizzDeck-hosted service. Development commands started by FizzDeck may make their own network requests.

The shared data directory is `~/.repodeck`. The path is kept for compatibility with existing installations.

```text
~/.repodeck/
├── roots.json        # managed folders and display aliases
├── state.json        # stars, tags, groups, notes, and UI state
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

Project removal only accepts managed roots, refuses shallow or protected paths, is blocked while a dev server or test is running, and requires typing the directory name. Permanent deletion first copies the project to `~/.repodeck/trash`.

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

- The native app requires macOS 26+ on Apple Silicon. A DMG is published, but it uses an ad-hoc signature and is not notarized.
- The native app includes batch rescan, cleanup-command copy, project removal, and ending dedicated AI CLI sessions.
- The native theme supports light and low-saturation charcoal dark modes, following the system by default.
- Lightweight background watchers refresh Git and AI-session state without full rescans.
- Local notifications require system permission. The `--sign-local` build uses an ad-hoc signature, which is enough to register with Notification Center for local testing; distribution still needs a Developer ID signature and notarization.
- AI session integration covers Codex, Claude Code, and Grok; the shared Codex Desktop app-server cannot be ended from FizzDeck.
- Port detection is heuristic; unusual development setups may need a mapping in `server.mjs`.
- Initial scans run `du`-style size checks and take roughly a few seconds per large folder. Later loads use the scan cache until a rescan.

## Status

FizzDeck is a personal, source-first macOS tool. The native app and web UI share one data directory, so switching between them does not require an export or migration step.
