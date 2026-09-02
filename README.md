# Toe — The Opinionated Experience

A small native macOS window manager: Hyprland's **dwindle** layout, ten workspaces, and
nothing else. One layout, one set of key bindings, nothing to agonise over — that is the
opinion, and it is the whole product.

The opinions are borrowed, mind. `TOE` first stood for *The Omarchy Experience*, and toe
still cribs every default from [Omarchy](https://omarchy.org) — the Linux that had these
opinions first and, being an entire distribution, had a great many more of them.

The layout is the part nothing else on macOS gets right. The tilers here are i3-style —
explicit splits, with container normalization that flattens the tree dwindle depends on — so
the one thing they cannot reproduce is dwindle itself. toe's tiler is a direct port of Hyprland's
`CHyprDwindleLayout`, with Omarchy's settings (`preserve_split = true`, `force_split = 2`)
as the defaults.

## What it does

| Binding | Action |
|---|---|
| `SUPER` + `←↑↓→` | Move focus |
| `SUPER` + `SHIFT` + `←↑↓→` | Swap window with its neighbour |
| `SUPER` + `1`…`9`, `0` | Switch to workspace 1…10 |
| `SUPER` + `SHIFT` + `1`…`9`, `0` | Move window to workspace and follow it |
| `SUPER` + `TAB` / `SHIFT`+`TAB` / `CTRL`+`TAB` | Next / previous workspace in use, former workspace |
| `SUPER` + `ENTER` | New terminal window |
| `SUPER` + `SHIFT` + `ENTER` | New browser window |
| `SUPER` + `W` | Close window |
| `SUPER` + `J` | Toggle split orientation |
| `SUPER` + `T` | Cycle floating: 70×80% of the display, 80×90%, back to tiling |
| `SUPER` + `SPACE` | The quick menu — Configure, Learn, Quit |
| `SUPER` + `K` | Every binding, in a list |
| `SUPER` + `,` | Edit the config — nano, in a terminal window |
| `SUPER` + `SHIFT` + `R` / `Q` | Reload the config / quit toe |
| Drag a tiled window | Swap it with the tile you drag it over |

`SUPER` is **Option (⌥)** — the same physical key position as SUPER on a PC keyboard, and it
leaves ⌘S ⌘F ⌘T ⌘W ⌘1-9 ⌘Tab untouched. Configurable.

The focused window gets a gradient border, and everything is driven by a hot-reloaded config
at `~/.config/toe/toe.toml`.

## The menu bar

The status item is the workspace strip, styled the way Omarchy's waybar styles it: the
workspace you are on is a filled rounded square rather than a number, every other workspace
is its own digit, and workspace 10 shows as `0`. Workspaces 1-5 always have a slot — that is
waybar's `persistent-workspaces` — dimmed while they are empty; past those, a workspace shows
up only once it has windows on it. With several displays, a workspace showing on one you are
not focused on gets the same square, outlined.

```
T  ▪ 2 3 4 5 7
```

`[bar] persistent_workspaces` sets how many keep a slot: `0` shows only the ones in use, `10`
always shows all ten.

toe's own mark leads the strip — the T from the app icon, without the tile, drawn at menu bar
size so it takes the menu bar's own colour. Clicking it opens the quick menu, which is the one
thing on the bar that is not a workspace.

Clicking a workspace switches to it, as Omarchy's `on-click: activate` does. That is the
whole of it — waybar's strip has no menu behind it, and neither has this one. toe's own
actions are key bindings instead: `SUPER`+`,` edits the config, `SUPER`+`SHIFT`+`R` reloads
it, `SUPER`+`SHIFT`+`Q` quits. A config that will not parse is named in the item's tooltip.

## Install

```sh
brew tap theclifmeister/toe https://github.com/theclifmeister/toe
brew install --cask theclifmeister/toe/toe
open /Applications/Toe.app
```

The two-argument `brew tap` is because the cask lives in this repository rather than a
separate `homebrew-toe` one. `brew upgrade --cask toe` picks up new releases.

Grant **System Settings → Privacy & Security → Accessibility** when asked. That single
permission is all toe needs.

### Treat your config as code

`~/.config/toe/toe.toml` is not merely settings. An `exec` binding runs `/bin/sh -c` with
whatever the file says, toe reloads the file about 150 ms after it changes, and it does so
inside a long-running login agent holding the Accessibility grant you just gave. That is by
design — it is Hyprland's `exec` dispatcher, and it is what `SUPER`+`RETURN` opening a terminal
is built on — but the consequence is worth saying plainly: **anything that can write that file
can run commands as you, with no prompt.** Give it the same care you would a shell profile.

toe creates the directory `0700` and the file `0600` on first run, so nothing else on the
machine can write it by default. If the file is later found writable by other users, or owned
by someone else, the menu bar item says so. Symlinking it into a dotfiles repository still
works, and is checked at the far end of the link.

### From source

```sh
make install          # builds, signs, copies to /Applications
open /Applications/Toe.app
```

`make run` builds and launches in place without installing. `make test` runs the layout suite.

### Start at login

```sh
make start-at-login   # from a clone; writes a LaunchAgent for /Applications/Toe.app
```

## How faithful is the dwindle?

Every rule below is ported from the Hyprland source rather than approximated, and is covered
by `make test` against hand-computed Hyprland output:

- A new window splits the **focused** window, always taking the right or bottom half
  (`force_split = 2`).
- Orientation is chosen once, from the region's aspect ratio (`w > h * split_width_multiplier`
  → side by side), and then **frozen** (`preserve_split = true`). This is why a dwindle layout
  stays put as windows come and go.
- Closing a window hands its exact space to its sibling — nothing else reflows.
- `SUPER+SHIFT+arrow` is Omarchy's `swapwindow`: the two windows trade places and the tree
  shape does not change. (`movewindow` — i3-style reparenting — is available in the config if
  you prefer it.)
- Dragging a tiled window swaps it with whichever tile the pointer crosses, live, and keeps
  going for as long as you hold it — Hyprland's `switchWindows` under the pointer, the mouse
  equivalent of `SUPER+SHIFT+arrow`.
- Directional focus between tiles is **edge adjacency**, not nearest-centre: a window qualifies
  only if its opposing edge lines up with yours within 2px, computed on un-gapped node boxes.
  Ties go to the most recently focused window. Detached windows are off the grid entirely and
  are walked as a list — see **Floating windows**.

## Design notes

**Workspaces.** macOS has no API for putting a window on a virtual desktop without private
SkyLight calls, so hidden workspaces park their windows far off-screen and restore their exact
frames on return. The trade-off is that stashed windows
remain visible to Cmd-Tab and Mission Control, and Cmd-Tabbing to one can pull it back onto the
current workspace.

**Dock swipes.** A four-finger swipe up opens Mission Control, which puts that off-screen stash on
display; a sideways swipe changes the macOS Space out from under toe, leaving its model of the
screen describing windows that are no longer on it. So toe swallows the Dock's swipe gestures —
up, down, left and right — with a session-level `CGEventTap` inserted ahead of the Dock. It keys
off the gesture's event type rather than a finger count, so it covers the three-finger setting
too. `CGEvent.tapCreate` is public API and this needs no entitlement and no private symbol, but
the mask — two gesture event types — and the fields the callback reads are undocumented, so
anything that does not positively identify itself as a dock swipe is passed straight through. The
worst a wrong guess there can do is drop a gesture: no keystroke, click or scroll can reach a tap
masked this way. `gestures.swallow_dock_swipes = false` turns it off.

The cost is that swiping between Spaces is gone, including swiping out of a natively-fullscreen
app's Space — and natively-fullscreen windows are one of the things toe leaves alone. `Ctrl`+`←`/`→`
still switches Spaces and `⌃⌘F` still leaves fullscreen; the config key is there for anyone who
would rather have the swipe.

The swipe is not the only way in: `Ctrl`+`↑` and `Ctrl`+`↓` open the same two views. Those are
*symbolic hotkeys*, resolved inside the window server well before any event tap sees a key, so the
tap cannot help — toe switches them off with `CGSSetSymbolicHotKeyEnabled` while it runs. Unlike
the tap, that state outlives the process: the window server keeps it, so a toe that died without
restoring would leave `Ctrl`+`↑` dead with nothing to say why. Every change is journalled to
`~/.local/state/toe/symbolic-hotkeys` *before* it is made, and a journal found at startup is
replayed in reverse, which is what repairs a crash, a `kill -9` or a logout. Show Desktop is left
alone, because its gesture is a thumb-and-three-finger spread rather than a dock swipe — the key
and the gesture stay consistent. `misc.disable_expose_shortcuts = false` leaves all of them alone.

**The wallpaper click.** Clicking a bare patch of wallpaper sweeps every window off the sides of
the screen and leaves them there until the next click — and with `gaps_out` set, bare wallpaper is
one missed window edge away at any time. It takes the off-screen stash along with the tiles, so
it lands toe in the same place a swipe up would. There is nothing to swallow here: WindowManager
decides it from a click that belongs to the wallpaper rather than to any window, and it is a
setting rather than a gesture. So toe writes the setting — `EnableStandardClickToShowDesktop` in
`com.apple.WindowManager`, the one System Settings › Desktop & Dock calls "Click wallpaper to show
desktop" — and, since that outlives the process just as a symbolic hotkey does, journals it to
`~/.local/state/toe/wallpaper-click` first. An absent key is journalled as absent and restored by
removing the key again, so a setting you never set is not left holding a value you never chose.
A reveal you had already switched off yourself is left alone. `misc.disable_wallpaper_click = false`
hands the click back.

**The quick menu.** The menu bar item is the workspace strip and nothing else, which is faithful
to waybar and leaves toe with nowhere to *show* you anything: the bindings above are the whole
interface, and a Homebrew user has no way to discover one of them. Omarchy has the surface that
fills that gap, and it is not a menu bar menu — it is the one walker draws for `omarchy-menu`, on
`SUPER`+`ALT`+`SPACE`. toe ports that to `SUPER`+`SPACE`, with the keybindings list on
`SUPER`+`K` as Omarchy has it. Arrows to move, `ENTER` to choose, `ESC` or backspace to back out,
and a second `SUPER`+`SPACE` to close. `Configure` holds *Run on startup* and *Edit
configuration*, `Learn` holds the keybindings, and `Quit` is a row rather than a keystroke you
had to know. *Run on startup* is `SMAppService`, so it appears in System Settings › General ›
Login Items too — and it is left out of the menu entirely where it cannot work: from a build
directory rather than `/Applications`, or alongside a LaunchAgent that `make start-at-login`
wrote. The log says which, and what fixes it.

Typing searches what a row does as well as what it is called — on the keybindings page the name
is `SUPER`+`W` and the description is *Close window*, so a filter that read only names would have
you typing modifiers to find anything. It searches the whole tree rather than the level in front
of you, too, and every hit says where it was found — type `startup` at the top and *Run on startup* comes back labelled `Configure`,
ready to act on without going there first. That is Omarchy's behaviour, and it is the difference
between a filter and a search: you should not have to know which submenu something lives in to be
able to type its name.

It is drawn to walker's own stylesheet — the 0.95 background, the 2px border with no corner
radius, the 20px padding, the 14px rows and the selected row at 7% with its text in the accent
colour — and in the font Omarchy renders it in, JetBrainsMono Nerd Font, which ships inside
Toe.app and is registered for toe's own process only. Nothing is installed, no permission is
asked, and it never appears in another app's font menu; bundling it rather than looking for one
is also what makes the rows the same width on every Mac. `[menu]` retunes the colours and the
size.

The panel is a `.nonactivatingPanel`, so it takes the keyboard without toe becoming the active
application: the window you were in keeps its title bar and its menu bar, and the focus model
keeps working — `isEchoOfOwnRaise` tells a real focus change from the echo of a raise by asking
which application is frontmost, and toe making *itself* frontmost would break that test for every
window it had recently raised. While the menu is up, the other bindings are held back, since
`SUPER`+`W` would otherwise close a window you cannot see; `quit` stays live so a wedged menu can
never trap you.

The costs, plainly: `SUPER`+`SPACE` and `SUPER`+`K` are ⌥Space and ⌥K, and Carbon claims them
system-wide while toe runs, so neither types ` ` or `˚` any more. Neither collides with a system
shortcut — Spotlight is ⌘Space — and both are ordinary bindings you can move.

**Hiding.** `⌘H` and `⌘⌥H` take an application's windows out of the layout without closing them:
the tree reflows around the gap, and `SUPER`+arrows cannot reach them again because they are no
longer on any workspace. Omarchy has no equivalent, so toe puts a hidden application straight
back. Deliberately done by watching `NSWorkspace.didHideApplicationNotification` rather than by
swallowing the keystroke — hiding is observable, so it can be undone without a keyboard tap, and
the notification also catches the routes a shortcut tap would miss: the Dock's Hide menu item, an
app hiding itself, and `⌘⌥H` hiding everything else at once. The window is gone for a frame, since
the notification arrives after the fact rather than instead of it.
`misc.prevent_hiding = false` turns it off.

**Restarting.** Quitting toe used to cost you the whole layout — every workspace flattened, every
window back on one screen. It no longer does: where each window was, the workspace it was on, its
slot in the dwindle tree, every split orientation and ratio, and the frames floating windows
return to are written to `~/.local/state/toe/session.json` and put back on the next launch. So
`make run`, a crash, an upgrade and `SUPER+SHIFT+Q` followed by a relaunch all leave the screen
exactly as they found it.

Windows are matched on their `CGWindowID`, which the window server issues when a window opens and
keeps for as long as it exists, whatever happens to toe — so this is exact, with no guessing from
app names or window titles. A reboot renumbers everything, and a stale snapshot would then scatter
windows into workspaces belonging to whatever now holds those numbers, so the file records
`kern.boottime` and is discarded unread when it no longer matches. That is a fact rather than an
expiry guess, which is why there is no age limit: a Mac left running for a fortnight has the same
window ids it started with, and its snapshot is as good on day fourteen as on day one.

Restoring happens *before* the window tracker starts, because the applications are still running
and their windows arrive through Accessibility over the second that follows — the tree has to be
waiting for them rather than built around them as they turn up. Anything the snapshot named that
has not appeared 2.5 seconds in is an application that was quit while toe was down; those windows
are dropped and the trees collapse over the gaps exactly as they would have at the time. Displays
are recorded by UUID rather than by `CGDirectDisplayID`, which is handed out per connection, so a
monitor that comes back as a different number still gets its own workspaces; a display that is
gone hands them to the focused one, the same thing unplugging it while toe runs does.

The snapshot is written on the way out — the one path both `SUPER+SHIFT+Q` and `make run`'s
`SIGTERM` reach — and again, debounced, on every layout change, which is what covers a `kill -9`.
`misc.restore_session = false` turns it off and removes the file.

**Hotkeys** use Carbon's `RegisterEventHotKey`, deliberately not a keyboard `CGEventTap`. A tap
masked to key events would receive every keystroke you type; Carbon hotkeys only ever deliver the
exact combinations toe registers. The one tap toe does run — see **Dock swipes** — has a mask
covering two gesture event types and nothing else, so it cannot see a keystroke even in principle.

**Electron and Chromium apps** (Chrome, VS Code, Slack) and the JetBrains IDEs ignore or
animate programmatic resizes while `AXEnhancedUserInterface` is set. toe clears it around each
frame write and restores it afterwards, which is what makes those apps tile.

**Apps that fight back.** Chromium, Electron and JetBrains apps re-apply their own remembered
geometry a beat after a window opens, clobbering the frame toe just wrote, so toe re-asserts the
layout when a window moves or resizes behind its back. That is bounded at three attempts: an app
whose minimum size exceeds its tile (Safari will not go narrower than ~574px) is written once and
then left alone rather than fought with forever. A tile is re-asserted against an app, never
against you: a window you have hold of is left alone until you let go — see **Dragging**.

**Dragging.** Pick a tiled window up by its title bar and the tile under the pointer trades
places with it, the way Hyprland's `IHyprLayout::onMouseMove` does — only the two windows move,
the tree shape does not change, and crossing onto another display takes the window and the focus
with it. It keeps swapping as you sweep across tiles, so where you let go is where the window
lands; let go over the tile you started on and nothing has changed. The focus border stays behind
on the tile the window will land in, so the target is visible the whole way across — a border
chasing the window itself would only trail behind it, because toe hears about its movement
through Accessibility, well after the fact. It sits *under* the window you are dragging, which is
where Hyprland puts it: a border there is drawn inside its own window's render pass, and the
focused window is drawn last of all, so a dragged window passes over the tiles it crosses. macOS
will not slot a panel behind one particular window — `order(_:relativeTo:)` stops at the process
boundary — but it does not have to, because toe is a background app and its normal-level panel
lands directly beneath the frontmost window, which is the one being dragged. toe cannot see the drag
itself — those events belong to the window's own application — so it infers one from an
Accessibility move notification arriving while a mouse button is down, and follows the pointer
with a read-only global event monitor rather than an event tap. For as long as you have hold of
a window toe writes nothing to it, which is what stops it being yanked out from under the cursor;
its frame is written once, into whatever tile it now owns, when you release.

**The focus border** is a panel above every ordinary window, which is right until something is
genuinely stacked over the focused one — a settings panel, a dialog — because a floating-level
panel is composited above every ordinary window whatever the real z-order says, and the ring
gets drawn straight through it. Accessibility does not expose stacking order at all, so toe asks
the window server what is above the focused window and drops the border to the ordinary level
when any of it covers the band. That is a read of `CGWindowListCopyWindowInfo` for geometry
only — never `kCGWindowName`, which would need Screen Recording, so Accessibility stays the one
permission toe asks for. The border still sits above every inactive application, so it stays
visible all the way round the window; only what is really in front of it covers it.

**Floating windows.** `togglefloating` lifts a window out of the tree and centres it, at a
consistent fraction of the display — 70% wide by 80% tall by default — so every floating window
is the same shape whichever window it came from. It is a cycle rather than a toggle: press it
again and the window is re-centred at the larger size, 80% by 90%, and only the third press puts
it back in the tree. A window toe floated on its own — a dialog, anything that will not take a
size — has no place in that cycle, and the first press tiles it. No floating window is ever wider
than 1.6 times its own height, which is what stops 70% of a 32:9 ultrawide from being a
letterbox; on a laptop that cap never comes into play. All of it is `[floating]` keys in the
config, and setting `large_width`/`large_height` to the same values as `width`/`height` gives
back the plain two-state toggle. Sizing happens when you float the window, not on every frame,
so dragging it afterwards sticks: toe writes a
floating frame only when it actually changes and never re-asserts it, so a floating window is
never fought the way a tile is. If the display it was last on has been unplugged, it is centred
on the display that remains rather than clamped against an edge. It is raised when you float it
and again whenever it is focused, and it drops behind the tiles it covers the moment the focus
moves on — so cycling with `SUPER`+arrows never lands you on a tile half-hidden by a window you
have already left. Hyprland keeps a float above the tiles whatever has the focus; the
Accessibility API has a raise action and no lower, so the way down is to raise what the float
covers, and only the tiles it really overlaps are touched. Tiles never overlap each other, so
re-ordering those among themselves is invisible. Activating an application brings all of its
windows forward with it, float included, so the stack is checked against the window server
rather than remembered — a float that comes back up goes straight back down, and one that is
already at the bottom is left alone. Floating windows stay reachable with
`SUPER`+arrows, and they are reached as a **list** rather than by where they are. Two of a size
are centred identically, so they land exactly on top of each other, and no arrow can mean "the
one underneath this one" — geometry has nothing to say about them. So they are not on the grid
at all: they are the workspace's detached windows in the order they were opened, and a direction
with no tile that way lands in that list, at whichever end it arrives from. From there the same
direction walks along it and the opposite direction walks back, and off either end is the tile
the focus came in from — so holding one arrow down goes round tile, detached windows, tile, and
all four directions behave alike. Two detached windows are two presses past the last tile, and
going back is going out reversed: every step has an exact inverse, which is the thing proximity
could never give. Tile to tile is untouched by any of this — that is Hyprland's walk, edge
adjacency and all, and it never answers with a detached window.

**Windows toe leaves alone**: dialogs, sheets, palettes, minimized and natively-fullscreen (see
**Dock swipes** for the one thing that changes about living in one)
windows, and anything that refuses a position or size. Add your own exceptions with `[[float]]`
rules.

## Config

`~/.config/toe/toe.toml` is written on first run and reloaded whenever you save it. `SUPER`+`,`
opens it in nano, in a Terminal.app window; bind `exec` with your own terminal instead if you
would rather. If it fails to parse, the running config is kept and the error is named in the
menu bar item's tooltip — a typo can never leave you without a keyboard. See
[`toe.example.toml`](toe.example.toml), and
[Treat your config as code](#treat-your-config-as-code) for what an `exec` binding can do.

Binding specs parse in both the dash spelling and Omarchy's, so you can paste from either:
`"alt-shift-1"`, `"super+shift+1"` and `"SUPER SHIFT, 1"` are the same binding.

`editconfig`, `reload`, `quit` and the quick menu are bound in code as well as in the file —
`SUPER`+`,`, `SUPER`+`SHIFT`+`R`, `SUPER`+`SHIFT`+`Q`, `SUPER`+`SPACE` and `SUPER`+`K` — so the
ways out exist whether or not your config mentions them. Your config is never rewritten once it is there, so a binding introduced after you
first ran toe would otherwise never reach you: that is how the menu bar item losing its menu left
anyone upgrading with no way to quit but `pkill`. A fallback applies only when the command is
bound nowhere, so rebinding `quit` keeps your key and does not also collect the default, and a
fallback whose own combination you have already used for something else is dropped rather than
registered on top of yours.

Commands: `movefocus`, `swapwindow`, `movewindow`, `workspace`, `movetoworkspace`,
`movetoworkspacesilent`, `killactive`, `togglefloating`, `togglesplit`, `swapsplit`, `exec`,
`reload`, `editconfig`, `menu`, `keybindings`, `quit`.

The TOML parser is a dependency-free subset: tables, arrays of tables, bare and quoted keys,
basic and literal strings, numbers, booleans, arrays and inline tables. No multi-line strings
or dates.

## Development

```sh
make dev-cert  # once — see below
make test      # layout engine, no permissions needed
make run       # build, bundle, relaunch
```

`Sources/ToeCore` is pure geometry with no AppKit or Accessibility dependency, which is what
makes the dwindle port testable headlessly. `Sources/toe` holds everything that touches the
system.

macOS keys Accessibility grants to an app's code signature, so an ad-hoc signature — which
changes on every build — makes macOS re-ask for permission after each rebuild. `make dev-cert`
creates a self-signed `toe-dev` certificate in your login keychain (one password prompt) and
`scripts/bundle.sh` picks it up automatically, giving the bundle a stable identity so the grant
sticks. Without it, signing falls back to ad-hoc and `make reset-perms` plus re-granting is the
way through.

Diagnostics go to the unified log:

```sh
log stream --predicate 'subsystem == "com.clifmeister.toe"' --level info
```

## Not included

By design: no scratchpads, no binding modes, no scripting API, no resize bindings, no window
groups. It is a layout engine and the bindings that drive it.

## License

MIT — see [LICENSE](LICENSE).

Toe.app bundles JetBrainsMono Nerd Font for the quick menu, used under the SIL Open Font License
1.1 — see [`Resources/JetBrainsMonoNerdFont-OFL.txt`](Resources/JetBrainsMonoNerdFont-OFL.txt).
