# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS tiling window manager: a direct port of Hyprland's `CHyprDwindleLayout`, with
Omarchy's defaults (`preserve_split = true`, `force_split = 2`). It runs as a background agent
(`.accessory`) with no Dock icon and no main window — a menu bar item or, with `[bar] enabled`,
Omarchy's bar across the top of every display, key bindings and a gradient border around the
focused window. Accessibility is the only
permission it asks for by default; the opt-in `[animations] slide_style = "pictures"` is the one
feature behind a second one (Screen Recording — see `ScreenSnapshot`; the default `"cards"` style
draws the slide from the model and asks for nothing), and the bar's Bluetooth panel the one
behind a third, asked the first time that panel is opened (see "The bar").

## Commands

```sh
make test      # layout suite — no permissions, no Xcode, ~1s
make run       # build/ToeDev.app, sign, relaunch in place (replaces any running toe)
make bundle    # build/Toe.app — the installed identity; runs `make test` first
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

`toe query state` and the rest of the command line are the same binary talking to the running
agent — see "The control socket" below.

**Diagnostics without launching the agent:**

```sh
toe --version                # what the bundle was stamped with
toe --print-default-config   # the shipped default TOML
toe --print-corner-radius    # what macOS rounds each on-screen window to
toe help                     # the command line's own usage (also what a bare `toe` prints)
toe skill print              # the generated Claude Code skill, without writing it anywhere
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

**`Apps` is a provider level** in Omarchy's sense — its rows come from the machine, not the
menu file. `AppLibrary` (in `toe`) scans the application folders off the main thread, once at
start and again on every open, and the Coordinator holds the last answer; `Apps.ordered` and
`MenuModel.apps` (in `ToeCore`) do everything after that. An app row's icon is `.application(path:)`,
the one `MenuItem.Icon` that is a picture rather than a glyph, and the one `foundAt` keeps on a
search hit. Pressing one is `MenuOutcome.launch`, not a `Command`: it is not a verb, and a path
with an apostrophe in it does not want to go through `/bin/sh`.

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

**A tile can outlive what was in it.** The tracker hears that a window has gone from exactly two
places — `kAXUIElementDestroyed` / `kAXWindowMiniaturized` on the element, and the application
terminating — and a tile going native fullscreen is neither, so the desktop kept a hole where it
was (#147). `Coordinator.checkPresence` is the failsafe: one `CGWindowListCopyWindowInfo`, on
every stack and Space change and every three seconds, judged by `Presence.assess` in ToeCore. A
tile the window server does not list is reaped; one it lists on another Space is *suspended* —
`WorkspaceManager.suspend` takes it out of the tree and remembers its workspace and neighbour,
`resume` puts it back. Two things to keep straight: a suspended window is on **no** workspace
(`workspaceIndex(of:)` is nil, the state report says `hidden` on the workspace it will return
to), and `Presence.Watch` will not believe "away" or "back" until the same answer has held for
`presenceRecheckLatency`, because a fullscreen transition reads as both on the way through.

**Native window tabs are one tile.** Every tab of a Terminal, Ghostty or Safari window is a real
`NSWindow` that `isManageable` would accept, and the tabs share one frame — so a tile per tab is
one window dragged between two places (#165). `TabGroups` keeps the group to one tile and the
window in front of it as the holder; on a switch the incoming tab takes the tile over *in place*
(`DwindleLayout.rename`, `WorkspaceManager.replaceWindow`), never a remove and an insert. The
signal is `WindowTracker.hiddenTabs`: a tracked window that has dropped out of its application's
`AXWindows` while the window server still lists it. Minimized windows and windows on other Spaces
stay in that list; only a tab that has gone behind leaves it. Two consequences: a tab switch posts
`kAXMainWindowChanged` and *no* focused-window change, which is why the tracker observes both; and
a window behind a tab is on **no** workspace, like a suspended one, and is not `Presence`'s to
judge — it is not in the tree.

**Native-fullscreen windows** are never managed (`isManageable` rejects them) but do affect the
border: the border panel is `.canJoinAllSpaces` + `.fullScreenAuxiliary`, so it will happily paint
across a fullscreen Space unless something stops it. With *Displays have separate Spaces* on (the
macOS default) "is anything fullscreen" is never the right question — scope it to a display.

**State that outlives the process.** Symbolic hotkeys (`CGSSetSymbolicHotKeyEnabled`), the
wallpaper-click and edge-tiling preferences and the Dock's auto-hide
(`CoreDockSetAutoHideEnabled`) belong to the window server or the Dock, not to toe, so a `kill -9`
during development would leave `Ctrl`+`↑` dead — or the Dock hiding itself — with nothing to
explain why. All four are journalled to `~/.local/state/toe/` *before* the change is made and
replayed in reverse at startup. If you add another such global toggle, follow that pattern:
`Journal` is the file, `JournalFormat` its lines, and `StateDirectory.ensure` the only thing that
makes the directory — and a record that could not be written is a change that is not made.
`CoreDock*` is also the one place toe reaches a symbol through `dlsym` instead of declaring it:
unexported from every header, and a link-time dependency on it would turn its removal into a
launch failure.

**The session snapshot** (`~/.local/state/toe/session.json`) is keyed on `CGWindowID` plus
`kern.boottime`, and is restored *before* the tracker starts. A stale snapshot is discarded unread
rather than expired by age.

**AX calls are synchronous and on the main thread**, capped at 250 ms (`axMessagingTimeout`). They
are not rare — `isManageable` alone is six round trips per candidate window. Adding one to a path
that runs on every focus change or stack change is a real cost; put it after the cheap conditions.

## The bar

Off by default — `[bar] enabled = false`, and absent reads as off — because it takes the menu
bar away from a Mac user who did not ask; on, the `NSStatusItem` is not created and the bar is
the strip. `BarWindowSet` is one `NSPanel` per `NSScreen` across the top of its frame, one
level *above* the menu bar — sketchybar's `topmost` — so the bar covers the menu bar rather than
replacing it; `BarView` draws the items `BarLayout.place` positions, in `draw(_:)` like
`MenuView`.
Everything that can be a value is in `ToeCore/Bar/`: `BarItem` is Omarchy's `WidgetButton`,
`BarMetrics` its `Style.bar` with `[bar] height` as the scale, `BarWidgets` the glyph rule of
each widget from the numbers a Mac reports, `ClockFormat` the Qt-spelled formats and their
`DateFormatter` translation, `Glyphs` the codepoints. The providers in `toe/Bar/Providers/`
read the system and say when it changed — a listener where one exists, never a poll — and
`Coordinator.refreshBar` assembles a `BarSnapshot` on every `refreshStatus`.

Four things to keep straight:

- **The exclusive zone is `usable`.** `refreshMonitors` reserves the bar's strip from the
  display's *frame* (`Monitor.reserving(top:)`) — the menu bar under the bar has already kept
  its own strip out of `visibleFrame`, so the bar costs the tiles only what it needs beyond
  that — and nothing downstream knows the bar exists. `bar hide` takes the panels away and the
  menu bar is what shows; the strip stays the menu bar's.
- **Do not hide the menu bar.** The first cut set `_HIHideMenuBar` and sat one level under,
  and the menu bar slid back in over the bar on every trip to the top edge; worse, `NSScreen`
  never learns of a hide made by its own process, so `visibleFrame` stayed stale for the rest
  of the run. Covering it at level 25 has neither problem, and no state that outlives toe.
  The bar is the taller of `[bar] height` and the menu bar's strip, so no line of it shows.
- **The peek is how the menus are reached by mouse.** `MenuBarPeek` (ToeCore, in the
  selftest) is auto-hide's gesture with a dwell: the pointer held against the top edge for
  0.3 s orders that display's panel out, and it comes back 0.4 s after the pointer has left
  the strip with no menu open. `BarPanel` drives it from a 50 ms timer that runs only while
  the pointer is on the strip or a peek is on — never a global mouse monitor, which is the
  cost sketchybar's maintainer measured and refused. "A menu is open" is an on-screen window
  at `kCGPopUpMenuWindowLevel` (101) in the window list, checked only when the pointer has
  left mid-peek. `BarWindowSet.refresh` leaves a peeking panel alone, so the clock ticking
  does not bring the bar back over a menu the user is reading.
- **The notch.** AppKit keeps every window out of a notched display's top safe area through
  `constrainFrameRect`; `TopStripPanel` overrides it. On that display the bar is the safe
  area's 32 pt tall and the centre section is centred on the right-hand gap beside the notch
  (`BarWindowSet.centre(on:)`) — a clock under the camera housing is in the framebuffer and not
  on the glass.
- **Fullscreen is scoped per display**, as the border scopes it: `BarWindowSet.fullscreen` is
  the frontmost fullscreen window's frame, and only the panel on the display it overlaps
  hides. Read where `updateBorder` already reads it, and on its own at the start of a Space
  change and the end of the settle.

**The panels.** A left click on a right-section widget — and on the clock — opens a panel of
toe's own under it: Omarchy's `plugins/panels/*/Panel.qml`, cut to what a Mac exposes
publicly, in the quick menu's chrome at the bar's type size. The split is the bar's again:
`ToeCore/Bar/Panels/` holds `PanelRow` (one row: hero, header, slider, list row, the Settings
door), `PanelState` (the cursor — hidden until the first arrow, clamped, stepping over what
cannot be chosen, following a device by identity when the list is rebuilt under it),
`PanelLayout` (the rows' frames at Omarchy's `Style` tokens, the card anchored under its
widget inside the display) and one model per panel (`PowerPanel`, `MonitorPanel`,
`ClockPanel`, `AudioPanel`, `NetworkPanel`, `BluetoothPanel`) — a pure function from what the
provider read to rows, all in the selftest. `toe/UI/BarPanelWindow.swift` is the one popover
for all six (`PanelView` draws), `Coordinator.openPanel` fills it, and `refreshBar` pushes new
rows into it on every provider change so a slider you are holding shows the volume the device
confirmed. Four rules:

- **Every panel ends on its Settings pane** — the click that used to open the pane is the
  panel's last row, so nothing is lost. `PanelState` is not `MenuState`, though #177 asked for
  that where it fits: a panel is one flat list with sliders and a hero, not a tree with a
  search, and what carries across is the rules, not the type.
- **Panels ask for one permission, and only Bluetooth's, and only from the Bluetooth panel.**
  `BluetoothProvider` starts with the rest but reads nothing until `CBCentralManager.authorization`
  says it may; the widget draws the generic "on" glyph until then; the panel's first open makes
  the `CBCentralManager` whose creation puts the sheet up (`NSBluetoothAlwaysUsageDescription`).
  The network panel does **not** ask for Location — measured for #177: without it every SSID
  is nil and a scan blocks for seven seconds, so the panel is the connection's numbers and a
  note saying why there is no name. Brightness has no public route on Apple silicon (no
  `IODisplayConnect` service), so the monitor panel has no slider. Both measurements are
  comments on #177.
- **A click on the bar is not a click outside.** `BarPanelWindow`'s click monitor lets the
  bar's clicks through so that `barClicked` can answer them: the open panel's own widget
  toggles it closed, another widget's swaps the rows in place under the other slot. Anything
  else — Escape, a click elsewhere, losing key to another application, a screen change, `bar
  hide`, fullscreen on that display — closes it.
- **Bold is a stroke.** The bundled face is Regular only; the panels' headers and titles are
  drawn with a negative `strokeWidth` rather than 2.6 MB of Bold in the bundle.
- **The network panel's traffic graph is the one poll** (#189), and it runs only while that
  panel is up: a byte counter has no listener, so `NetworkProvider.startTraffic` samples
  `sysctl NET_RT_IFLIST2` once a second from `openPanel(.network)` until `BarPanelWindow`'s
  `onClose` or a swap to another widget. `NetworkTraffic` (ToeCore) turns the readings into
  the ring the `.graph` row carries; the glide between samples is `BarPanelWindow`'s timer,
  alive only while a sample is sliding in. If `log stream` shows `network: traffic` lines with
  no panel open, something has grown a third way out of the panel.

The Focus state (Dnd) still waits on a permission toe does not ask for — it lives in a
Full-Disk-Access-protected database — and has no provider.

## The control socket

`toe <verb>` is the same binary, deciding by argv before `NSApplication` exists — the shape
`--version` and `--print-default-config` already had. It connects to a Unix socket at
`~/.local/state/toe/toe.sock` and the running agent answers. A Mach service would be the more
macOS answer and is not available: it needs a `MachServices` key in a launchd plist, and toe is as
often started by `open Toe.app`, which never goes through launchd.

The split follows the two-target rule. `ToeCore/Control` holds the wire types, the argv parsing,
the selectors, the verb catalogue, the layout profiles and the generated skill document — all of
it pure, all of it in the selftest. `toe/Control` holds the socket, the client, and the assembly
of live state into `StateReport`.

Three things here are easy to break:

- **The socket runs on the main thread**, because a request ends in Accessibility writes and those
  are main-thread-only. So nothing in `ControlSocket` may block: non-blocking descriptors, a
  64 KiB cap, a two-second deadline on a connection that has not produced a whole request, a
  write source for partial writes, and `SO_NOSIGPIPE` on every accepted descriptor.
- **A batch renders once.** `Coordinator.batch` holds `apply` while a run of commands executes,
  because every arm of `dispatch` ends in its own `apply` and ten of those is an arrangement
  assembling itself on screen. Only synchronous runs are ever wrapped.
- **`exec` and `quit` are gated** by `[cli] allow_exec` / `allow_quit`, and `CommandCatalogue.gate`
  is where that is decided. The socket is not a privilege boundary — it is mode 600 in your own
  home directory — but a window manager with one verb that runs shell lines should not hand a
  shell to everything that learns to talk to it as a side effect. A new verb that runs anything
  belongs on that list.

**A bare `toe` from a shell is not the agent.** `make install-cli` and the cask's `binary` stanza
both put `toe` on the PATH, at which point somebody types it to see what it does — and started from
a shell the agent inherits that shell's process group, so closing the tab signals it and
`installSignalHandlers` shuts it down, after `takeOver` has already stopped the copy that was
running properly. `isatty` on **either** standard input or standard output separates that from
launchd and `open Toe.app`, which have neither; one alone leaves a hole that `toe | head` or
`toe > log` walks through, which is how this was found. `toe agent` is the deliberate way in from a
shell.

`Command.acceptsTarget` is the other rule worth knowing: `--window` may only be pointed at the
verbs whose meaning survives being aimed away from the focus. The directional ones do not — they
mean "from where the focus is" — and the catalogue's `--window` column is computed from that
property rather than written down beside it, so the table cannot claim a target the dispatcher
would refuse.

The skill document (`SkillDocument`) is generated rather than committed, and its verb table comes
from `CommandCatalogue`, so a verb added to the table reaches the file without anybody remembering
to. The prose around it is the part that cannot be derived, and it is the reason the file exists:
workspaces are not Spaces, fullscreen suspends half the verbs, a float is the user's. Installing
it is `Install › Claude Code skill` in the quick menu, `toe skill install` on the command line, or
the `installskill` verb.

## Accessibility and code signing

macOS keys the Accessibility grant to the code signature, and an ad-hoc signature changes on every
build — so without `make dev-cert` (a stable self-signed `toe-dev` identity, one password prompt)
you re-grant permission after every rebuild. `scripts/bundle.sh` picks it up automatically. When
hotkeys or window moves stop working after a rebuild, `make reset-perms` and re-grant.

**The grant is keyed to the bundle identifier as well**, which is why `make run` builds a second
application rather than the same one: `build/ToeDev.app`, `com.clifmeister.toe.dev`, "Toe Dev" in
the Accessibility list. The installed copy is signed with Developer ID and this one with `toe-dev`,
so under one identifier each launch invalidated the other's grant and asked again. Two identifiers,
two grants, each given once — and `make reset-perms` resets both.

Two applications, one machine. Everything toe does is global — the hotkeys, the taps, the windows,
the four settings journalled to `~/.local/state/toe` — so `AppIdentity.takeOver` asks any other
running copy to quit and waits for it, first thing in `Coordinator.start`, before the journal
repairs the outgoing copy is still writing. `SIGTERM` and not `NSRunningApplication.terminate()`:
that sends a quit Apple Event, and AppKit answers it without going near `shutDown`, which would
leave a hidden workspace's windows parked in the stash corner. Config and state are deliberately
shared, since only one copy ever runs and a swap should keep your layout.

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
