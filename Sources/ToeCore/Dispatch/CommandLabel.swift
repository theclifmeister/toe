import Foundation

/// What a command is called, for a reader rather than for a parser.
///
/// The keybindings page shows `SUPER + W  →  Close window`, and the right-hand half is this. It
/// is one of three exhaustive `switch`es over `Command` in the tree — `Coordinator.dispatch` and
/// `MenuModel.rank` are the others — so a new command needs five edits rather than two: the verb
/// in `CommandParser`, the arm in `dispatch`, a label here, a rank on the keybindings page, and a
/// row in `CommandCatalogue`, which is what `toe query commands` and the generated skill file
/// answer with. The compiler catches the first four; the fifth is caught by the selftest only in
/// the direction that matters — every catalogued verb must parse — so a verb added to the parser
/// and left out of the table is a verb the command line will run and never mention.
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
        case .swapWorkspace(let delta): return swapWorkspace(delta)
        case .killActive:           return "Close window"
        case .toggleFloating:       return "Cycle floating"
        case .toggleSplit:          return "Toggle split orientation"
        case .swapSplit:            return "Swap the split"
        case .resizeActive(let dx, let dy): return resize(dx: dx, dy: dy)
        case .growActive(let dx, let dy):   return grow(dx: dx, dy: dy)
        case .exec(let line):
            // The one exec the list can name for you: `SUPER`+`,` read as "Edit the config"
            // while toe owned the command, and a row that reads `Run open -a "Visual Studio
            // Code" ~/.config/toe/…` is a worse answer to the same question. The text comes from
            // the line you bound, not from a command — see `Command.opensConfig`.
            return command.opensConfig ? "Edit the config" : "Run \(ellipsised(line))"
        case .reload:               return "Reload the config"
        case .quit:                 return "Quit toe"
        case .menu(let route):
            if route == .root { return "Open the menu" }
            if route == .keybindings { return "Show the keybindings" }
            // The path, not a name for it: a route names the level it opens, and that level's own
            // breadcrumb is what the user sees a moment later. A table saying "Choose a theme"
            // for `Style › Theme` would be a second name for one place, and the day the level is
            // renamed only one of the two would follow.
            return "Open " + route.path.joined(separator: " › ")
        case .theme(let slug):
            // Titled from the slug, because that is all a label has: toe ships no themes, so
            // there is no table of names to look one up in, and a theme's directory name is the
            // only thing true of it whether it is installed, merely available, or neither.
            guard !slug.isEmpty else { return "Use your own colours" }
            return "Theme: \(Slug.title(slug))"
        case .removeTheme(let slug): return "Remove the theme \(Slug.title(slug))"
        case .background(let file):  return "Background: \(ellipsised(file))"
        case .nextBackground:        return "Next background"
        // Named for what it is for rather than for what it writes. Somebody reading this row in
        // the keybindings list has not got the path in their head, and "the Claude Code skill"
        // is the thing they went looking for.
        case .installSkill:          return "Install the Claude Code skill"
        case .removeSkill:           return "Remove the Claude Code skill"
        }
    }

    /// "Move the split 100 pt right" — where the split goes, not what happens to the window,
    /// because the window is the half of it that depends on which side you are on. Someone who
    /// pressed `=` and watched their window shrink comes to this list to find out why, and the
    /// answer is the split.
    private static func resize(dx: Double, dy: Double) -> String {
        func travel(_ v: Double, _ positive: String, _ negative: String) -> String {
            let n = abs(v)
            let amount = n == n.rounded() ? String(Int(n)) : String(n)
            return "\(amount) pt \(v < 0 ? negative : positive)"
        }
        switch (dx != 0, dy != 0) {
        case (true, false):  return "Move the split " + travel(dx, "right", "left")
        case (false, true):  return "Move the split " + travel(dy, "down", "up")
        case (true, true):   return "Move the splits " + travel(dx, "right", "left")
                                    + " and " + travel(dy, "down", "up")
        case (false, false): return "Move the split nowhere"
        }
    }

    /// "Make the window 100 pt wider" — what happens to the window you are in, which for this
    /// verb is the whole of the meaning.
    private static func grow(dx: Double, dy: Double) -> String {
        func change(_ v: Double, _ more: String, _ less: String) -> String {
            let n = abs(v)
            let amount = n == n.rounded() ? String(Int(n)) : String(n)
            return "\(amount) pt \(v < 0 ? less : more)"
        }
        switch (dx != 0, dy != 0) {
        case (true, false):  return "Make the window " + change(dx, "wider", "narrower")
        case (false, true):  return "Make the window " + change(dy, "taller", "shorter")
        case (true, true):   return "Make the window " + change(dx, "wider", "narrower")
                                    + " and " + change(dy, "taller", "shorter")
        case (false, false): return "Leave the window its size"
        }
    }

    /// "Swap this workspace with the one to its left" — the swap and not the renumbering, which
    /// is only how it is done. What the user sees is their workspace changing places on the bar
    /// with its neighbour, and both keeping their windows.
    private static func swapWorkspace(_ delta: Int) -> String {
        let side = delta < 0 ? "left" : "right"
        let places = abs(delta)
        return places == 1 ? "Swap this workspace with the one to its \(side)"
                           : "Move this workspace \(places) places to the \(side)"
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
