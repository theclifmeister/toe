import Foundation

/// One verb, described for somebody who has never seen toe's config.
///
/// `sample` is not decoration. It is a line that must parse, and the selftest parses every one
/// of them — so a verb described here and misspelled, or given an argument it does not take, is
/// a test failure rather than a sentence a language model will believe. It is also where
/// `takesWindow` comes from, which keeps this table from claiming a target the dispatcher would
/// refuse.
public struct CommandDescriptor: Equatable, Sendable {
    public let verb: String
    public let aliases: [String]
    /// What goes after the verb, in the shape a caller should type it, or nil for the verbs
    /// that take nothing.
    public let argument: String?
    public let summary: String
    public let sample: String

    public init(verb: String, aliases: [String] = [], argument: String? = nil,
                summary: String, sample: String) {
        self.verb = verb
        self.aliases = aliases
        self.argument = argument
        self.summary = summary
        self.sample = sample
    }

    /// Whether `--window` means anything for this verb — asked of the command the sample parses
    /// to, so the answer is the dispatcher's own and not a second opinion about it.
    public var takesWindow: Bool {
        (try? CommandParser.parse(sample))?.acceptsTarget ?? false
    }

    public var usage: String {
        argument.map { "\(verb) \($0)" } ?? verb
    }
}

/// One verb as JSON — `toe query commands`.
///
/// A projection rather than making `CommandDescriptor` itself `Codable`, because the field that
/// matters most to a caller is the one the descriptor computes: whether `--window` works. A
/// synthesised encoding would quietly leave it out.
public struct CommandReport: Codable, Equatable, Sendable {
    public var verb: String
    public var aliases: [String]
    public var argument: String?
    /// Whether `dispatch --window` may point this verb at a window other than the focused one.
    public var window: Bool
    public var summary: String
    public var example: String
}

public extension CommandDescriptor {
    var report: CommandReport {
        CommandReport(verb: verb, aliases: aliases, argument: argument,
                      window: takesWindow, summary: summary, example: sample)
    }
}

/// The saved layout profiles, and where they live — so a caller that wants to read or edit one
/// by hand is not left guessing at the directory.
public struct LayoutsReport: Codable, Equatable, Sendable {
    public var directory: String
    public var layouts: [String]

    public init(directory: String, layouts: [String]) {
        self.directory = directory
        self.layouts = layouts
    }
}

/// Every verb `CommandParser` accepts, as a table.
///
/// This exists because the caller on the other end of the socket cannot read the config file to
/// find out what toe can do — and because the alternative, letting a model infer the vocabulary
/// from Hyprland's documentation, produces confident calls to verbs toe does not have. `toe
/// query commands` is the answer to "what can I say", and the skill document is generated from
/// this same table, so the two cannot disagree.
///
/// Ordered the way `MenuModel.rank` orders the keybindings page — focus, then windows, then
/// workspaces, then how it all looks, then toe itself — because that is the order somebody
/// learns them in.
public enum CommandCatalogue {

    public static let entries: [CommandDescriptor] = [
        CommandDescriptor(verb: "movefocus", aliases: ["focus"], argument: "l|r|u|d",
                          summary: "Move the focus to the window in that direction.",
                          sample: "movefocus l"),
        CommandDescriptor(verb: "swapwindow", aliases: ["swap"], argument: "l|r|u|d",
                          summary: "Trade places with the window in that direction.",
                          sample: "swapwindow r"),
        CommandDescriptor(verb: "movewindow", aliases: ["move"], argument: "l|r|u|d",
                          summary: "Move the focused window that way in the tree, or to the next monitor.",
                          sample: "movewindow r"),
        CommandDescriptor(verb: "killactive", aliases: ["close"],
                          summary: "Close the window.",
                          sample: "killactive"),
        CommandDescriptor(verb: "togglefloating", aliases: ["float"],
                          summary: "Step the window round the floating cycle: tiled, floating, larger, tiled.",
                          sample: "togglefloating"),
        CommandDescriptor(verb: "togglesplit",
                          summary: "Flip the focused window's split between side-by-side and stacked.",
                          sample: "togglesplit"),
        CommandDescriptor(verb: "swapsplit",
                          summary: "Swap the two halves of the focused window's split.",
                          sample: "swapsplit"),
        CommandDescriptor(verb: "growactive", argument: "<dx> <dy>",
                          summary: "Grow the window by that many points; negative shrinks it.",
                          sample: "growactive 100 0"),
        CommandDescriptor(verb: "resizeactive", argument: "<dx> <dy>",
                          summary: "Move the window's split by that many points — Hyprland's verb, "
                                 + "where growactive is toe's.",
                          sample: "resizeactive 100 0"),
        CommandDescriptor(verb: "workspace", argument: "1-10 | next | prev | previous",
                          summary: "Show a workspace. `previous` is the one you were on last.",
                          sample: "workspace 3"),
        CommandDescriptor(verb: "movetoworkspace", argument: "1-10",
                          summary: "Send the window to that workspace and follow it there.",
                          sample: "movetoworkspace 3"),
        CommandDescriptor(verb: "movetoworkspacesilent", argument: "1-10",
                          summary: "Send the window to that workspace and stay where you are.",
                          sample: "movetoworkspacesilent 3"),
        CommandDescriptor(verb: "swapworkspace", argument: "left|right|<±n>",
                          summary: "Trade this workspace's number with its neighbour's. Nothing on "
                                 + "screen moves; the strip reorders.",
                          sample: "swapworkspace left"),
        CommandDescriptor(verb: "theme", argument: "<name>",
                          summary: "Wear an Omarchy theme, fetching it first if this machine has "
                                 + "not got it. No argument hands your own colours back.",
                          sample: "theme tokyo-night"),
        CommandDescriptor(verb: "removetheme", aliases: ["theme-remove"], argument: "<name>",
                          summary: "Delete a theme's folder from ~/.config/toe/themes.",
                          sample: "removetheme tokyo-night"),
        CommandDescriptor(verb: "background", aliases: ["bg"], argument: "<file>",
                          summary: "Put one of the current theme's pictures up.",
                          sample: "background city.jpg"),
        CommandDescriptor(verb: "nextbackground", aliases: ["bgnext", "background-next"],
                          summary: "Step to the next picture.",
                          sample: "nextbackground"),
        CommandDescriptor(verb: "installskill",
                          summary: "Write the Claude Code skill into ~/.claude/skills/toe.",
                          sample: "installskill"),
        CommandDescriptor(verb: "removeskill",
                          summary: "Take that skill file away again.",
                          sample: "removeskill"),
        CommandDescriptor(verb: "menu", argument: "[root|keybindings|style|theme|background|setup|install|remove]",
                          summary: "Open the quick menu, at a level.",
                          sample: "menu theme"),
        CommandDescriptor(verb: "reload",
                          summary: "Re-read toe.toml and re-tile everything.",
                          sample: "reload"),
        CommandDescriptor(verb: "exec", aliases: ["exec-and-forget"], argument: "<shell line>",
                          summary: "Run a shell command. Refused over the socket unless "
                                 + "[cli] allow_exec is on.",
                          sample: "exec open -a Safari"),
        CommandDescriptor(verb: "quit", aliases: ["exit"],
                          summary: "Stop toe, putting every hidden workspace's windows back first. "
                                 + "Refused over the socket unless [cli] allow_quit is on.",
                          sample: "quit"),
    ]

    /// The verbs a caller may not send over the socket without saying so in the config first,
    /// and the setting that lets each through. See `CLIConfig`.
    public static func gate(_ command: Command) -> (key: String, reason: String)? {
        switch command {
        case .exec:
            return ("cli.allow_exec",
                    "`exec` runs a shell command as you, so the socket refuses it by default — "
                    + "set allow_exec = true under [cli] if you want it")
        case .quit:
            return ("cli.allow_quit",
                    "`quit` stops toe, and a caller that stops toe cannot start it again — "
                    + "set allow_quit = true under [cli] if you want it")
        default:
            return nil
        }
    }
}
