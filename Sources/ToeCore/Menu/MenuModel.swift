import Foundation

/// Which view of the menu is on screen. `omarchy-menu keybindings` opens the second one
/// directly, and so does `SUPER`+`K`.
public enum MenuPage: String, Equatable, Sendable {
    case root
    case keybindings
}

/// Where a `menu` binding opens the quick menu.
///
/// Omarchy's menu is one tree with many doors into it — `omarchy-menu toggle background` opens
/// at `style.background`, `toggle system` at the power rows — and its default bindings use four
/// of them. toe had two doors, `root` and `keybindings`, so the two keys an Omarchy user reaches
/// for to change how their desktop looks did not open the menu at all.
///
/// The path is titles rather than ids because toe's rows have no ids: `MenuState.rebuild` already
/// walks the tree by title, for the menu that changes while you are looking at it, so opening at
/// a level is that same walk with the titles handed in rather than remembered. A path that no
/// longer resolves — `Style › Background` on a theme with no pictures — stops where it can and
/// leaves you one rung up, which is the behaviour `rebuild` already had to have.
public struct MenuRoute: Equatable, Sendable {
    public let page: MenuPage
    public let path: [String]

    public init(page: MenuPage = .root, path: [String] = []) {
        self.page = page
        self.path = path
    }

    public static let root = MenuRoute()
    public static let keybindings = MenuRoute(page: .keybindings)
    public static let learn = MenuRoute(path: ["Learn"])
    public static let style = MenuRoute(path: ["Style"])
    public static let theme = MenuRoute(path: ["Style", "Theme"])
    public static let background = MenuRoute(path: ["Style", "Background"])
    public static let trigger = MenuRoute(path: ["Trigger"])
    public static let toggle = MenuRoute(path: ["Trigger", "Toggle"])
    public static let setup = MenuRoute(path: ["Setup"])
    public static let install = MenuRoute(path: ["Install"])
    public static let remove = MenuRoute(path: ["Remove"])
}

/// One row.
public struct MenuItem: Equatable {

    /// Symbolic rather than a codepoint, so ToeCore never learns what a glyph is: the selftest
    /// asserts `.gear`, and the day the icon font changes it is one table in the UI layer that
    /// moves rather than every test that mentions a row.
    public enum Icon: Equatable, Sendable {
        case gear, book, keyboard, pencil, power, toggleOn, toggleOff
        case rocket, sliders
        case paintbrush, droplet, image
        case download, trash, info, globe
    }

    public indirect enum Action: Equatable {
        case submenu([MenuItem])
        case page(MenuPage)
        case run(Command)
        case toggleLoginItem
        /// The Trigger › Toggle row for `animations.slide_on_swipe`. Its own case rather than a
        /// `.run`, for the reason the login toggle has one: the row's value flips under the
        /// cursor and the menu stays open, which no `Command` does.
        case toggleSlide
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
    /// The second column: `on`/`off` for the login toggle, what it does for a keybinding row, a
    /// `✓` on the choice already in effect.
    public let value: String?
    /// How full to draw the row, 0…1, or nil for the ordinary case of a row that is not doing
    /// anything. Set on the theme being downloaded, and the reason a download is visible at all
    /// now that the menu bar has stopped saying so.
    ///
    /// On `MenuItem` rather than on the theme rows specifically, because the drawing is generic:
    /// `MenuView` fills whatever row carries this, so the next thing that takes time — and there
    /// will be one — does not need a second way of showing it.
    public let progress: Double?
    /// Omarchy's `disabled` guard: the row stays listed but goes dim, takes a `✓`, and can no
    /// longer be selected — the cursor steps over it, a click does not take it, Return does
    /// nothing, and a search omits it.
    ///
    /// It exists for one job, and the job is the reason the Install level is worth having:
    /// software you already have reads as *installed* rather than vanishing from the list it was
    /// installed from, so the list stays a catalogue of what toe can fetch rather than a list
    /// that gets shorter every time you use it.
    public let isDisabled: Bool
    public let action: Action

    public init(title: String, subtitle: String? = nil, icon: Icon? = nil,
                value: String? = nil, progress: Double? = nil, isDisabled: Bool = false,
                action: Action) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.value = value
        self.progress = progress
        self.isDisabled = isDisabled
        self.action = action
    }

    /// The same row as a search hit: it gains the path it was found at and loses its icon.
    ///
    /// Losing the icon is the point. One level of the tree is a handful of rows that mostly
    /// carry a glyph, so the icons form a column and the titles start after it. A search mixes
    /// levels, and most of what it turns up — a theme, a wallpaper, a keybinding — never had an
    /// icon, so that column is a column no longer: a few rows indent while the rest do not, and
    /// the eye reads the ragged left edge before it reads any of the titles. Dropping the glyph
    /// costs a hint that the subtitle now gives better, and buys back the straight edge.
    public func foundAt(path: String?) -> MenuItem {
        MenuItem(title: title, subtitle: path, icon: nil, value: value, progress: progress,
                 isDisabled: isDisabled, action: action)
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

/// What the Style, Install and Remove levels need to draw themselves.
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
    /// Omarchy's published catalogue, whole: the ones this machine has as well as the ones it
    /// does not. Filtering it is the menu's job rather than the Coordinator's, because the two
    /// levels that read it want opposite halves — `Style › Theme` offers what is here, and
    /// `Install › Style › Theme` lists everything and dims what is here.
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
///
/// The tree follows Omarchy's — the same names at the same depth, in the same order — and the
/// rule for what is missing is Omarchy's own `when` guard: a row whose condition fails is not
/// listed, and a submenu whose visible descendants have all gone goes with them. That is why
/// there is no `Style › Menu Bar` (its two rows upstream are Position, which macOS fixes, and
/// Transparency, which is not toe's menu bar to style) and no `System` (Omarchy's is a power
/// menu for the machine). What is left should read to an Omarchy user as their own menu with the
/// Linux taken out, rather than as a different menu that borrowed some names.
public enum MenuModel {

    /// Omarchy's "this is the current choice" marker: a `✓` appended to the label. toe puts it in
    /// the second column instead, because that column already exists and right-aligning it keeps
    /// the titles lined up — but the glyph is the same one, and it means the same thing on a
    /// theme, a background and an already-installed row.
    public static let checkmark = "✓"

    public static func root(loginItem: LoginItemState, bindings: [Binding],
                            style: StyleMenu = StyleMenu(),
                            version: String? = nil,
                            slideOnSwipe: Bool = false) -> [MenuItem] {
        // Omarchy's root order, with the rows toe has no analogue for left out: Apps, **Learn**,
        // **Trigger**, **Style**, **Setup**, **Install**, **Remove**, Update, **About**, System.
        // Quit is toe's own and goes last, after everything ported.
        var items: [MenuItem] = [
            MenuItem(title: "Learn", icon: .book, action: .submenu(learn())),
            MenuItem(title: "Trigger", icon: .rocket,
                     action: .submenu(trigger(slideOnSwipe: slideOnSwipe))),
            MenuItem(title: "Style", icon: .paintbrush, action: .submenu(MenuModel.style(style))),
        ]
        // Setup can come out empty — neither of its rows is guaranteed — and a row that leads
        // into an empty level is worse than no row, so the parent goes with it. That is Omarchy's
        // rule for a submenu whose children have all failed their `when`, applied here by hand
        // because toe's levels are built rather than filtered.
        let setupRows = setup(loginItem: loginItem, bindings: bindings)
        if !setupRows.isEmpty {
            items.append(MenuItem(title: "Setup", icon: .gear, action: .submenu(setupRows)))
        }
        let installRows = install(style)
        if !installRows.isEmpty {
            items.append(MenuItem(title: "Install", icon: .download, action: .submenu(installRows)))
        }
        let removeRows = remove(style)
        if !removeRows.isEmpty {
            items.append(MenuItem(title: "Remove", icon: .trash, action: .submenu(removeRows)))
        }
        // Omarchy's About opens a window with the branding in it; toe has no window to open and
        // one fact to report, so the row *is* the fact — the version in the second column, and
        // nothing to press. Left out entirely when there is no version to show, which is what a
        // debug build run straight out of `.build` has.
        if let version {
            items.append(MenuItem(title: "About", icon: .info, value: version, action: .note))
        }
        items.append(MenuItem(title: "Quit", icon: .power, action: .run(.quit)))
        return items
    }

    /// Omarchy's `Learn` level: the keybindings, then the manuals.
    ///
    /// Three of upstream's nine links survive. `toe` stands where `learn.omarchy` does — the
    /// system's own manual — and Omarchy's is kept because toe ships its defaults and fetches
    /// its themes, Hyprland's because the layout in the middle of toe is a port of theirs and
    /// `dwindle`, `preserve_split` and `force_split` are documented there and nowhere else. Arch,
    /// Neovim, Bash, Tmux, Herdr and the Discord are about a machine this is not running on.
    public static func learn() -> [MenuItem] {
        [
            MenuItem(title: "Keybindings", icon: .keyboard, action: .page(.keybindings)),
            MenuItem(title: "toe", icon: .globe,
                     action: .run(.exec("open https://github.com/theclifmeister/toe"))),
            MenuItem(title: "Omarchy", icon: .globe,
                     action: .run(.exec("open https://omarchy.org/manual/"))),
            MenuItem(title: "Hyprland", icon: .globe,
                     action: .run(.exec("open https://wiki.hypr.land/"))),
        ]
    }

    /// Omarchy's `Trigger` level: Emoji, Reminder, Capture, Transcode, Share, **Toggle**,
    /// Hardware, Speed Test. One survives. The rest are Linux tools — an emoji picker, ffmpeg,
    /// a share sheet, a touchpad switch — that a Mac either has of its own or has no need of, so
    /// they fail their `when` here the way an upstream row does on a machine without the
    /// hardware. Toggle stays because it holds a row toe can honour, and a level with one live
    /// descendant is listed: that is the Setup rule read the other way round.
    public static func trigger(slideOnSwipe: Bool) -> [MenuItem] {
        [MenuItem(title: "Toggle", icon: .sliders, action: .submenu(toggles(slideOnSwipe: slideOnSwipe)))]
    }

    /// Omarchy's `Trigger › Toggle` level — where upstream keeps every switch that is on or off
    /// *right now*: Stay Awake, Notifications, Screensaver, Nightlight, Menu Bar, and the
    /// Hyprland ones, Workspace Layout and Window Gaps. None of those ten has a Mac analogue
    /// toe can throw from here yet, so the level opens with toe's own row, where an Omarchy
    /// user would go looking for a switch. (Run on startup is under Setup, not here, on
    /// purpose: it is how toe *starts*, like upstream's Direct Boot, not what is on at the
    /// moment.) Also built on its own, by the menu, when throwing the switch rebuilds the level
    /// under the cursor.
    public static func toggles(slideOnSwipe: Bool) -> [MenuItem] {
        [MenuItem(title: "Workspace slide",
                  icon: slideOnSwipe ? .toggleOn : .toggleOff,
                  value: slideOnSwipe ? "on" : "off",
                  action: .toggleSlide)]
    }

    /// Omarchy's `Style` level, minus the parts toe has no analogue for.
    public static func style(_ style: StyleMenu) -> [MenuItem] {
        var rows = [MenuItem(title: "Theme", icon: .droplet, action: .submenu(themes(style)))]
        // The Setup rule, one level down: a row that leads into an empty level is worse than no
        // row. Background appears exactly when the current theme has pictures — which means when
        // one was downloaded with it, or when you put some there yourself.
        if !style.backgrounds.isEmpty {
            rows.append(MenuItem(title: "Background", icon: .image,
                                 action: .submenu(MenuModel.backgrounds(style))))
        }
        return rows
    }

    /// The themes on this machine, with the one in effect marked.
    ///
    /// Installed only. A theme that has to be fetched first is under `Install › Style › Theme`,
    /// where Omarchy keeps it — the split costs toe the one list it used to have and buys the
    /// thing the split is for: `Style › Theme` is a list of things that happen instantly, and
    /// nothing in it can start a nine-megabyte download.
    ///
    /// Marked with a value rather than by opening the level with the cursor already on it:
    /// walker preselects, and matching that needs a new mutating entry point on `MenuState`. The
    /// value column is how the startup toggle already shows its state, so this is the rule the
    /// menu has rather than a new one.
    public static func themes(_ style: StyleMenu) -> [MenuItem] {
        var rows = style.themes.map { theme in
            MenuItem(title: theme.name,
                     value: theme.slug == style.current ? checkmark : nil,
                     action: .run(.theme(theme.slug)))
        }

        // Last rather than first, so the list reads as a list of themes. Short, because a value
        // in the second column takes its width out of the title's.
        rows.append(MenuItem(title: "Your own colours",
                             value: style.current == nil ? checkmark : nil,
                             action: .run(.theme(""))))
        return rows
    }

    /// Omarchy's `Install` level. Upstream it holds sixteen submenus; toe can fetch one kind of
    /// thing, so it holds `Style › Theme` and the two levels above it exist to put that row
    /// where an Omarchy user's hands expect to find it.
    ///
    /// Empty — and so absent from the root — until the catalogue has been fetched once. A
    /// machine that has never had a network has nothing to install and says so by not offering.
    public static func install(_ style: StyleMenu) -> [MenuItem] {
        let rows = installableThemes(style)
        guard !rows.isEmpty else { return [] }
        return [MenuItem(title: "Style", icon: .paintbrush, action: .submenu([
            MenuItem(title: "Theme", icon: .droplet, action: .submenu(rows)),
        ]))]
    }

    /// Everything Omarchy publishes: what you have, dimmed, and what you do not, priced.
    ///
    /// The size is the disclosure — these run from a third of a megabyte to nine, and a row that
    /// downloaded nine megabytes without having said so first would be a row that surprised you.
    public static func installableThemes(_ style: StyleMenu) -> [MenuItem] {
        let have = Set(style.themes.map(\.slug))
        var rows = style.available.map { theme -> MenuItem in
            guard !have.contains(theme.slug) else {
                // Omarchy's `disabled`: listed, dim, ticked, unselectable. The action is left on
                // the row rather than swapped for a `.note` because the row still *is* the thing
                // it describes; it is the guard that says you cannot have it again.
                return MenuItem(title: theme.name, value: checkmark, isDisabled: true,
                                action: .run(.theme(theme.slug)))
            }
            // The one being fetched trades its size for a count and starts filling: the size was
            // there to tell you what you were about to spend, and once you have spent it the
            // question has become how much longer.
            let download = style.downloading?.slug == theme.slug ? style.downloading : nil
            return MenuItem(title: theme.name,
                            value: download?.label ?? ByteSize.describe(theme.bytes),
                            progress: download?.fraction,
                            action: .run(.theme(theme.slug)))
        }

        // Said rather than left to be inferred from a short list. Deliberately last, which is
        // where the rows it is waiting for will appear.
        if style.fetching {
            rows.append(MenuItem(title: "Fetching Omarchy's themes…", action: .note))
        }
        return rows
    }

    /// Omarchy's `Remove` level. Upstream it is the mirror of Install and hides with `when` what
    /// is not there to remove; toe has one removable kind of thing, and no themes of its own, so
    /// this is every folder in `~/.config/toe/themes` — the ones fetched from the catalogue and
    /// the ones you wrote yourself alike, because on disk there is no difference between them.
    ///
    /// No `✓` on the theme in effect. In a list called Remove a tick would read as *this one is
    /// already gone*; removing the theme you are wearing is allowed, and hands your own colours
    /// back on the way out.
    public static func remove(_ style: StyleMenu) -> [MenuItem] {
        guard !style.themes.isEmpty else { return [] }
        return [MenuItem(title: "Theme", icon: .droplet, action: .submenu(
            style.themes.map { MenuItem(title: $0.name, action: .run(.removeTheme($0.slug))) }))]
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
                     value: file == style.currentBackground ? checkmark : nil,
                     action: .run(.background(file)))
        }
        rows.append(MenuItem(title: "Next background", action: .run(.nextBackground)))
        return rows
    }

    /// Omarchy's `Setup` level — the name upstream gives it, and the level `settings` routes to.
    /// Also built on its own, by the menu, when throwing the startup toggle rebuilds the level
    /// under the cursor.
    ///
    /// `Config` is `setup.config`, which upstream is a submenu of the files Omarchy will open for
    /// you. toe has one file, so it is one row.
    public static func setup(loginItem: LoginItemState, bindings: [Binding]) -> [MenuItem] {
        var rows: [MenuItem] = []
        if let opener = configOpener(in: bindings) {
            rows.append(MenuItem(title: "Config", icon: .pencil, action: .run(opener.command)))
        }
        // After the ported row rather than before it: this one has no Omarchy counterpart — an
        // Omarchy session does not start its window manager at login, it *is* the login — and
        // toe's own rows go under the ones an Omarchy user came looking for.
        if let startup = startup(loginItem) { rows.append(startup) }
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
    ///
    /// Deliberately not Omarchy's `disabled`, which would leave it listed and dim: that guard
    /// means "you already have this", and a tick beside a switch that cannot be thrown would say
    /// the opposite of what is true.
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
        case .theme, .removeTheme, .background, .nextBackground: return 7
        case .menu:             return 8
        case .reload, .quit:    return 9
        case .exec:             return 10
        }
    }
}
