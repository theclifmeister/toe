/// The config written to ~/.config/toe/toe.toml on first run.
///
/// Values match Omarchy's Hyprland defaults exactly:
///   default/hypr/looknfeel.conf  →  gaps_in = 5, gaps_out = 10, border 2px, dwindle
///                                   preserve_split = true, force_split = 2
///   default/hypr/bindings/tiling.conf → the bindings below
let defaultConfigText = #"""
# toe — The Opinionated Experience
#
# Reloads automatically when you save. If a line does not parse, the running config is kept
# and the error is named in the menu bar item's tooltip, so a typo can never leave you
# keyboardless. SUPER+, opens this file in Visual Studio Code — a binding like any other,
# so point it at the editor you actually use.
#
# This file is code, not just settings: an `exec` binding below runs a shell command, and toe
# picks up a change within about 150 ms of the save. Anything that can write this file can run
# commands as you. It is created mode 600 for that reason — keep it that way.

[general]
# Omarchy's SUPER maps to Option: same physical key position as SUPER on a PC keyboard, and
# it leaves ⌘S ⌘F ⌘T ⌘W ⌘1-9 ⌘Tab alone. Also accepts "cmd" or "ctrl".
super_key = "alt"

# Omarchy: gaps_in = 5, gaps_out = 10
gaps_in  = 5
gaps_out = 10

[dwindle]
# Both of these are Omarchy's settings, and together they are what makes dwindle feel right:
#   preserve_split — a split's orientation is decided once, when the window opens, and never
#                    silently re-derived afterwards.
#   force_split 2  — a new window always takes the right or bottom half of the focused window.
preserve_split = true
force_split    = 2

# SIDEBYSIDE = width > height * split_width_multiplier. Raise it to prefer stacking.
split_width_multiplier = 1.0
# 1.0 is an even split. Clamped to 0.1 ... 1.9.
default_split_ratio    = 1.0
# 0 = even, 1 = favour the new window, 2 = favour the existing one.
split_bias             = 0

[theme]
# An Omarchy theme, by name. Empty is toe's own colours — the [border] and [menu] values below —
# which is what this file has always been, and what it stays until you choose otherwise. Those
# defaults are Tokyo Night's palette already, resolved the way walker resolves it, so nothing
# looks unthemed while this is empty.
#
# A theme wins outright. With a name set here, the *colour* keys in [border] and [menu] are not
# consulted at all; the sizes still are — width, angle, radius, opacity, font_size. Omarchy's own
# theme template sets col.active_border and nothing else, so a theme is exactly that much: the
# focused border takes the accent, flat, and the quick menu takes the background, the foreground
# and the accent.
#
# SUPER+SPACE > Style > Theme is where you get one. toe ships no themes: a theme is somebody
# else's work, and the list you choose from is what is in ~/.config/toe/themes plus what Omarchy
# publishes. Choosing one you have not got downloads it from Omarchy into that folder — palette
# and pictures — and then sets it, so a theme you fetched and a theme you copied in by hand are
# the same thing afterwards.
#
# That download is the only time toe touches the network, along with the list of themes it fetches
# when you open Style > Theme, at most once a day. Nothing at launch, no update check, no
# telemetry; the only host it talks to is github.com. A machine that has never been online has no
# themes to choose from, and the colours below.
#
# The menu rewrites this one line and leaves every other byte of this file alone, so picking a
# theme there and editing it here are the same act. It refuses to write at all if the result would
# not parse.
#
# A theme is a folder: ~/.config/toe/themes/<name>/colors.toml, in Omarchy's own format, plus an
# optional backgrounds/ beside it. Nothing has to be registered — one appears in the menu the
# moment you next open it, and saving its palette recolours the screen the way saving this file
# does. Style > Background appears exactly when that theme has pictures, and SUPER+CTRL+SPACE
# steps through them.
name = ""

[border]
# Highlights the focused window. Omarchy's col.active_border gradient — and what you see when no
# theme is set above, since a theme replaces both stops with one flat accent.
enabled      = true
width        = 2
active_start = "#33ccffee"
active_end   = "#00ff99ee"
angle        = 45
# -1 follows each window's own corner radius, asking the window server for it and falling
# back to the system value for windows that do not report one. 0 is square, or set an
# explicit value.
radius       = -1

[floating]
# The size a window gets when SUPER+T lifts it out of the tree — it is always centred, at
# this fraction of the display, so every floating window is the same shape.
width  = 0.70
height = 0.80
# SUPER+T again grows it to this instead of tiling it; the third press puts it back in the
# tree. Set these to width/height above for a plain two-state toggle.
large_width  = 0.80
large_height = 0.90
# ...except that no floating window is ever wider than this many times its own height. On a
# 32:9 ultrawide a plain 70% would be a letterbox; on a laptop this never comes into play.
max_aspect_ratio = 1.6

[gestures]
# Swallow the Dock's swipe gestures before macOS acts on them. A swipe up would open Mission
# Control, which puts the windows on hidden workspaces — parked off-screen, since macOS has no
# public API for virtual desktops — back on display; a sideways swipe would change the macOS
# Space out from under toe. Ctrl+←/→ still switches Spaces, which is also the way out of a
# fullscreen app now that swiping is not.
swallow_dock_swipes = true

[misc]
# Ctrl+↑ and Ctrl+↓ open the same Mission Control and App Exposé the vertical swipe does. These
# are symbolic hotkeys, resolved inside the window server, so nothing an event tap can do reaches
# them — toe switches them off while it runs and gives them back when it quits. Ctrl+←/→ is left
# alone: it is the way out of a fullscreen app now that swiping is not.
disable_expose_shortcuts = true

# A click on bare wallpaper — the gaps between the tiles count — sweeps every window off the sides
# of the screen, the windows parked off-screen on hidden workspaces along with them, until you
# click again. macOS decides that inside WindowManager rather than from an event a tap could
# swallow, so toe switches the setting itself (the one System Settings › Desktop & Dock calls
# "Click wallpaper to show desktop") and puts it back the way it found it when it quits.
disable_wallpaper_click = true

# ⌘H and ⌘⌥H take an application's windows out of the layout without closing them — the tree
# reflows around the gap and SUPER+arrows cannot reach them again, because they are no longer on
# any workspace. toe puts a hidden application straight back.
prevent_hiding = true

# Where every window was — its workspace, its place in the tree, every split — is written to
# ~/.local/state/toe/session.json and put back when toe starts again, so restarting it costs you
# nothing. Windows are matched on the id the window server gave them, so this is exact rather
# than a guess; a reboot voids those ids and the file is discarded unread. Set false to start
# from an empty workspace every time and keep the *layout* off disk. It is not a blanket switch:
# the theme's current background is remembered in the same directory either way, since that is a
# choice you made rather than a window arrangement toe worked out for you.
restore_session = true

[bar]
# waybar's persistent-workspaces: Omarchy keeps slots 1-5 on the bar even when they are
# empty, dimmed. 0 shows only the workspaces in use; 10 always shows all ten.
persistent_workspaces = 5

[menu]
# SUPER+SPACE opens the quick menu, styled after Omarchy's — the one walker draws for
# `omarchy-menu`. Arrows to move, Enter to choose, Escape to back out. Typing searches the whole
# tree rather than the level you are on, and each hit says which submenu it came from.
# These are its theme's tokens: Omarchy's default (Tokyo Night) resolved the way walker's
# stylesheet resolves them — background, foreground (which is also the border), and the accent
# the selected row's text takes. Which is to say these three are already a theme: setting
# [theme] name = "tokyo-night" above leaves this block looking exactly as it does now, and only
# the border moves. The three are ignored while a theme is set; the sizes below are not.
background = "#1a1b26"
foreground = "#a9b1d6"
accent     = "#7aa2f7"
# The window is the background at 95%, as walker's .box-wrapper is. The search line stays solid.
opacity    = 0.95
# omarchy-menu asks walker for 295 points, and 800 for a list like the keybindings page. The list
# width is walker's; the menu's is not — at 295 the row "Edit configuration" was a point too wide
# to draw whole, and the column that says on or off beside "Run on startup" was four points too
# narrow. 400 fits every row. Both are clamped to the display if it is narrower.
width      = 400
list_width = 800
# walker draws at 18px and so does this. The one measurement here worth changing: the padding,
# the icon size and the gaps are all walker's and are left alone.
font_size  = 18

[binds]
# ── Focus — SUPER + arrows ────────────────────────────────────────────────────
"super-left"  = "movefocus l"
"super-right" = "movefocus r"
"super-up"    = "movefocus u"
"super-down"  = "movefocus d"

# ── Swap windows — SUPER SHIFT + arrows ───────────────────────────────────────
# Omarchy binds swapwindow here, not movewindow: the two windows trade places and the
# layout keeps its shape. Use "movewindow l" instead if you want i3-style reparenting.
"super-shift-left"  = "swapwindow l"
"super-shift-right" = "swapwindow r"
"super-shift-up"    = "swapwindow u"
"super-shift-down"  = "swapwindow d"

# ── Workspaces — SUPER + 1-9,0 ────────────────────────────────────────────────
"super-1" = "workspace 1"
"super-2" = "workspace 2"
"super-3" = "workspace 3"
"super-4" = "workspace 4"
"super-5" = "workspace 5"
"super-6" = "workspace 6"
"super-7" = "workspace 7"
"super-8" = "workspace 8"
"super-9" = "workspace 9"
"super-0" = "workspace 10"

# ── Move window to workspace — SUPER SHIFT + 1-9,0 ────────────────────────────
"super-shift-1" = "movetoworkspace 1"
"super-shift-2" = "movetoworkspace 2"
"super-shift-3" = "movetoworkspace 3"
"super-shift-4" = "movetoworkspace 4"
"super-shift-5" = "movetoworkspace 5"
"super-shift-6" = "movetoworkspace 6"
"super-shift-7" = "movetoworkspace 7"
"super-shift-8" = "movetoworkspace 8"
"super-shift-9" = "movetoworkspace 9"
"super-shift-0" = "movetoworkspace 10"
# Same, without following the window:  "movetoworkspacesilent 3"

# ── Cycling ───────────────────────────────────────────────────────────────────
# next/prev walk only the workspaces in use — the ones with windows on them, plus whatever the
# other displays are showing — so a press never lands on a blank slot.
"super-tab"       = "workspace next"
"super-shift-tab" = "workspace prev"
"super-ctrl-tab"  = "workspace previous"

# ── Windows ───────────────────────────────────────────────────────────────────
"super-w"       = "killactive"
"super-j"       = "togglesplit"
"super-t"       = "togglefloating"

# ── toe itself ────────────────────────────────────────────────────────────────
# The menu bar item is only the workspace strip — waybar's has nothing behind it either — so
# these are the way in to everything toe can do to itself.
# Editing this file is nothing special — it is an `exec`, the same as the launchers below, and
# toe has no editor of its own. Whichever exec below mentions toe.toml is the one the quick menu
# offers as "Edit configuration", so the menu follows this line wherever you point it. It runs
# through /bin/sh, so ~ expands and any editor works:
#   "exec open -a Zed ~/.config/toe/toe.toml"
#   "exec open -e ~/.config/toe/toe.toml"                     # TextEdit, always installed
#   "exec open -na Ghostty --args -e nano ~/.config/toe/toe.toml"
"super-comma"   = "exec open -a \"Visual Studio Code\" ~/.config/toe/toe.toml"
# Saving this file already reloads it; this is the manual way.
"super-shift-r" = "reload"
# Puts every window on a hidden workspace back where it came from on the way out.
"super-shift-q" = "quit"
# The quick menu — Omarchy's SUPER+ALT+SPACE, and the keybindings list it holds. Note that this
# takes ⌥Space and ⌥K away from typing ` ` and ˚ for as long as toe runs.
"super-space"   = "menu"
"super-k"       = "keybindings"
# Omarchy's background key. SUPER+CTRL+SPACE is what its bindings.conf gives to backgrounds —
# there it opens the picker, which here is Style › Background in the menu above, so the key does
# the thing the menu cannot: step to the next picture without stopping to choose one. Does
# nothing until the current theme has a backgrounds/ folder with something in it.
#
# The one binding here with a macOS shortcut behind it: ⌃⌥Space is "select next input source",
# and while that is a symbolic hotkey — resolved inside the window server, ahead of anything toe
# can register — it is switched off unless you have two or more input sources. If you do, and
# this key changes your keyboard instead of your wallpaper, that is why; move it, or turn the
# shortcut off in System Settings › Keyboard › Keyboard Shortcuts › Input Sources.
"super-ctrl-space" = "nextbackground"

# ── Launch ────────────────────────────────────────────────────────────────────
# AppleScript's `new window` reuses the running instance, so the window opens on the current
# workspace without a second app process lingering. `ghostty +new-window` is not supported on
# macOS, and `open -na Ghostty` leaves a zombie instance behind.
"super-enter"       = "exec osascript -e 'tell application \"Ghostty\" to new window'"
"super-shift-enter" = "exec osascript -e 'tell application \"Safari\" to make new document' -e 'tell application \"Safari\" to activate'"
# Chrome instead:
# "super-shift-enter" = "exec open -na \"Google Chrome\" --args --new-window"

# ── Windows that should never be tiled ────────────────────────────────────────
# `app` matches the bundle identifier and accepts *; `title` is a case-insensitive substring.
[[float]]
app = "com.apple.systempreferences"
[[float]]
app = "com.raycast.macos"
[[float]]
app = "com.1password.1password"
[[float]]
app = "com.apple.finder"
title = "Copy"
[[float]]
app = "com.apple.ActivityMonitor"

"""#
