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
        case paintbrush, droplet, image
    }

    public indirect enum Action: Equatable {
        case submenu([MenuItem])
        case page(MenuPage)
        case run(Command)
        case toggleLoginItem
        /// A row that says something and does nothing when you press it — "Fetching Omarchy's
        /// themes…". The alternative was leaving the level looking like a short list rather than
        /// an unfinished one, which is the sort of thing you stare at wondering if it is broken.
        case note
    }

    public let title: String
    /// Where the row lives, when the list is not showing one level at a time — `Install › Style`.
    /// Only a filtered list sets this: see `MenuState`.
    public let subtitle: String?
    public let icon: Icon?
    /// The second column: `on`/`off` for the login toggle, what it does for a keybinding row.
    public let value: String?
    /// How full to draw the row, 0…1, or nil for the ordinary case of a row that is not doing
    /// anything. Set on the theme being downloaded, and the reason a download is visible at all
    /// now that the menu bar has stopped saying so.
    ///
    /// On `MenuItem` rather than on the theme rows specifically, because the drawing is generic:
    /// `MenuView` fills whatever row carries this, so the next thing that takes time — and there
    /// will be one — does not need a second way of showing it.
    public let progress: Double?
    public let action: Action

    public init(title: String, subtitle: String? = nil, icon: Icon? = nil,
                value: String? = nil, progress: Double? = nil, action: Action) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.value = value
        self.progress = progress
        self.action = action
    }

    public func with(subtitle: String?) -> MenuItem {
        MenuItem(title: title, subtitle: subtitle, icon: icon, value: value, progress: progress,
                 action: action)
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

/// What the Style level needs to draw itself.
///
/// A value rather than four parameters, because it is threaded from the Coordinator through
/// `QuickMenu` to here unchanged, and because it is rebuilt every time the menu opens — that is
/// what makes a theme folder you created a moment ago appear without a reload.
///
/// Every field defaults to empty, and that is not a convenience for tests: it is what a machine
/// that has never fetched anything actually has. The Theme level still draws — `Your own colours`
/// is a real row, and it is the one that is current.
public struct StyleMenu: Equatable {
    /// Themes on disk — the ones that can be chosen without waiting for anything.
    public var themes: [ThemeRef]
    /// Themes Omarchy publishes that this machine does not have. Choosing one downloads it.
    public var available: [RemoteTheme]
    /// True while the catalogue is being fetched, so the level can say so rather than looking
    /// like a list that happens to be short.
    public var fetching: Bool
    /// The theme in effect. nil is toe's own colours.
    public var current: String?
    /// The current theme's `backgrounds/`, in cycle order.
    public var backgrounds: [String]
    public var currentBackground: String?
    /// The theme being fetched right now, if one is. Its row fills as the pictures arrive, which
    /// is the whole of what toe says about a download since the menu bar stopped saying it.
    public var downloading: ThemeDownload?

    public init(themes: [ThemeRef] = [], available: [RemoteTheme] = [], fetching: Bool = false,
                current: String? = nil,
                backgrounds: [String] = [], currentBackground: String? = nil,
                downloading: ThemeDownload? = nil) {
        self.themes = themes
        self.available = available
        self.fetching = fetching
        self.current = current
        self.backgrounds = backgrounds
        self.currentBackground = currentBackground
        self.downloading = downloading
    }
}

/// The menu's contents.
///
/// Deliberately a function of the state it displays rather than a constant: a "Run on startup"
/// row that shows a remembered value instead of launchd's is a row that will eventually lie.
public enum MenuModel {

    public static func root(loginItem: LoginItemState, bindings: [Binding],
                            style: StyleMenu = StyleMenu()) -> [MenuItem] {
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
        // Omarchy's own order — Learn, then Style — with Quit last by toe's rule. Unlike
        // Configure, Style is never conditional: three themes ship, so the level it leads to
        // cannot come out empty.
        items.append(MenuItem(title: "Style", icon: .paintbrush, action: .submenu(MenuModel.style(style))))
        items.append(MenuItem(title: "Quit", icon: .power, action: .run(.quit)))
        return items
    }

    /// Omarchy's `Style` level, minus the parts toe has no analogue for.
    public static func style(_ style: StyleMenu) -> [MenuItem] {
        var rows = [MenuItem(title: "Theme", icon: .droplet, action: .submenu(themes(style)))]
        // The Configure rule, one level down: a row that leads into an empty level is worse than
        // no row. Background appears exactly when the current theme has pictures — which means
        // when one was downloaded with it, or when you put some there yourself.
        if !style.backgrounds.isEmpty {
            rows.append(MenuItem(title: "Background", icon: .image,
                                 action: .submenu(MenuModel.backgrounds(style))))
        }
        return rows
    }

    /// Every theme toe can see, with the one in effect marked.
    ///
    /// Marked with a value rather than by opening the level with the cursor already on it:
    /// walker preselects, and matching that needs a new mutating entry point on `MenuState`. The
    /// value column is how the startup toggle already shows its state, so this is the rule the
    /// menu has rather than a new one.
    public static func themes(_ style: StyleMenu) -> [MenuItem] {
        var rows = style.themes.map { theme in
            MenuItem(title: theme.name,
                     value: theme.slug == style.current ? "current" : nil,
                     action: .run(.theme(theme.slug)))
        }

        // Then what Omarchy publishes and this machine does not have. The size is the disclosure:
        // these run from a third of a megabyte to nine, and a row that downloaded nine megabytes
        // without having said so first would be a row that surprised you.
        rows += style.available.map { theme in
            // The one being fetched trades its size for a count and starts filling: the size was
            // there to tell you what you were about to spend, and once you have spent it the
            // question has become how much longer.
            let download = style.downloading?.slug == theme.slug ? style.downloading : nil
            return MenuItem(title: theme.name,
                            value: download?.label ?? ByteSize.describe(theme.bytes),
                            progress: download?.fraction,
                            action: .run(.theme(theme.slug)))
        }

        // Said rather than left to be inferred from a short list. Deliberately after the themes
        // and before the way out, which is where the rows it is waiting for will appear.
        if style.fetching {
            rows.append(MenuItem(title: "Fetching Omarchy's themes…", action: .note))
        }

        // Last rather than first, so the list reads as a list of themes. Short, because a value
        // in the second column takes its width out of the title's.
        rows.append(MenuItem(title: "Your own colours",
                             value: style.current == nil ? "current" : nil,
                             action: .run(.theme(""))))
        return rows
    }

    /// The current theme's pictures, and the row that steps through them.
    ///
    /// Shaped exactly like the Theme level above: no icons, and the row that is an *action*
    /// rather than a choice comes last, the way `Your own colours` does. Both rules are there
    /// because a level reads as a list only when its rows line up — an icon on one row of four
    /// indents that row's text past the other three, and it was the only row in the menu that
    /// did it.
    public static func backgrounds(_ style: StyleMenu) -> [MenuItem] {
        var rows = style.backgrounds.map { file in
            // The whole file name, extension and all: strip it and a folder holding city.jpg
            // beside city.png gets two rows that say the same thing.
            MenuItem(title: file,
                     value: file == style.currentBackground ? "current" : nil,
                     action: .run(.background(file)))
        }
        rows.append(MenuItem(title: "Next background", action: .run(.nextBackground)))
        return rows
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
    /// to a workspace, then to how it all looks, then to toe itself, and last the bindings that
    /// launch something — those are the ones a user has replaced with their own, so they belong
    /// at the bottom.
    private static func rank(_ command: Command) -> Int {
        switch command {
        case .moveFocus:        return 0
        case .swapWindow:       return 1
        case .moveWindow:       return 2
        case .workspace(.index): return 3
        case .moveToWorkspace:  return 4
        case .workspace:        return 5
        case .killActive, .toggleFloating, .toggleSplit, .swapSplit: return 6
        case .theme, .background, .nextBackground: return 7
        case .menu:             return 8
        case .reload, .quit:    return 9
        case .exec:             return 10
        }
    }
}
