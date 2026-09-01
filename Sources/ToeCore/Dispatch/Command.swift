import Foundation

public enum WorkspaceTarget: Equatable {
    case index(Int)
    case next
    case previous       // the workspace before this one in 1...10
    case former         // `workspace previous` in Hyprland: the last one you were on
}

/// The dispatchers toe implements. Names match Hyprland's so bindings can be copied over —
/// with one exception: `menu` has no Hyprland counterpart, because Omarchy reaches SUPER+SPACE's
/// menu through `exec walker`. toe's is built in, so it gets a dispatcher of its own rather than
/// hiding inside an `exec` string.
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
    case exec(String)
    case reload
    /// The quick menu — toe's own, see the note above.
    case menu

    /// The command written back out in the spelling `CommandParser` accepts, so
    /// `parse(described) == self` for every case. The quick menu shows this beside a binding.
    public var described: String {
        switch self {
        case .moveFocus(let d):     return "movefocus \(d.hyprlandLetter)"
        case .swapWindow(let d):    return "swapwindow \(d.hyprlandLetter)"
        case .moveWindow(let d):    return "movewindow \(d.hyprlandLetter)"
        case .workspace(let t):
            switch t {
            case .index(let n):  return "workspace \(n)"
            case .next:          return "workspace next"
            case .previous:      return "workspace prev"
            case .former:        return "workspace previous"
            }
        case .moveToWorkspace(let n, let follow):
            return follow ? "movetoworkspace \(n)" : "movetoworkspacesilent \(n)"
        case .killActive:       return "killactive"
        case .toggleFloating:   return "togglefloating"
        case .toggleSplit:      return "togglesplit"
        case .swapSplit:        return "swapsplit"
        case .exec(let line):   return "exec \(line)"
        case .reload:           return "reload"
        case .menu:             return "menu"
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
        case "reload":                      return .reload
        case "menu":                        return .menu

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
