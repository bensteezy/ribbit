# ribbit

ribbit is a native macOS workspace for two equal jobs: running terminal-based AI agents and writing raw text notes.

## run

```sh
./scripts/run-app.sh
```

The first build downloads Ghostty 1.3.1’s official source archive, verifies its
SHA-256 checksum, and builds a native `GhosttyKit` framework. This requires
Xcode’s Metal Toolchain and Zig 0.15.2 (`brew install zig@0.15`).

Before packaging a public build, run the complete release gate:

```sh
./scripts/verify-release.sh
```

This checks the source tree for personal paths and credential-shaped files,
runs the Swift suite, sends 21 editing/navigation chords through both a direct
PTY and an isolated tmux client, builds and signs the app, and verifies the
bundled third-party licenses.

## projects

- choose `new project…` to create a folder with a `ribbit-notes/` directory
- right-click any folder in the file inspector and choose `ribbit here`
- terminals start at the project root; new notes live in `ribbit-notes/`
- each project keeps its own terminal and note tabs; switching projects hides the other sets without closing them
- choose `base` to work from your normal home-directory shell without a project
- project registrations are stored in Application Support, leaving project roots clean

## terminal journals

Every ribbit terminal continuously journals its output to a rolling, 50 MB session log in Application Support. Raw journals stay outside project folders and are not added to Git automatically.

From a terminal attached to a project, save its retained session as a plain-text note:

```sh
ribbit save
ribbit save agent-session
```

The cleaned transcript is written to the project’s `ribbit-notes/` folder and opened as a note. ANSI color and terminal-control sequences are removed. The same action is available by right-clicking a terminal or pressing `⇧⌘S`.

Terminal journals can contain any secrets printed to the screen. Password prompts that disable terminal echo are not recorded, but visible API keys and tokens are.

## shortcuts

- `⌘T` — new terminal
- `⌘N` — new note
- `⌘O` — open project folder
- `⌘S` — save the active note
- `⇧⌘S` — save the active terminal transcript as a project note
- `⌘F` — find in the active terminal
- `⌘W` — close the active tab without closing the ribbit window
- `⇧⌘[` / `⇧⌘]` — previous or next tab
- `⌘1`…`⌘9` — select a tab directly
- `⌘K` — clear the active terminal
- `⌘-` / `⌘=` / `⌘0` — decrease, increase, or reset terminal text size

ribbit uses [libghostty](https://github.com/ghostty-org/ghostty) for its native
PTY, terminal emulation, and Metal rendering.

## persistent terminals and canvas

- tab mode and canvas mode are two views of the same terminal and note sessions
- each terminal attaches to a deterministic tmux session and survives ribbit quitting or crashing
- if tmux is unavailable, ribbit falls back to a direct shell and reports that persistence is off
- a Mac reboot restores the workspace; terminals with a saved Codex or Claude session ID offer an explicit resume button
- directed canvas links let a terminal read an explicitly linked note or journal with `ribbit context list` and `ribbit context read <name>`
- two-finger scrolling pans the empty canvas; pinching zooms around the trackpad pointer
- use the explicit `+` control to create a terminal without overloading canvas clicks
- node headers drag independently; their close, link, badge, and resize controls keep separate click targets

## agent activity

- optional local observer hooks report Codex, Claude, and Cursor activity to ribbit’s loopback-only bridge
- status badges identify running, ready, and needs-you sessions on the exact matching terminal
- clicking a badge focuses its terminal; optional local notifications do the same
- unmatched sessions appear in a compact external-agent dock; click to focus,
  use the pin button, or drag one onto the canvas
- external-agent canvas pins retain their project, position, latest status, and
  focus target across relaunches
- terminals, notes, and pinned agents can be grouped from a node menu; the
  labeled canvas boundary and membership persist with the project
- existing Noot agent state is imported once into ribbit without deleting or modifying the Noot files
- hook installation is always an explicit action in Settings

## agent monitor

- the optional top-of-screen monitor shows live Codex, Claude, and Cursor sessions without opening ribbit
- on a MacBook with a hardware notch, only the frog and session count extend beyond the camera housing; other displays use a small top-center bar
- hover briefly to inspect activity or click to pin the monitor open
- click a session row to return to its exact ribbit terminal, Codex task, or Cursor window
- a row’s `×` hides it from the monitor without stopping the agent; it returns for a new live phase or new attention
- `Escape` collapses a clicked-open monitor, while simple hover never takes keyboard focus from the active terminal or editor
- enable the monitor and tune hover, collapse, attention dwell, display target, and activity detail in Settings

## ai agent input

- Claude, Codex, and other terminal TUIs receive native Control, Option/Meta, Tab, Shift+Tab, arrow, Escape, and function-key input
- left, right, middle, and extended mouse buttons are forwarded to terminal applications that enable mouse reporting
- `Shift+Return` inserts a newline in agent prompts; `Option+Return` sends the standard Meta+Return fallback
- drag files, folders, or Finder images into a terminal to insert shell-safe absolute paths at the cursor
- image data dragged from another app is saved under the project’s `ribbit-notes/attachments/` folder; base-workspace images are stored in Application Support
- drops only insert text and never run the current command automatically

## license

ribbit is available under the [MIT License](LICENSE). Third-party dependency
notices are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), with
complete texts in [`ThirdPartyLicenses/`](ThirdPartyLicenses/). Release builds
embed both Ribbit's license and the full notice bundle.

When updating libghostty, regenerate the checked-in notice bundle:

```sh
./scripts/collect-third-party-licenses.sh
```
