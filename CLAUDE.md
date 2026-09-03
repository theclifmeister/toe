# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS tiling window manager: a direct port of Hyprland's `CHyprDwindleLayout`, with
Omarchy's defaults (`preserve_split = true`, `force_split = 2`). It runs as a background agent
(`.accessory`) with no Dock icon and no main window — a menu bar item, key bindings and a
gradient border around the focused window. Accessibility is the only permission it asks for.

## Commands

```sh
make test      # layout suite — no permissions, no Xcode, ~1s
make run       # build, bundle, sign, relaunch in place (replaces any running toe)
make bundle    # build/Toe.app, runs `make test` first
make install   # same, into /Applications
make dev-cert  # once per machine — see "Accessibility and code signing" below
make reset-perms
make example-config   # regenerate toe.example.toml from the default baked into the binary
```

`swift build -c release` and `swift run -c debug toe-selftest` are what those wrap.

**Running one test:** the harness has no filter. `Sources/toe-selftest/Harness.swift` is a plain
executable rather than XCTest (XCTest ships with Xcode, not the Command Line Tools, so this keeps
`make test` working on a bare CLT machine). The whole suite is ~600 assertions and runs in about a
second, so run all of it. Failures print as `test name:line — what: got X, want Y`.

**Diagnostics without launching the agent:**

```sh
toe --version                # what the bundle was stamped with
toe --print-default-config   # the shipped default TOML
toe --print-corner-radius    # what macOS rounds each on-screen window to
log stream --predicate 'subsystem == "com.clifmeister.toe"' --level info
```

## The two-target split

`Package.swift` enforces the architecture:

- **`Sources/ToeCore`** — pure geometry and state. No AppKit, no Accessibility, no Carbon. The
  dwindle port, workspaces, config parsing, the menu model, session snapshots, border geometry.
  This is the only part the selftest can reach, so **anything worth testing belongs here.** When a
  decision in `Sources/toe` needs test coverage, the move is to lift the arithmetic into ToeCore
  and leave the system call behind — `BorderGeometry` exists entirely for that reason.
- **`Sources/toe`** — everything touching the system. AX, CGWindowList, Carbon hotkeys, event
  taps, AppKit panels.

Adding an AppKit import to ToeCore breaks the test suite's reason for existing.

## How a change reaches the screen

`Coordinator` is the hub and the only `WindowTrackerDelegate`. Roughly:

1. `WindowTracker` discovers windows per-application via `AXObserver` and calls back
   (`windowAppeared`, `windowFocused`, `windowFrameChangedExternally`, `windowStackChanged`,
   `activeSpaceChanged`, `screensChanged`).
2. `Coordinator.dispatch(_ command:)` mutates `WorkspaceManager` — the layout model.
3. `apply(refocus:)` calls `workspaces.render()` for a `RenderPlan` (`frames`, `floating`,
   `stashed`, `focus`) and writes only what differs from `desired`.
4. `updateBorder()` last.

Two invariants in that loop are easy to break:

- **`desired` / `corrections`.** Chromium, Electron and JetBrains apps re-apply their own geometry
  after a window opens, so a frame is re-asserted when it changes behind toe's back — bounded at
  three attempts, so an app whose minimum size exceeds its tile is written once and left alone.
  Floating windows deliberately bypass this machinery: pointing it at one would fight the user's
  own drags.
- **A window the user has hold of is never written to.** `draggedWindow` is checked in `apply`,
  `windowFrameChangedExternally` and `updateBorder`; the frame is written once, on release.

## The quick menu mirrors Omarchy's tree

`MenuModel` is a port of `default/omarchy/omarchy-menu.jsonc` on Omarchy's `quattro` branch, not a
menu that borrowed some names — the same rows at the same depth in the same order, so that an
Omarchy user diving it finds their own menu with the Linux taken out. The rule for what is absent
is Omarchy's own `when` guard: a row whose condition fails is not listed, and a submenu whose
visible descendants have all gone goes with them. Before adding a row, check where upstream puts
it; before leaving one out, check that it genuinely cannot work here rather than that it was
inconvenient.

Two divergences are deliberate and should stay:

- **`Quit` is a root row.** Omarchy's `System` is a power menu for the machine; toe quits an
  agent, and one row does not want a level.
- **`About` is a `.note` row carrying the version**, where upstream's opens a branding window.
  toe has no window to open and one fact to report.

`disabled` (dim, ticked, unselectable, omitted from search) is upstream's guard for "you already
have this" and is why `Install › Style › Theme` can list the whole catalogue. `MenuState` enforces
it in four places — `move`, `select`, `activate` and the search filter — so a new way of reaching a
row needs a fifth.

## Things that will bite you

**Coordinate spaces.** `Box` is Accessibility coordinates: origin top-left of the primary display,
y growing *down*. `kCGWindowBounds` is already the same space — `WindowStack.ordinaryWindowsAbove`
does no conversion, and adding one would be invisible on a single display and badly wrong on two.
`Coordinates.toCocoa` / `toAX` flip about the primary display's height and are for AppKit only.

**Workspaces are not macOS Spaces.** There is no public API for putting a window on another Space,
so hidden workspaces park windows far off-screen (`stashPoint`) and restore their frames on return.
Consequences: stashed windows are still visible to Cmd-Tab and Mission Control, and anything that
asks the window server about an off-screen window gets an answer that means "not on screen", not
"nothing there". `WindowStack.windowsAbove` returning an empty set is the trap — `Stacking.raiseOrder`
reads empty as *this float is on top*, not *no idea*.

**Native-fullscreen windows** are never managed (`isManageable` rejects them) but do affect the
border: the border panel is `.canJoinAllSpaces` + `.fullScreenAuxiliary`, so it will happily paint
across a fullscreen Space unless something stops it. With *Displays have separate Spaces* on (the
macOS default) "is anything fullscreen" is never the right question — scope it to a display.

**State that outlives the process.** Symbolic hotkeys (`CGSSetSymbolicHotKeyEnabled`), the
wallpaper-click preference and the Dock's auto-hide (`CoreDockSetAutoHideEnabled`) belong to the
window server or the Dock, not to toe, so a `kill -9` during development would leave `Ctrl`+`↑`
dead — or the Dock hiding itself — with nothing to explain why. All three are journalled to
`~/.local/state/toe/` *before* the change is made and replayed in reverse at startup. If you add
another such global toggle, follow that pattern. `CoreDock*` is also the one place toe reaches a
symbol through `dlsym` instead of declaring it: unexported from every header, and a link-time
dependency on it would turn its removal into a launch failure.

**The session snapshot** (`~/.local/state/toe/session.json`) is keyed on `CGWindowID` plus
`kern.boottime`, and is restored *before* the tracker starts. A stale snapshot is discarded unread
rather than expired by age.

**AX calls are synchronous and on the main thread**, capped at 250 ms (`axMessagingTimeout`). They
are not rare — `isManageable` alone is six round trips per candidate window. Adding one to a path
that runs on every focus change or stack change is a real cost; put it after the cheap conditions.

## Accessibility and code signing

macOS keys the Accessibility grant to the code signature, and an ad-hoc signature changes on every
build — so without `make dev-cert` (a stable self-signed `toe-dev` identity, one password prompt)
you re-grant permission after every rebuild. `scripts/bundle.sh` picks it up automatically. When
hotkeys or window moves stop working after a rebuild, `make reset-perms` and re-grant.

## Releasing

Push a tag; nothing in the tree carries the version. `.github/workflows/release.yml` derives it
from the tag name, stamps `Info.plist` via `TOE_VERSION`, signs with the Developer ID cert,
notarizes, staples, publishes the release, then opens *and merges* its own `Casks/toe.rb` bump PR.

```sh
git tag -a v0.9.4 -m "toe 0.9.4 — <what changed>" && git push origin v0.9.4
```

`main` requires changes to arrive by PR, which is why the cask bump is a self-merging PR marked
`[skip ci]` rather than a push.

**The `claude-review` check reports `pass` while leaving inline comments.** `gh pr checks` does not
surface them. Read `gh api repos/theclifmeister/toe/pulls/N/comments` before merging — a green
check is not an empty review.

## Conventions

Comments here explain **why**, at length, and frequently name the bug or the platform behaviour
that forced the code into its shape ("this guard has to come first", "learned at v0.9.1"). Match
that density — a change that removes the reasoning is a regression even when the code is right.
Commit subjects are sentences in the imperative: *Send a detached window behind the tiles when it
loses the focus*.

`Resources/Toe.icns` is committed and `make icon` regenerates it — deliberately not a build
dependency, so don't run it unless the icon is the point.
