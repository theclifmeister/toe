import Foundation

/// The quick menu's contents.
///
/// Compiled in rather than configurable, which is the same call the README's "Not included" list
/// makes about a scripting API: toe is a layout engine and the bindings that drive it, and a menu
/// you have to configure is a scripting API with a nicer name.
///
/// The shape follows Omarchy's `omarchy-menu` — a top-level "Go" that drills into submenus — with
/// the entries adapted to macOS. Omarchy's Install, Remove, Update and Learn are pacman, AUR and
/// Arch documentation, so they have no counterpart here; Learn's `Keybindings` survives, under
/// About, where it is generated from the live config.
public enum MenuTree {

    public static func root(_ c: MenuContext) -> MenuEntry {
        MenuEntry(id: "root", title: "Go", kind: .submenu([
            .submenu("windows", "Windows", icon: .section(.windows),
                     keywords: ["window", "switch", "focus", "jump"], windows(c)),
            .submenu("workspaces", "Workspaces", icon: .section(.workspaces),
                     keywords: ["workspace", "desktop", "move"], workspaces(c)),
            .submenu("layout", "Layout", icon: .section(.layout),
                     keywords: ["split", "float", "tile", "dwindle"], layout(c)),
            .submenu("style", "Style", icon: .section(.style),
                     keywords: ["theme", "colour", "color", "border", "gaps"], style(c)),
            .submenu("setup", "Setup", icon: .section(.setup),
                     keywords: ["config", "settings", "preferences"], setup(c)),
            .submenu("system", "System", icon: .section(.system),
                     keywords: ["lock", "sleep", "restart", "shutdown", "power"], system()),
            .submenu("about", "About", icon: .section(.about),
                     keywords: ["version", "help", "keybindings"], about(c)),
        ]))
    }

    // MARK: - Windows

    /// The focused workspace's windows flat at the top, because that is what you nearly always
    /// want, with everything else one level down.
    public static func windows(_ c: MenuContext) -> [MenuEntry] {
        var entries: [MenuEntry] = []

        let here = c.workspace(c.focusedWorkspace)?.apps ?? []
        for app in here {
            entries.append(windowRow(app, workspace: c.focusedWorkspace, showWorkspace: false))
        }

        let elsewhere = c.workspaces.filter { $0.index != c.focusedWorkspace && !$0.isEmpty }
        if !elsewhere.isEmpty {
            var rows: [MenuEntry] = []
            for workspace in elsewhere {
                for app in workspace.apps {
                    rows.append(windowRow(app, workspace: workspace.index, showWorkspace: true))
                }
            }
            entries.append(.submenu("windows.elsewhere", "On other workspaces",
                                    icon: .section(.workspaces),
                                    keywords: ["hidden", "all"], rows))
        }

        if entries.isEmpty {
            entries.append(.info("windows.none", "No windows"))
        }
        return entries
    }

    private static func windowRow(_ app: AppSummary, workspace: Int, showWorkspace: Bool) -> MenuEntry {
        // `Safari  ×2` is the spelling the menu bar already uses for a grouped app.
        let title = app.windowCount > 1 ? "\(app.name)  ×\(app.windowCount)" : app.name
        let detail = showWorkspace ? "Workspace \(workspace)" : app.windowTitle
        return .action("windows.\(app.representativeWindow)", title,
                       .revealWindow(app.representativeWindow),
                       detail: detail,
                       icon: .runningApp(pid: app.pid),
                       keywords: [app.windowTitle, showWorkspace ? nil : "Workspace \(workspace)"]
                           .compactMap { $0 })
    }

    // MARK: - Workspaces

    /// All ten, always — deliberately *not* filtered through `bar.persistent_workspaces`. That
    /// setting exists to keep the menu bar strip short; a navigator wants stable row positions so
    /// muscle memory works, and switching to an empty workspace is a legitimate thing to want.
    public static func workspaces(_ c: MenuContext) -> [MenuEntry] {
        var entries: [MenuEntry] = []

        for index in 1...WorkspaceManager.workspaceCount {
            let summary = c.workspace(index)
            let count = summary?.windowCount ?? 0
            let isFocused = index == c.focusedWorkspace
            var detail = count == 0 ? "empty" : (count == 1 ? "1 window" : "\(count) windows")
            if let name = summary?.monitorName, !isFocused { detail += " · \(name)" }
            entries.append(.action("workspaces.\(index)", "Workspace \(index)",
                                   .command(.workspace(.index(index))),
                                   detail: isFocused
                                       ? c.shortcut(for: .workspace(.index(index)))
                                       : detail,
                                   icon: .workspace(index: index, filled: isFocused),
                                   isOn: isFocused))
        }

        // Named for what they do, not for how Hyprland spells them. There is a genuine trap in
        // `CommandParser`: `workspace prev` is index − 1 while `workspace previous` is the last
        // one you were on. The menu must not inherit that confusion.
        entries.append(.action("workspaces.next", "Next workspace", .command(.workspace(.next)),
                               detail: c.shortcut(for: .workspace(.next)),
                               icon: .symbol("arrow.right")))
        entries.append(.action("workspaces.prev", "Previous workspace",
                               .command(.workspace(.previous)),
                               detail: c.shortcut(for: .workspace(.previous)),
                               icon: .symbol("arrow.left"),
                               keywords: ["before"]))
        entries.append(.action("workspaces.former", "Back to last visited",
                               .command(.workspace(.former)),
                               detail: c.shortcut(for: .workspace(.former)),
                               icon: .symbol("arrow.uturn.backward"),
                               keywords: ["former", "toggle"]))

        entries.append(moveWindowSubmenu(c, follow: true))
        entries.append(moveWindowSubmenu(c, follow: false))
        return entries
    }

    private static func moveWindowSubmenu(_ c: MenuContext, follow: Bool) -> MenuEntry {
        let rows = (1...WorkspaceManager.workspaceCount).map { index in
            MenuEntry.action("workspaces.move\(follow ? "" : "silent").\(index)",
                             "Workspace \(index)",
                             .command(.moveToWorkspace(index, follow: follow)),
                             detail: c.shortcut(for: .moveToWorkspace(index, follow: follow)),
                             icon: .workspace(index: index, filled: index == c.focusedWorkspace),
                             isEnabled: index != c.focusedWorkspace)
        }
        var entry = MenuEntry.submenu(follow ? "workspaces.move" : "workspaces.movesilent",
                                      follow ? "Move window to…" : "Send window to…",
                                      icon: .symbol(follow ? "arrow.right.square"
                                                           : "arrow.right.to.line"),
                                      keywords: follow ? ["send", "throw"]
                                                       : ["silent", "stay", "without following"],
                                      rows)
        entry.isEnabled = c.hasFocusedWindow
        return entry
    }

    // MARK: - Layout

    /// Only what toe actually has. No resize rows, no window groups, no fullscreen or monocle —
    /// there is no `Command` for any of them and the README says as much out loud. `movefocus` is
    /// left out too: four rows that move focus, offered while you are already holding a menu open,
    /// are hotkey territory. So is `movewindow`, which is the deliberately non-default i3-style
    /// reparenting variant and stays a config choice.
    public static func layout(_ c: MenuContext) -> [MenuEntry] {
        let enabled = c.hasFocusedWindow
        var entries: [MenuEntry] = [
            .action("layout.togglesplit", "Toggle split orientation", .command(.toggleSplit),
                    detail: c.shortcut(for: .toggleSplit), icon: .symbol("rectangle.split.2x1"),
                    keywords: ["rotate", "horizontal", "vertical"], isEnabled: enabled),
            .action("layout.swapsplit", "Swap the two halves", .command(.swapSplit),
                    detail: c.shortcut(for: .swapSplit),
                    icon: .symbol("arrow.left.arrow.right.square"),
                    keywords: ["mirror", "flip"], isEnabled: enabled),
            .action("layout.togglefloating", "Toggle floating", .command(.toggleFloating),
                    detail: c.shortcut(for: .toggleFloating), icon: .symbol("macwindow"),
                    keywords: ["float", "untile"], isEnabled: enabled),
            .action("layout.killactive", "Close window", .command(.killActive),
                    detail: c.shortcut(for: .killActive), icon: .symbol("xmark.square"),
                    keywords: ["quit", "kill"], isEnabled: enabled),
        ]

        let swaps = Direction.allCases.map { direction in
            MenuEntry.action("layout.swap.\(direction.rawValue)", direction.label,
                             .command(.swapWindow(direction)),
                             detail: c.shortcut(for: .swapWindow(direction)),
                             icon: .symbol(arrowSymbol(direction)),
                             isEnabled: enabled)
        }
        var swap = MenuEntry.submenu("layout.swap", "Swap window with neighbour",
                                     icon: .symbol("arrow.up.arrow.down.square"),
                                     keywords: ["move", "exchange"], swaps)
        swap.isEnabled = enabled
        entries.append(swap)
        return entries
    }

    private static func arrowSymbol(_ d: Direction) -> String {
        switch d {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        }
    }

    // MARK: - Style

    /// Omarchy's Style menu rewrites config and reloads; so does this. Picking a theme writes
    /// `[border]` in toe.toml and `ConfigWatcher` does the rest, which is why nothing here has to
    /// hold any state — `BorderTheme.matching` reads the tick straight back off the live config.
    public static func style(_ c: MenuContext) -> [MenuEntry] {
        let active = BorderTheme.matching(c.config.border)
        let themes = BorderTheme.all.map { theme in
            MenuEntry.action("style.theme.\(theme.id)", theme.name, .applyBorderTheme(theme),
                             icon: .gradient(start: theme.activeStart, end: theme.activeEnd),
                             isOn: theme.id == active?.id)
        }

        // Gaps are a separate group on purpose. In Omarchy `looknfeel.conf` is shared across every
        // theme and only the colours change, so a theme that also moved your gaps would be
        // inventing a relationship the reference does not have.
        let gaps = GapsPreset.all.map { preset in
            MenuEntry.action("style.gaps.\(preset.id)", preset.name,
                             .applyGaps(inner: preset.inner, outer: preset.outer),
                             detail: "\(preset.inner) / \(preset.outer)",
                             icon: .symbol("square.dashed"),
                             isOn: c.config.gaps.inner == Double(preset.inner)
                                 && c.config.gaps.outer == Double(preset.outer))
        }

        return [
            .submenu("style.theme", "Theme", icon: .section(.style),
                     keywords: ["colour", "color", "gradient", "border"], themes),
            .submenu("style.gaps", "Gaps", icon: .symbol("square.dashed"),
                     keywords: ["spacing", "padding", "margin"], gaps),
            .action("style.border", "Show focus border",
                    .setBorderEnabled(!c.config.border.enabled),
                    detail: c.config.border.enabled ? "on" : "off",
                    icon: .symbol("square.on.square.dashed"),
                    keywords: ["outline", "highlight"],
                    isOn: c.config.border.enabled),
        ]
    }

    // MARK: - Setup

    public static func setup(_ c: MenuContext) -> [MenuEntry] {
        var entries: [MenuEntry] = [
            // No $EDITOR: toe is launched by launchd or Finder, so its environment has none, and
            // recovering it through a login shell would still leave a second guess about which
            // terminal to run it in — a choice that lives only inside an opaque `exec` string.
            // Opening the file is one guess, and it is the user's own.
            .action("setup.config", "Open config…", .reveal(.configFile),
                    detail: "~/.config/toe/toe.toml", icon: .symbol("doc.text"),
                    keywords: ["toml", "edit", "settings"]),
            .action("setup.folder", "Reveal config folder", .reveal(.configFolder),
                    icon: .symbol("folder"), keywords: ["finder"]),
            .action("setup.reload", "Reload config", .command(.reload),
                    detail: c.shortcut(for: .reload), icon: .symbol("arrow.clockwise")),
        ]

        switch c.startAtLogin {
        case .legacyLaunchAgent:
            entries.append(.action("setup.legacylaunchagent",
                                   "Started by a LaunchAgent — remove it",
                                   .removeLegacyLaunchAgent,
                                   detail: "make start-at-login",
                                   icon: .symbol("exclamationmark.triangle"),
                                   keywords: ["login", "startup", "plist"]))
        case .on, .off:
            let on = c.startAtLogin == .on
            entries.append(.action("setup.startatlogin", "Start toe at login",
                                   .setStartAtLogin(!on),
                                   detail: on ? "on" : "off",
                                   icon: .symbol("power.circle"),
                                   keywords: ["startup", "boot"],
                                   isOn: on))
        case .unavailable:
            break
        }

        entries.append(.action("setup.accessibility", "Accessibility settings…",
                               .reveal(.accessibilitySettings),
                               icon: .symbol("lock.shield"),
                               keywords: ["permission", "privacy", "grant"]))
        return entries
    }

    // MARK: - System

    public static func system() -> [MenuEntry] {
        var entries = SystemAction.allCases.map { action in
            MenuEntry.action("system.\(action.rawValue)", action.title, .system(action),
                             icon: .symbol(systemSymbol(action)),
                             keywords: systemKeywords(action))
        }
        entries.append(.action("system.restarttoe", "Restart toe", .restartToe,
                               icon: .symbol("arrow.triangle.2.circlepath"),
                               keywords: ["relaunch"]))
        entries.append(.action("system.quittoe", "Quit toe", .quitToe,
                               icon: .symbol("xmark.circle"), keywords: ["exit"]))
        return entries
    }

    private static func systemSymbol(_ a: SystemAction) -> String {
        switch a {
        case .lock:         return "lock"
        case .sleepDisplay: return "display"
        case .sleep:        return "moon"
        case .logOut:       return "rectangle.portrait.and.arrow.right"
        case .restart:      return "restart"
        case .shutDown:     return "power"
        }
    }

    private static func systemKeywords(_ a: SystemAction) -> [String] {
        switch a {
        case .lock:         return ["screen", "secure"]
        case .sleepDisplay: return ["screen", "off", "monitor"]
        case .sleep:        return ["suspend"]
        case .logOut:       return ["logout", "sign out"]
        case .restart:      return ["reboot"]
        case .shutDown:     return ["shutdown", "off", "halt"]
        }
    }

    /// The two-row question a hierarchical menu asks instead of a dialog. Pushed by the host when
    /// an action says it `needsConfirmation`, so it exists only while the question is on screen.
    ///
    /// Cancel comes first, and is a label rather than an action, so the row a fresh level preselects
    /// is one that does nothing: ENTER pressed twice in quick succession cannot restart your Mac.
    /// You have to move down to the row that acts, or press ESC to back out.
    public static func confirmation(_ action: SystemAction) -> [MenuEntry] {
        [
            .info("confirm.no", "Cancel — or press ESC", icon: .symbol("xmark.circle")),
            .action("confirm.yes", action.confirmationVerb, .system(action),
                    icon: .symbol("exclamationmark.triangle")),
        ]
    }

    // MARK: - About

    public static func about(_ c: MenuContext) -> [MenuEntry] {
        // Omarchy's Learn → Keybindings, generated from the live config so it is always accurate.
        // Each row *runs* its command rather than merely describing it, and this is the one honest
        // place for a raw `exec` shell string to be shown.
        let keys = c.config.bindings.map { binding in
            MenuEntry.action("about.bind.\(binding.source)", binding.describedShortcut,
                             .command(binding.command),
                             detail: binding.command.described,
                             icon: .symbol("keyboard"),
                             keywords: [binding.command.described, binding.source])
        }

        return [
            .action("about.version", "toe \(c.version)",
                    .copyToClipboard("toe \(c.version)"),
                    detail: "copy", icon: .section(.about),
                    keywords: ["version", "build"]),
            .submenu("about.keybindings", "Keybindings", icon: .symbol("keyboard"),
                     keywords: ["shortcuts", "learn", "bindings"], keys),
            .action("about.repo", "toe on GitHub",
                    .openURL("https://github.com/theclifmeister/toe"),
                    icon: .symbol("link"), keywords: ["source", "code"]),
            .action("about.issues", "Report an issue",
                    .openURL("https://github.com/theclifmeister/toe/issues"),
                    icon: .symbol("exclamationmark.bubble"), keywords: ["bug"]),
            .action("about.omarchy", "Omarchy", .openURL("https://omarchy.org"),
                    icon: .symbol("link"), keywords: ["reference"]),
            .action("about.dwindle", "Hyprland's dwindle layout",
                    .openURL("https://wiki.hyprland.org/Configuring/Dwindle-Layout/"),
                    icon: .symbol("link"), keywords: ["hyprland", "tiling"]),
        ]
    }
}
