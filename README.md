# toe — The Omarchy Experience

A small native macOS window manager that reproduces [Omarchy](https://omarchy.org)'s
window management: Hyprland's **dwindle** layout, Omarchy's key bindings, ten workspaces,
and nothing else.

AeroSpace gets most of the way there, but it is i3-style — explicit splits, with container
normalization that flattens the tree dwindle depends on — so the one thing it cannot
reproduce is the layout itself. toe's tiler is a direct port of Hyprland's
`CHyprDwindleLayout`, with Omarchy's settings (`preserve_split = true`, `force_split = 2`)
as the defaults.

## What it does

| Binding | Action |
|---|---|
| `SUPER` + `←↑↓→` | Move focus |
| `SUPER` + `SHIFT` + `←↑↓→` | Swap window with its neighbour |
| `SUPER` + `1`…`9`, `0` | Switch to workspace 1…10 |
| `SUPER` + `SHIFT` + `1`…`9`, `0` | Move window to workspace and follow it |
| `SUPER` + `TAB` / `SHIFT`+`TAB` / `CTRL`+`TAB` | Next / previous / former workspace |
| `SUPER` + `ENTER` | New terminal window |
| `SUPER` + `SHIFT` + `ENTER` | New browser window |
| `SUPER` + `W` | Close window |
| `SUPER` + `J` | Toggle split orientation |
| `SUPER` + `SHIFT` + `V` | Toggle floating |

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
▪ 2 3 4 5 7
```

`[bar] persistent_workspaces` sets how many keep a slot: `0` shows only the ones in use, `10`
always shows all ten.

Clicking a workspace switches to it, as Omarchy's `on-click: activate` does. Right-click —
or left-click the padding at either end — to open the menu, which breaks each workspace down
into the applications living there:

```
▪ Workspace 1
      Ghostty  ×2
      Safari  ×2
  Workspace 4
      Google Chrome
────────────────────
Config loaded
```

Rows are live: click a workspace to switch to it, or an application to focus its window —
including one on a hidden workspace, which brings that workspace forward first. The list is
built when the menu opens, so nothing is maintained while it is closed.

## Install

```sh
make install          # builds, ad-hoc signs, copies to /Applications
open /Applications/Toe.app
make start-at-login   # optional
```

Grant **System Settings → Privacy & Security → Accessibility** when asked. That single
permission is all toe needs.

`make run` builds and launches in place without installing. `make test` runs the layout suite.

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
- Directional focus is **edge adjacency**, not nearest-centre: a window qualifies only if its
  opposing edge lines up with yours within 2px, computed on un-gapped node boxes. Ties go to
  the most recently focused window.

## Design notes

**Workspaces.** macOS has no API for putting a window on a virtual desktop without private
SkyLight calls, so hidden workspaces park their windows far off-screen and restore their exact
frames on return — the same approach AeroSpace takes. The trade-off is that stashed windows
remain visible to Cmd-Tab and Mission Control, and Cmd-Tabbing to one can pull it back onto the
current workspace.

**Hotkeys** use Carbon's `RegisterEventHotKey`, deliberately not a `CGEventTap`. A tap would
receive every keystroke you type; Carbon hotkeys only ever deliver the exact combinations toe
registers.

**Electron and Chromium apps** (Chrome, VS Code, Slack) and the JetBrains IDEs ignore or
animate programmatic resizes while `AXEnhancedUserInterface` is set. toe clears it around each
frame write and restores it afterwards, which is what makes those apps tile.

**Apps that fight back.** Chromium, Electron and JetBrains apps re-apply their own remembered
geometry a beat after a window opens, clobbering the frame toe just wrote, so toe re-asserts the
layout when a window moves or resizes behind its back. That is bounded at three attempts: an app
whose minimum size exceeds its tile (Safari will not go narrower than ~574px) is written once and
then left alone rather than fought with forever. The same mechanism snaps a window back when you
drag it out of its tile.

**Windows toe leaves alone**: dialogs, sheets, palettes, minimized and natively-fullscreen
windows, and anything that refuses a position or size. Add your own exceptions with `[[float]]`
rules.

## Config

`~/.config/toe/toe.toml` is written on first run and reloaded whenever you save it. If it
fails to parse, the running config is kept and the error appears in the menu bar item — a typo
can never leave you without a keyboard. See [`toe.example.toml`](toe.example.toml).

Binding specs parse in both spellings, so you can paste from an AeroSpace config or an Omarchy
one: `"alt-shift-1"`, `"super+shift+1"` and `"SUPER SHIFT, 1"` are the same binding.

Commands: `movefocus`, `swapwindow`, `movewindow`, `workspace`, `movetoworkspace`,
`movetoworkspacesilent`, `killactive`, `togglefloating`, `togglesplit`, `swapsplit`, `exec`,
`reload`.

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
