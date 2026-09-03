import Foundation

/// What a command is called, for a reader rather than for a parser.
///
/// The keybindings page shows `SUPER + W  →  Close window`, and the right-hand half is this. It
/// is the second exhaustive `switch` over `Command` in the tree — `Coordinator.dispatch` is the
/// other — so a new command now needs three edits rather than two: the verb in `CommandParser`,
/// the arm in `dispatch`, and a label here. The compiler catches a missing label; nothing but a
/// reader catches a bad one.
public enum CommandLabel {

    public static func describe(_ command: Command) -> String {
        switch command {
        case .moveFocus(let d):     return "Move focus \(d.rawValue)"
        case .swapWindow(let d):    return "Swap window \(d.rawValue)"
        case .moveWindow(let d):    return "Move window \(d.rawValue)"
        case .workspace(let t):     return workspace(t)
        case .moveToWorkspace(let n, let follow):
            return follow ? "Move window to workspace \(n)"
                          : "Move window to workspace \(n), staying here"
        case .killActive:           return "Close window"
        case .toggleFloating:       return "Cycle floating"
        case .toggleSplit:          return "Toggle split orientation"
        case .swapSplit:            return "Swap the split"
        case .exec(let line):
            // The one exec the list can name for you: `SUPER`+`,` read as "Edit the config"
            // while toe owned the command, and a row that reads `Run open -a "Visual Studio
            // Code" ~/.config/toe/…` is a worse answer to the same question. The text comes from
            // the line you bound, not from a command — see `Command.opensConfig`.
            return command.opensConfig ? "Edit the config" : "Run \(ellipsised(line))"
        case .reload:               return "Reload the config"
        case .quit:                 return "Quit toe"
        case .menu(let page):
            switch page {
            case .root:        return "Open the menu"
            case .keybindings: return "Show the keybindings"
            }
        case .theme(let slug):
            // Titled from the slug, because that is all a label has: toe ships no themes, so
            // there is no table of names to look one up in, and a theme's directory name is the
            // only thing true of it whether it is installed, merely available, or neither.
            guard !slug.isEmpty else { return "Use your own colours" }
            return "Theme: \(Slug.title(slug))"
        case .background(let file):  return "Background: \(ellipsised(file))"
        case .nextBackground:        return "Next background"
        }
    }

    private static func workspace(_ target: WorkspaceTarget) -> String {
        switch target {
        case .index(let n): return "Workspace \(n)"
        case .next:         return "Next workspace in use"
        case .previous:     return "Previous workspace in use"
        case .former:       return "The workspace you were on"
        }
    }

    /// A shell line can be any length, and the keybindings page lays its second column out to
    /// the widest entry — so one `exec` binding could set the width of every row. Cut it here,
    /// where the number is visible, rather than leaving the drawing to cope.
    static let execLimit = 44

    private static func ellipsised(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > execLimit else { return trimmed }
        return trimmed.prefix(execLimit - 1) + "…"
    }
}
