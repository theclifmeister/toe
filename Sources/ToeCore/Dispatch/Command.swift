import Foundation

public enum WorkspaceTarget: Equatable {
    case index(Int)
    case next
    case previous       // the workspace before this one in 1...10
    case former         // `workspace previous` in Hyprland: the last one you were on
}

/// The dispatchers toe implements. Names match Hyprland's so bindings can be copied over.
public enum Command: Equatable {
    case moveFocus(Direction)
    case swapWindow(Direction)
    case moveWindow(Direction)
    case workspace(WorkspaceTarget)
    case moveToWorkspace(Int, follow: Bool)
    case killActive
    case toggleFloating
    case toggleSplit
    case swapSplit
    /// `resizeactive <dx> <dy>`: how far the focused window's splits move, in points, right and
    /// down when positive. Hyprland's numbers and Hyprland's meaning — see
    /// `DwindleLayout.resizeActive` for why the split moves rather than the window growing.
    case resizeActive(dx: Double, dy: Double)
    /// `growactive <dx> <dy>`: how much the focused window grows, in points, whichever side of
    /// its splits it is on — so `=` is always bigger and `-` always smaller. toe's own verb,
    /// bound by default; `resizeactive` is kept for configs copied from Omarchy.
    case growActive(dx: Double, dy: Double)
    case exec(String)
    case reload
    /// The quick menu, at a level. One case with a route rather than one per door: the
    /// keybindings view *is* the menu on another page — same panel, same filter, same keys — and
    /// `menu theme` is the same panel again, opened three rows in. Separate cases would give
    /// `dispatch` several arms with one body between them.
    case menu(MenuRoute)
    case quit
    /// An Omarchy theme, by slug — `omarchy-theme-set`. Empty clears it and hands your own
    /// `[border]` and `[menu]` colours back, which is why the argument is the one in the parser
    /// that may be missing: `theme none` would be wrong, since `none` is a directory somebody
    /// could legitimately name.
    case theme(String)
    /// Deletes a theme's folder from `~/.config/toe/themes` — `omarchy-theme-remove`. The one
    /// destructive thing the menu can do, which is why it takes a slug rather than a path: the
    /// name is joined onto a directory that is about to be removed, and `Slug.make` is what
    /// stands between that join and a name with a `/` or a `..` in it.
    case removeTheme(String)
    /// A picture from the current theme's `backgrounds/`, by file name.
    case background(String)
    /// `omarchy-theme-bg-next`.
    case nextBackground
}

public extension Command {

    /// True for the `exec` that opens the config file.
    ///
    /// There is no `editconfig` command any more — opening the file is an `exec` like the ones
    /// that launch a terminal or a browser — so the two places that want to know which binding
    /// edits your config read the line rather than a command name: any `exec` that mentions the
    /// config file is taken to be it. `MenuModel.configOpener` finds the menu row that way, and
    /// `CommandLabel` names the row in the keybindings list that way, so both follow your config
    /// instead of a command toe used to own.
    ///
    /// A shell line that merely touches the file for some other reason matches too. That is the
    /// price of not asking you to declare which binding is the editor one.
    var opensConfig: Bool {
        guard case .exec(let line) = self else { return false }
        return line.contains(Config.fileName)
    }

    /// True for the two verbs that change a window's size. They answer for one another where
    /// the question is "has this config got resizing on a key" — see `Config.bound(_:in:)`.
    var resizes: Bool {
        switch self {
        case .resizeActive, .growActive: return true
        default:                         return false
        }
    }

    /// Whether the quick menu stays up after running this.
    ///
    /// Every row used to dismiss the panel, which is right for almost all of them: `exec` brings
    /// another application forward, `quit` tears the process down, and a window command acts on a
    /// window you cannot see past the menu. Choosing a theme is the exception, and for two
    /// reasons that arrived separately and point the same way.
    ///
    /// The first is that a theme you have not got has to be *fetched*, and the fetching is
    /// reported by that row filling — so closing the menu would dismiss the only surface saying
    /// anything about the slowest thing toe does.
    ///
    /// The second is that a theme recolours the menu itself. Picking one and staying put means
    /// the panel restyles under the cursor, so arrowing down the list and pressing return is a
    /// way of *looking* at themes rather than a commitment to one — which is what the list is
    /// for. Closing on each pick made trying three themes three trips through
    /// `SUPER`+`SPACE` › `Style` › `Theme`.
    ///
    /// `.theme("")` — `Your own colours` — is in here for the same reason: it is the way back,
    /// and a way back you have to reopen the menu to use is not much of one.
    ///
    /// Backgrounds deliberately still close. A wallpaper is behind the panel rather than in it,
    /// so there is nothing to restyle and nothing being fetched; the picture is the whole of what
    /// changed, and the menu is what is in front of it.
    var keepsMenuOpen: Bool {
        switch self {
        // Removing one is the same argument from the other side: the row leaves the list under
        // the cursor, and that disappearance is the whole of what toe says about it.
        case .theme, .removeTheme: return true
        default:                   return false
        }
    }
}

public enum CommandError: Error, CustomStringConvertible {
    case unknown(String)
    case badArgument(String, String)
    case missingArgument(String)

    public var description: String {
        switch self {
        case .unknown(let c): return "unknown command '\(c)'"
        case .badArgument(let c, let a): return "'\(c)': bad argument '\(a)'"
        case .missingArgument(let c): return "'\(c)' needs an argument"
        }
    }
}

public enum CommandParser {

    public static func parse(_ raw: String) throws -> Command {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Hyprland writes `movefocus, l`; we accept that and the plain `movefocus l`.
        let head = trimmed.prefix { !$0.isWhitespace && $0 != "," }
        let name = String(head).lowercased()
        var argument = String(trimmed.dropFirst(head.count))
            .trimmingCharacters(in: .whitespaces)
        if argument.hasPrefix(",") {
            argument = String(argument.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        func direction() throws -> Direction {
            guard !argument.isEmpty else { throw CommandError.missingArgument(name) }
            guard let d = Direction(argument) else { throw CommandError.badArgument(name, argument) }
            return d
        }

        func workspaceIndex() throws -> Int {
            guard !argument.isEmpty else { throw CommandError.missingArgument(name) }
            guard let n = Int(argument), (1...WorkspaceManager.workspaceCount).contains(n) else {
                throw CommandError.badArgument(name, argument)
            }
            return n
        }

        switch name {
        case "movefocus", "focus":          return .moveFocus(try direction())
        case "swapwindow", "swap":          return .swapWindow(try direction())
        case "movewindow", "move":          return .moveWindow(try direction())
        case "killactive", "close":         return .killActive
        case "togglefloating", "float":     return .toggleFloating
        case "togglesplit":                 return .toggleSplit
        case "swapsplit":                   return .swapSplit
        case "resizeactive", "growactive":
            // Two numbers, and only two: Hyprland's `exact` and percentage forms are not ported,
            // because a tile's size is the tree's to decide and an exact size has no meaning in
            // it. They fail as a bad argument rather than an unknown verb so the warning points
            // at the right word. Commas and spaces both separate, as `resizeactive, 100 0`
            // copied from an Omarchy config has both.
            let parts = argument.split { $0.isWhitespace || $0 == "," }.map(String.init)
            guard !parts.isEmpty else { throw CommandError.missingArgument(name) }
            guard parts.count == 2, let dx = Double(parts[0]), let dy = Double(parts[1]),
                  dx.isFinite, dy.isFinite
            else { throw CommandError.badArgument(name, argument) }
            return name == "growactive" ? .growActive(dx: dx, dy: dy) : .resizeActive(dx: dx, dy: dy)
        case "reload":                      return .reload
        case "quit", "exit":                return .quit

        // Spelled after `omarchy-theme-set` and `omarchy-theme-bg-next`.
        //
        // `theme` is the one verb here whose argument may be absent, and it means *clear the
        // theme* rather than being an error — see `Command.theme`. It is also the one that
        // slugifies its argument at the door rather than at the far end, so that `theme "Tokyo
        // Night"` copied out of an Omarchy config finds the same directory, and so that no
        // un-slugified string can reach the code that writes this name back into your config.
        case "theme":                       return .theme(Slug.make(argument))
        // `omarchy theme remove <name>`, one word rather than two because a binding's value is a
        // verb and its argument, and `theme` had already taken the first word.
        case "removetheme", "theme-remove":
            guard !argument.isEmpty else { throw CommandError.missingArgument(name) }
            return .removeTheme(Slug.make(argument))
        // Not slugified: a background is a file name, with an extension and whatever case the
        // photographer gave it.
        case "background", "bg":
            guard !argument.isEmpty else { throw CommandError.missingArgument(name) }
            return .background(argument)
        case "nextbackground", "bgnext", "background-next":
            return .nextBackground

        // Spelled the way `omarchy-menu` and `omarchy-menu keybindings` are invoked, so a
        // binding can be read across from an Omarchy config without translating it.
        // Routes are Omarchy's, aliases included: `omarchy-menu toggle background` and
        // `toggle settings` are lines out of its own bindings and its own menu file, and they
        // open the same levels here.
        case "menu":
            switch argument.lowercased() {
            case "", "root", "go":                    return .menu(.root)
            case "keybindings", "keys":               return .menu(.keybindings)
            case "learn":                             return .menu(.learn)
            case "style":                             return .menu(.style)
            case "theme", "themes":                   return .menu(.theme)
            case "background", "backgrounds", "wallpaper": return .menu(.background)
            // `trigger` and `toggles` opened the borrowed `Trigger › Toggle` level, which held
            // one switch and is gone; the switch is a Setup row now, so the aliases follow it
            // there rather than becoming an error in a config that was right when it was written.
            case "setup", "settings", "trigger", "toggle", "toggles": return .menu(.setup)
            case "install":                           return .menu(.install)
            case "remove", "uninstall":               return .menu(.remove)
            default:                    throw CommandError.badArgument(name, argument)
            }
        case "keybindings":                 return .menu(.keybindings)

        case "exec", "exec-and-forget":
            guard !argument.isEmpty else { throw CommandError.missingArgument(name) }
            return .exec(argument)

        case "workspace":
            switch argument.lowercased() {
            case "": throw CommandError.missingArgument(name)
            case "e+1", "next", "+1": return .workspace(.next)
            case "e-1", "prev", "-1": return .workspace(.previous)
            case "previous", "former", "back": return .workspace(.former)
            default: return .workspace(.index(try workspaceIndex()))
            }

        case "movetoworkspace":
            return .moveToWorkspace(try workspaceIndex(), follow: true)
        case "movetoworkspacesilent":
            return .moveToWorkspace(try workspaceIndex(), follow: false)

        default:
            throw CommandError.unknown(name)
        }
    }
}
