# Toe — The Opinionated Experience

A small native macOS tiling window manager. It brings Hyprland's **dwindle** layout and
[Omarchy](https://omarchy.org)'s defaults to the Mac: one layout, ten workspaces, one set of key
bindings, a gradient border around the focused window and a quick menu. There is nothing to
agonise over — that is the opinion, and it is the whole product.

toe lives in the menu bar as a workspace strip. It has no Dock icon and no window of its own, and
the only permission it needs is Accessibility.

# Bindings
<img width="1728" height="1117" alt="image" src="https://github.com/user-attachments/assets/2256d0c4-884f-4af4-a405-51368390425c" />

# Theme selection
<img width="1392" height="948" alt="Screenshot 2026-09-03 at 18 16 08" src="https://github.com/user-attachments/assets/2383ac0e-97ce-46b3-b626-e54192f6a349" />
<img width="1392" height="948" alt="Screenshot 2026-09-03 at 18 16 20" src="https://github.com/user-attachments/assets/007511fa-eec8-444f-8766-b8afd504a062" />

# Quick menu
<img width="1392" height="948" alt="Screenshot 2026-09-03 at 18 17 33" src="https://github.com/user-attachments/assets/b64c4f20-50a6-42d5-8c53-8379c87aac10" />

## Install

```sh
brew tap theclifmeister/toe https://github.com/theclifmeister/toe
brew install --cask theclifmeister/toe/toe
open /Applications/Toe.app
```

The two-argument `brew tap` is needed because the cask lives in this repository.
`brew upgrade --cask toe` picks up new releases.

On first launch, grant **System Settings → Privacy & Security → Accessibility** when asked. That
is the only permission toe needs.

There is one optional extra. The workspace slide — the screen sliding sideways under a dock
swipe, the way Spaces does — is drawn from a picture of the display, and taking that picture is
**Screen Recording**, a second permission. It is off by default, and it is a gimmick: toe tiles,
focuses and switches exactly the same without it. Turn it on from the quick menu under
**Trigger › Toggle › Workspace slide** (or `slide_on_swipe = true` under `[animations]`) and macOS
asks for the grant then, not before. If you would rather not give it, leave the slide off and
nothing else changes.

### What the defaults assume

Three of the shipped bindings launch an application. toe has no terminal, browser or editor of its
own, so it borrows Omarchy's picks:

| Binding | Opens | If you have not got it |
|---|---|---|
| `SUPER` + `ENTER` | [Ghostty](https://ghostty.org) | `brew install --cask ghostty` |
| `SUPER` + `SHIFT` + `ENTER` | Safari | ships with macOS |
| `SUPER` + `,` | [Visual Studio Code](https://code.visualstudio.com) | `brew install --cask visual-studio-code` |

Each is one line in the config and can point anywhere — see [Configuration](#configuration).
A binding for an application you do not have simply does nothing.

### Start at login

Open the quick menu (`SUPER` + `SPACE`) and choose **Setup › Run on startup**. It registers toe as
a login item, so it also shows up under System Settings › General › Login Items.

From a clone of this repository, `make start-at-login` does the same with a LaunchAgent, and
`make stop-at-login` removes it.

## Using it

`SUPER` is **Option (⌥)** — the same physical key position as SUPER on a PC keyboard, and it
leaves ⌘S, ⌘F, ⌘T, ⌘W, ⌘1-9 and ⌘Tab untouched.

| Binding | Action |
|---|---|
| `SUPER` + `←↑↓→` | Move focus |
| `SUPER` + `SHIFT` + `←↑↓→` | Swap window with its neighbour |
| `SUPER` + `1`…`9`, `0` | Switch to workspace 1…10 |
| `SUPER` + `SHIFT` + `1`…`9`, `0` | Move window to workspace and follow it |
| `SUPER` + `TAB` / `SHIFT`+`TAB` / `CTRL`+`TAB` | Next / previous workspace in use, former workspace |
| `SUPER` + `CTRL` + `SHIFT` + `←` / `→` | Swap this workspace with the one next door, windows and all |
| Sideways swipe on the trackpad | Next / previous workspace in use |
| `SUPER` + `ENTER` | New terminal window |
| `SUPER` + `SHIFT` + `ENTER` | New browser window |
| `SUPER` + `W` | Close window |
| `SUPER` + `J` | Toggle split orientation |
| `SUPER` + `-` / `=` | Make the window 100 pt narrower / wider |
| `SUPER` + `SHIFT` + `-` / `=` | Make it 100 pt shorter / taller |
| `SUPER` + `T` | Cycle floating: 70×80% of the display, 80×90%, back to tiling |
| `SUPER` + `SPACE` | The quick menu |
| `SUPER` + `CTRL` + `SPACE` | The background picker, when the theme has pictures |
| `SUPER` + `SHIFT` + `CTRL` + `SPACE` | The theme picker |
| `SUPER` + `K` | Every binding, in a list |
| `SUPER` + `,` | Edit the config |
| `SUPER` + `SHIFT` + `R` / `Q` | Reload the config / quit toe |
| Drag a tiled window | Swap it with the tile you drag it over |
| Drag a tiled window's edge | Resize it; the neighbours follow when you let go |

**The layout.** A new window splits the focused one and takes the right or bottom half. A split's
orientation is decided once, from the shape of the space it is in, and then kept, so the layout
stays put as windows come and go. Closing a window hands its space to its sibling. Dialogs,
sheets, palettes, minimized and native-fullscreen windows are left alone.

**The menu bar** shows the workspace strip: the workspace you are on as a filled square, every
other workspace in use as its digit, and workspaces 1–5 always present. Click a workspace to
switch to it, or the `T` at the front to open the quick menu.

**The quick menu** (`SUPER` + `SPACE`) mirrors Omarchy's: Learn, Trigger, Style, Setup, Install,
Remove, About and Quit. Arrows move, `ENTER` chooses, `ESC` backs out, and typing searches the
whole tree — type `startup` at the top and *Run on startup* comes back ready to pick.

**Themes.** Style › Theme lists the themes in `~/.config/toe/themes`, and Install › Style › Theme
lists everything Omarchy publishes; choosing one there downloads it and applies it. A theme is a
folder holding Omarchy's `colors.toml` and an optional `backgrounds/`, so one copied from an
Omarchy install works as-is. That download is the only time toe uses the network. Without a
theme, toe's own colours are Tokyo Night's.

**Things toe changes while it runs.** To keep its workspaces intact, toe takes over the Dock's
swipe gestures, switches off `Ctrl`+`↑`/`↓`, turns off "click wallpaper to show desktop" and
macOS's own drag-a-window-to-the-edge tiling, and auto-hides the Dock. Everything is put back when it quits — and restored on the next launch if it
did not get the chance. Each has a switch in the config.

## Configuration

toe writes `~/.config/toe/toe.toml` on first run and reloads it whenever you save. If the file
fails to parse, the running config is kept and the error is named in the menu bar item's tooltip.
Every key is documented in [`toe.example.toml`](toe.example.toml), which is the same file toe
writes.

Most people change nothing. When you do, it is usually one of these:

```toml
[general]
super_key = "alt"       # or "cmd", "ctrl"
gaps_in   = 8
gaps_out  = 15

[binds]
"super-enter"       = "exec open -na Alacritty"
"super-shift-enter" = "exec open -na \"Google Chrome\" --args --new-window"
"super-comma"       = "exec open -a Zed ~/.config/toe/toe.toml"

[[float]]               # windows that should never be tiled
app = "com.apple.ActivityMonitor"
```

Binding specs accept the dash spelling and Omarchy's, so `"alt-shift-1"`, `"super+shift+1"` and
`"SUPER SHIFT, 1"` all mean the same. The commands are `movefocus`, `swapwindow`, `movewindow`,
`workspace`, `movetoworkspace`, `movetoworkspacesilent`, `swapworkspace`, `killactive`,
`togglefloating`, `togglesplit`, `swapsplit`, `growactive`, `resizeactive`, `exec`, `reload`,
`menu`, `keybindings`, `theme`, `removetheme`, `background`, `nextbackground`, `installskill`,
`removeskill` and `quit`.
`growactive <dx> <dy>` grows the focused window by that much; Hyprland's `resizeactive` moves the
split by that much instead, which from a right-hand window is the other way round, and is accepted
for configs copied from Omarchy. `swapworkspace left` / `right` is toe's own: it renumbers two
workspaces rather than moving any window, so a workspace can be shuffled along the menu bar.

Other sections worth knowing about:

- `[border]` and `[menu]` — colours, width, angle, opacity and font size. The colours are ignored
  while `[theme] name` is set.
- `[floating]` — the sizes `SUPER` + `T` cycles through.
- `[gestures]` and `[misc]` — the switches for the Dock swipes, the Mission Control shortcuts, the
  wallpaper click, macOS's edge tiling, Dock auto-hide, un-hiding ⌘H'd apps and restoring the
  layout across restarts.
- `[animations] slide_on_swipe` — slide the screen on a swipe the way Spaces does. Off by
  default because it needs Screen Recording, a second permission; Trigger › Toggle in the quick
  menu flips it.
- `[bar] persistent_workspaces` — how many workspaces always keep a slot on the menu bar.
- `[cli]` — the command line below: whether its socket is opened at all, and whether `exec` and
  `quit` may travel over it. Both are refused by default.

**Treat the config as code.** An `exec` binding runs whatever the file says through `/bin/sh`,
and toe reloads the file within a moment of it changing — so anything that can write it can run
commands as you. toe creates it `0600` and warns in the menu bar if it is later found writable by
others. Symlinking it into a dotfiles repository works fine.

## The command line

`toe` is a command as well as a window manager. Run with a verb, it talks to the copy already
running over a socket at `~/.local/state/toe/toe.sock` — mode `0600`, in a `0700` directory, and
refused to any user but you.

```sh
toe query state                          # what is open, where, and on which workspace
toe query commands                       # every verb dispatch accepts
toe dispatch "workspace 3"
toe dispatch "movetoworkspace 2" "workspace 2"       # several, drawn once at the end
toe dispatch --window app:Safari "movetoworkspace 3"
toe focus app:Ghostty
toe layout save work                     # remember an arrangement
toe layout apply work                    # and put it back, by application rather than window id
toe help
```

Replies are JSON on stdout — `{"ok":true,"result":…}`. A refusal exits 1 with a sentence on
stderr; a mistyped command exits 2 without reaching toe at all. Selectors are `id:`, `app:`,
`bundle:`, `title:` and `workspace:`, and a bare word tries the application first, then the title;
a selector matching more than one window is refused with the candidates listed.

**Getting `toe` onto your `PATH`.** Installed with Homebrew you already have it — the cask
symlinks the binary into Homebrew's `bin`. From source, `make install-cli` does the same into
`$(brew --prefix)/bin`, or wherever `BINDIR` points:

```sh
make install && make install-cli      # or: BINDIR=~/bin make install-cli
```

Either way the link points *into* the bundle rather than at a copy of it: the same binary is the
window manager and the command line, told apart by its first argument. Without a link it is
`/Applications/Toe.app/Contents/MacOS/toe`.

Which means a bare `toe` typed at a prompt would otherwise start a window manager as a child of
your shell — one that takes over from the copy running properly and then dies when you close the
tab. So from a shell, `toe` with no arguments prints the usage; with no terminal at either end,
which is how launchd and `open Toe.app` start it, it is the window manager. `toe agent` runs it in
your shell deliberately.

**Driving toe from an agent.** `toe skill install` writes a Claude Code skill into
`~/.claude/skills/toe/SKILL.md` — the verb table, the selector syntax, and the handful of things
about this window manager that nothing else would tell you: that a workspace is not a macOS Space,
that a fullscreen window suspends half the verbs, that a floating window is the user's. The verb
half is generated from toe's own table, so it cannot drift out of step with the program. The quick
menu has the same row under Install › Claude Code skill, ticked once the file is there, and Remove
takes it away again. `toe skill print` shows the document without writing it anywhere.

`exec` and `quit` do not travel over the socket unless `[cli] allow_exec` / `allow_quit` say so.
`exec` runs a shell line, and a control socket that carried it would hand a shell to everything
that learned to talk to toe.

## From source

```sh
make dev-cert   # once per machine: a stable signing identity so Accessibility survives rebuilds
make test       # layout suite — no permissions, no Xcode needed
make run        # build, sign and relaunch in place, as "Toe Dev"
make install    # same, into /Applications
```

`make run` builds a separate application — `build/ToeDev.app`, "Toe Dev" — so that the copy you are
working on and the one in `/Applications` hold their Accessibility grants separately and neither
launch costs you the other's permission. Grant each once. Only one copy runs at a time: whichever
starts asks the other to quit and waits for it to unstash its windows before taking over.

Diagnostics go to the unified log:

```sh
log stream --predicate 'subsystem == "com.clifmeister.toe"' --level info
```

## Not included

By design: no scratchpads, no binding modes, no window groups, and no scripting language. The
command line above is not one — it is the same verbs the keys send, spelled out loud so something
else can send them. It is a layout engine, the bindings that drive it, and one socket.

## License

MIT — see [LICENSE](LICENSE).

Toe.app bundles JetBrainsMono Nerd Font for the quick menu, used under the SIL Open Font License
1.1 — see [`Resources/JetBrainsMonoNerdFont-OFL.txt`](Resources/JetBrainsMonoNerdFont-OFL.txt).
