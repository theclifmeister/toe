import Foundation

/// Which view of the menu is on screen. `omarchy-menu keybindings` opens the second one
/// directly, and so does `SUPER`+`K`.
public enum MenuPage: String, Equatable, Sendable {
    case root
    case keybindings
}

/// One row.
public struct MenuItem: Equatable {

    /// Symbolic rather than a codepoint, so ToeCore never learns what a glyph is: the selftest
    /// asserts `.gear`, and the day the icon font changes it is one table in the UI layer that
    /// moves rather than every test that mentions a row.
    public enum Icon: Equatable, Sendable {
        case gear, book, keyboard, pencil, power, toggleOn, toggleOff
    }

    public indirect enum Action: Equatable {
        case submenu([MenuItem])
        case page(MenuPage)
        case run(Command)
        case toggleLoginItem
    }

    public let title: String
    /// Where the row lives, when the list is not showing one level at a time — `Install › Style`.
    /// Only a filtered list sets this: see `MenuState`.
    public let subtitle: String?
    public let icon: Icon?
    /// The second column: `on`/`off` for the login toggle, what it does for a keybinding row.
    public let value: String?
    public let action: Action

    public init(title: String, subtitle: String? = nil, icon: Icon? = nil,
                value: String? = nil, action: Action) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.value = value
        self.action = action
    }

    public func with(subtitle: String?) -> MenuItem {
        MenuItem(title: title, subtitle: subtitle, icon: icon, value: value, action: action)
    }

    /// walker marks the rows that lead somewhere with a trailing `›`, right-aligned.
    public var leadsOn: Bool {
        switch action {
        case .submenu, .page: return true
        default: return false
        }
    }

}

/// What launchd says about starting toe at login. Read, never remembered — see `LoginItem`.
public enum LoginItemState: Equatable, Sendable {
    case on
    case off
    /// Registering would not work, or would disagree with something that already does.
    case unavailable(String)
}

/// The menu's contents.
///
/// Deliberately a function of the state it displays rather than a constant: a "Run on startup"
/// row that shows a remembered value instead of launchd's is a row that will eventually lie.
public enum MenuModel {

    public static func root(loginItem: LoginItemState, bindings: [Binding]) -> [MenuItem] {
        var items: [MenuItem] = []
        // Configure can come out empty — neither of its rows is guaranteed — and a row that
        // leads into an empty level is worse than no row, so the parent goes with it.
        let configure = configure(loginItem: loginItem, bindings: bindings)
        if !configure.isEmpty {
            items.append(MenuItem(title: "Configure", icon: .gear, action: .submenu(configure)))
        }
        items.append(MenuItem(title: "Learn", icon: .book, action: .submenu([
            MenuItem(title: "Keybindings", icon: .keyboard, action: .page(.keybindings)),
        ])))
        items.append(MenuItem(title: "Quit", icon: .power, action: .run(.quit)))
        return items
    }

    /// The Configure level. Also built on its own, by the menu, when throwing the startup toggle
    /// rebuilds the level under the cursor.
    public static func configure(loginItem: LoginItemState, bindings: [Binding]) -> [MenuItem] {
        var rows: [MenuItem] = []
        if let startup = startup(loginItem) { rows.append(startup) }
        if let opener = configOpener(in: bindings) {
            rows.append(MenuItem(title: "Edit configuration", icon: .pencil,
                                 action: .run(opener.command)))
        }
        return rows
    }

    /// The binding that opens the config, if you have one — the row cannot name an editor of its
    /// own without being exactly the hardcoding that was taken out, so it reads your config
    /// instead. Point the binding at Zed and the row opens Zed; move it to another key and the
    /// row follows it there; take the binding out and the row goes too, rather than the menu
    /// offering an editor you never chose. `Command.opensConfig` is the rule, shared with the
    /// label the keybindings list gives the same binding.
    public static func configOpener(in bindings: [Binding]) -> Binding? {
        bindings.first { $0.command.opensConfig }
    }

    /// nil where the toggle cannot work — the row is left out rather than shown dimmed beside a
    /// reason. Even at the 400 points the menu widened to in #74, the second column beside this
    /// title is 133 points: enough for `on` or `off` and nowhere near the reason it would have
    /// to give ("needs /Applications"), so a row that has to explain itself has nowhere to do
    /// it. And a switch you can see but not throw is worse than one that is not offered.
    /// `LoginItem` logs why.
    private static func startup(_ state: LoginItemState) -> MenuItem? {
        switch state {
        case .on:
            return MenuItem(title: "Run on startup", icon: .toggleOn, value: "on",
                            action: .toggleLoginItem)
        case .off:
            return MenuItem(title: "Run on startup", icon: .toggleOff, value: "off",
                            action: .toggleLoginItem)
        case .unavailable:
            return nil
        }
    }

    /// Every binding that is live, grouped the way the README's table groups them.
    ///
    /// Not the config's own order, because there is no such thing: `[binds]` is a TOML table and
    /// `Config.parse` walks it sorted by the binding string, deliberately, so that a warning
    /// about it says the same thing twice running. That is the right answer for a diagnostic and
    /// the wrong one for a page you are meant to learn from — it opens on `SUPER`+`0`. So the
    /// rows are ranked by what they do, and left in the parser's order inside each rank, which
    /// keeps the whole list stable run to run without reading like a hash.
    public static func keybindings(_ bindings: [Binding], superKey: Modifiers) -> [MenuItem] {
        bindings.enumerated()
            .sorted { a, b in
                let (l, r) = (rank(a.element.command), rank(b.element.command))
                return l == r ? a.offset < b.offset : l < r
            }
            .map { _, binding in
                MenuItem(title: ShortcutFormatter.describe(binding, superKey: superKey),
                         icon: nil,
                         value: CommandLabel.describe(binding.command),
                         action: .run(binding.command))
            }
    }

    /// The reading order of the README's table: what you do to the focus, then to a window, then
    /// to a workspace, then to toe itself, and last the bindings that launch something — those
    /// are the ones a user has replaced with their own, so they belong at the bottom.
    private static func rank(_ command: Command) -> Int {
        switch command {
        case .moveFocus:        return 0
        case .swapWindow:       return 1
        case .moveWindow:       return 2
        case .workspace(.index): return 3
        case .moveToWorkspace:  return 4
        case .workspace:        return 5
        case .killActive, .toggleFloating, .toggleSplit, .swapSplit: return 6
        case .menu:             return 7
        case .reload, .quit:    return 8
        case .exec:             return 9
        }
    }
}
