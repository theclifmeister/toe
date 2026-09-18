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
    public static let apps = MenuRoute(path: ["Apps"])
    public static let learn = MenuRoute(path: ["Learn"])
    public static let style = MenuRoute(path: ["Style"])
    public static let theme = MenuRoute(path: ["Style", "Theme"])
    public static let background = MenuRoute(path: ["Style", "Background"])
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
        case paintbrush, droplet, image
        case download, trash, info, globe
        /// The command line, and the one row that is about it — see `MenuModel.agentSkill`.
        case terminal
        /// The `Apps` row — a grid of squares, which is what the glyph Omarchy puts on it is.
        case apps
        /// An application's own icon, by the bundle it is read from. Still symbolic to ToeCore —
        /// a path is not a picture — and it is the UI layer that asks `NSWorkspace` what the
        /// bundle looks like, so the selftest can assert a row carries one without a pixel in
        /// sight. The one icon that is not a glyph; `foundAt` once kept it on a root hit for
        /// that reason and no longer does, and says why.
        case application(path: String)
    }

    public indirect enum Action: Equatable {
        case submenu([MenuItem])
        case page(MenuPage)
        case run(Command)
        case toggleLoginItem
        /// One of the Setup switches — which one is the payload. Its own case rather than a
        /// `.run`, for the reason the login toggle has one: the row's value flips under the
        /// cursor and the menu stays open, which no `Command` does.
        case toggleSetting(ConfigSwitch)
        /// A row that says something and does nothing when you press it — "Fetching Omarchy's
        /// themes…". The alternative was leaving the level looking like a short list rather than
        /// an unfinished one, which is the sort of thing you stare at wondering if it is broken.
        case note
        /// Open the application at this path. Its own case rather than a `.run(.exec("open …"))`
        /// for two reasons: an `exec` goes through `/bin/sh`, so a path with an apostrophe in it
        /// (`Sid Meier's Civilization V.app`) would need quoting that gets it wrong somewhere; and
        /// a `Command` is a verb in the config and on the command line, which a menu row that
        /// launches whatever happens to be in `/Applications` is not.
        case launch(String)
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

    /// The same row as a search hit: it gains the path it was found at, and loses its icon if
    /// the search began at the root.
    ///
    /// The root is where a search crosses the whole tree, and the whole tree is two kinds of
    /// level: the ones that put an icon on every row (Learn, Setup, Apps) and the ones that put
    /// one on none (Theme, Background). `titleOrigin` sets a row's title past its icon only
    /// when it has one, so a list that mixes the two kinds indents some titles and not others,
    /// and the eye reads the ragged left edge before it reads a word. A root search is that
    /// list every time, so every root hit goes bare: the edge comes back, and the path under
    /// the title now carries the hint the glyph did. That includes an application's picture,
    /// which #153 had let survive — from then on `saf` at the root put a picture on Safari and
    /// nothing on `Style` beneath it, the very raggedness the rule was for, and `Apps` under
    /// the title says which Safari it is as well as the picture did.
    ///
    /// Inside a level the search is a filter of the rows in front of you, and those rows keep
    /// what they wear: a level is all icons or none by construction, so its filtered self lines
    /// up the way it did before the first keystroke, and a launcher does not lose its pictures
    /// for being typed at (#154). A search from a level does still reach the levels below it —
    /// `t` inside Style turns up `Theme` beside the themes under it — and there the column can
    /// go mixed; that is two rows of glyph-bearing parent among their bare children, in a
    /// level with two rows, and it was judged (#162) not worth taking the icons off every
    /// sublevel search to prevent.
    ///
    /// Why this split and not one rule for every search: #162 asked for the root and `Apps` to
    /// stop doing different things for the same keystrokes, and the two ways to make them
    /// agree both cost more than the split does. Keeping every icon everywhere brings the
    /// ragged root search back; dropping every icon everywhere turns the launcher into a text
    /// list the moment you type, which is what #154 kept it from being. Reserving the icon
    /// column for a whole list at once — every title indented while any row has an icon — was
    /// built and set aside: it lines a mixed search up, but by putting an empty gutter on the
    /// theme rows of a root search, and that was not the fix that was asked for. So the rule
    /// is the level's: the root strips, a sublevel keeps, and which one you are on is on the
    /// placeholder line (`Go…` against the level's own name) before you type.
    public func foundAt(path: String?, fromRoot: Bool) -> MenuItem {
        MenuItem(title: title, subtitle: path, icon: fromRoot ? nil : icon, value: value,
                 progress: progress, isDisabled: isDisabled, action: action)
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
/// Style is in the name because for a long time that was all of it. The Install and Remove levels
/// hold one row that is not about colour — the agent skill — and it is carried here rather than
/// as a second parameter for the reason the rest of this is one value: it is threaded from the
/// Coordinator through `QuickMenu` to `MenuModel` unchanged, and a second thing to thread is a
/// second thing to forget to thread.
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
    /// Where the Claude Code skill file is and whether what is there is what this copy of toe
    /// would write. nil where nobody has asked — the selftest, and every construction of this
    /// value that is not the menu opening — and the row is then left out rather than guessing.
    public var skill: SkillReport?
    /// The applications on the machine, in the order the `Apps` level lists them — see
    /// `Apps.ordered`. Empty is a machine the scan found nothing on, or has not looked at yet,
    /// and the row is then left out: the Setup rule, that a row into an empty level is worse
    /// than no row. Here for the reason the skill is — one value, threaded once.
    public var apps: [AppRef]

    public init(themes: [ThemeRef] = [], available: [RemoteTheme] = [], fetching: Bool = false,
                current: String? = nil,
                backgrounds: [String] = [], currentBackground: String? = nil,
                downloading: ThemeDownload? = nil, skill: SkillReport? = nil,
                apps: [AppRef] = []) {
        self.themes = themes
        self.available = available
        self.fetching = fetching
        self.current = current
        self.backgrounds = backgrounds
        self.currentBackground = currentBackground
        self.downloading = downloading
        self.skill = skill
        self.apps = apps
    }
}

/// A Setup row that flips one boolean in `toe.toml`.
///
/// The case names the line it writes — which table, which key, and how to read it back — because
/// everything between the row and the file is otherwise the same code once per switch: the menu
/// builds a row from `value(in:)`, `MenuState` hands the case straight back, and
/// `Coordinator.toggle` writes `key` into `table` and reloads. A sixth switch is a case here and
/// nothing anywhere else.
///
/// Only settings that are *worth* a row belong here — a switch in the menu is a switch somebody
/// will throw while looking at what it does, so it wants an effect they can see. The first three
/// change the screen the moment they are written; the fourth changes the next SUPER+TAB and the
/// fifth the next SUPER+W, keys under the same hand that closed the menu, and close enough to
/// count. That is the bar to clear: `restore_session` shows nothing until the next launch, and
/// is not here.
public enum ConfigSwitch: String, Equatable, Sendable, CaseIterable {
    /// `[animations] slide_on_swipe`. The one that can ask for a permission — see
    /// `Coordinator.toggle` on why the flip goes through the file.
    case slide
    /// `[border] enabled`. The gradient around the focused window.
    case border
    /// `[misc] autohide_dock`. Hands the Dock's strip of screen back to the tiles.
    case dock
    /// `[misc] cycle_empty_workspaces`. Whether SUPER+TAB stops at the empty slots on the bar.
    case cycleEmpty
    /// `[misc] quit_on_last_window`. Whether SUPER+W on an application's last window is ⌘Q.
    case quitOnLast

    /// The row's title. Says what the setting does rather than what the key is called, because
    /// the key is one grep away and the row is not.
    public var title: String {
        switch self {
        case .slide:  return "Workspace slide"
        case .border: return "Focus border"
        case .dock:   return "Auto-hide Dock"
        case .cycleEmpty: return "Cycle empty workspaces"
        case .quitOnLast: return "Quit app on last window"
        }
    }

    public var table: String {
        switch self {
        case .slide:  return "animations"
        case .border: return "border"
        case .dock:   return "misc"
        case .cycleEmpty: return "misc"
        case .quitOnLast: return "misc"
        }
    }

    public var key: String {
        switch self {
        case .slide:  return "slide_on_swipe"
        case .border: return "enabled"
        case .dock:   return "autohide_dock"
        case .cycleEmpty: return "cycle_empty_workspaces"
        case .quitOnLast: return "quit_on_last_window"
        }
    }

    public func value(in config: Config) -> Bool {
        switch self {
        case .slide:  return config.animations.slideOnSwipe
        case .border: return config.border.enabled
        case .dock:   return config.misc.autohideDock
        case .cycleEmpty: return config.misc.cycleEmptyWorkspaces
        case .quitOnLast: return config.misc.quitOnLastWindow
        }
    }

    /// The value written into a config in memory, for the one caller that has to show a row
    /// before the file has been read back — `QuickMenu`, redrawing the level under the cursor.
    public func set(_ on: Bool, in config: inout Config) {
        switch self {
        case .slide:  config.animations.slideOnSwipe = on
        case .border: config.border.enabled = on
        case .dock:   config.misc.autohideDock = on
        case .cycleEmpty: config.misc.cycleEmptyWorkspaces = on
        case .quitOnLast: config.misc.quitOnLastWindow = on
        }
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

    public static func root(loginItem: LoginItemState, config: Config,
                            style: StyleMenu = StyleMenu(),
                            version: String? = nil) -> [MenuItem] {
        // Omarchy's root order, with the rows toe has no analogue for left out: **Apps**,
        // **Learn**, Trigger, **Style**, **Setup**, **Install**, **Remove**, Update, **About**,
        // System. Quit is toe's own and goes last, after everything ported.
        var items: [MenuItem] = []
        // Upstream's first row, and a provider level rather than a written one: its rows are
        // whatever the machine has at the moment you look, the way `Style › Theme` is the
        // themes directory. Absent when the scan found nothing — a sandbox, or the first open
        // before the scan has answered — for the Setup rule below.
        let appRows = apps(style)
        if !appRows.isEmpty {
            items.append(MenuItem(title: "Apps", icon: .apps, action: .submenu(appRows)))
        }
        items.append(MenuItem(title: "Learn", icon: .book, action: .submenu(learn())))
        items.append(MenuItem(title: "Style", icon: .paintbrush,
                              action: .submenu(MenuModel.style(style))))
        // A row that leads into an empty level is worse than no row, so the parent goes with an
        // empty Setup. That is Omarchy's rule for a submenu whose children have all failed their
        // `when`, applied here by hand because toe's levels are built rather than filtered. The
        // slide switch is unconditional, so as things stand the level cannot come out empty — but
        // which of these rows survives is a function of the machine, and the guard is what keeps
        // the day one of them goes conditional again from putting a dead row at the root.
        let setupRows = setup(loginItem: loginItem, config: config)
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

    /// Omarchy's `Apps` level: every application found, each wearing its own icon, and Return
    /// launches it.
    ///
    /// Shaped like the theme list — no value column, nothing ticked, nothing dimmed. Omarchy
    /// shows no running state on an app row, and toe has no more to say about an application
    /// than that it is there: the row is the name and the picture, and the picture is the one
    /// thing here that is not a glyph from the menu font, which is why `MenuItem.Icon` has a
    /// case that names a path.
    public static func apps(_ style: StyleMenu) -> [MenuItem] {
        style.apps.map { app in
            MenuItem(title: app.name, icon: .application(path: app.path),
                     action: .launch(app.path))
        }
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

    /// Omarchy's `Install` level. Upstream it holds sixteen submenus; toe can put two kinds of
    /// thing on your machine, so it holds `Style › Theme` — the two levels above it exist to put
    /// that row where an Omarchy user's hands expect to find it — and the agent skill.
    ///
    /// The theme half is absent until the catalogue has been fetched once: a machine that has
    /// never had a network has no themes to offer and says so by not offering. The skill needs
    /// nothing fetched, so the level itself is no longer conditional — which is a change from
    /// when this could come out empty, and the reason the guard below stays: the *rule* is that a
    /// row leading into an empty level is worse than no row, not that this particular level
    /// happens to have something in it today.
    public static func install(_ style: StyleMenu) -> [MenuItem] {
        var rows: [MenuItem] = []
        let themes = installableThemes(style)
        if !themes.isEmpty {
            rows.append(MenuItem(title: "Style", icon: .paintbrush, action: .submenu([
                MenuItem(title: "Theme", icon: .droplet, action: .submenu(themes)),
            ])))
        }
        if let skill = agentSkill(style) { rows.append(skill) }
        return rows
    }

    /// The row that writes `~/.claude/skills/toe/SKILL.md`.
    ///
    /// toe's own row, with no Omarchy counterpart — Omarchy's Install level installs software,
    /// and this installs a page of documentation into another program's directory. It is here
    /// rather than under Setup because Setup is switches and the config file, and this is a thing
    /// that is either on your disk or not, which is exactly what Install and Remove are for.
    ///
    /// Omarchy's `disabled` guard does the work: once the file is there the row stays listed,
    /// goes dim and takes a tick, so the level reads as a catalogue of what toe can put on the
    /// machine rather than a list that empties as you use it. The one thing that is not simply
    /// present or absent is a file written by the *other* copy of toe — the document names the
    /// binary that wrote it, so the development build and the installed one write different text
    /// — and that is offered rather than ticked, with the second column saying which it is.
    public static func agentSkill(_ style: StyleMenu) -> MenuItem? {
        guard let skill = style.skill else { return nil }
        let current = skill.installed && !skill.stale
        return MenuItem(title: "Claude Code skill",
                        icon: .terminal,
                        value: current ? checkmark : (skill.stale ? "update" : nil),
                        isDisabled: current,
                        action: .run(.installSkill))
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
        var rows: [MenuItem] = []
        if !style.themes.isEmpty {
            rows.append(MenuItem(title: "Theme", icon: .droplet, action: .submenu(
                style.themes.map { MenuItem(title: $0.name, action: .run(.removeTheme($0.slug))) })))
        }
        // Only when there is something to remove, which is upstream's `when` and the mirror of
        // the Install row: no tick and no dimming here, because in a list called Remove a tick
        // would read as *this one is already gone*. A stale file is still a file and is still
        // listed — you can take away a skill written by the other copy of toe.
        if style.skill?.installed == true {
            rows.append(MenuItem(title: "Claude Code skill", icon: .terminal,
                                 action: .run(.removeSkill)))
        }
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
    public static func setup(loginItem: LoginItemState, config: Config) -> [MenuItem] {
        var rows: [MenuItem] = []
        if let opener = configOpener(in: config.bindings) {
            rows.append(MenuItem(title: "Config", icon: .pencil, action: .run(opener.command)))
        }
        // After the ported row rather than before it: this one has no Omarchy counterpart — an
        // Omarchy session does not start its window manager at login, it *is* the login — and
        // toe's own rows go under the ones an Omarchy user came looking for.
        if let startup = startup(loginItem) { rows.append(startup) }
        // Upstream keeps its live switches under `Trigger › Toggle`, and the slide sat there for
        // exactly as long as it was the only one: a root row leading to a level leading to a
        // level holding one switch is three keys to reach a thing toe had one of. None of these
        // is one of upstream's ten toggles — they are toe's own settings — so with the borrowed
        // level gone they go where toe's other settings are, under the config and the startup
        // switch, in the order `ConfigSwitch` declares them.
        //
        // Every one of them is also a line in `toe.toml`, and the row and the file say the same
        // thing because the row *is* the file: the value is read from the config the menu was
        // opened with, and throwing the switch edits that line rather than remembering something
        // beside it.
        for setting in ConfigSwitch.allCases {
            let on = setting.value(in: config)
            rows.append(MenuItem(title: setting.title,
                                 icon: on ? .toggleOn : .toggleOff,
                                 value: on ? "on" : "off",
                                 action: .toggleSetting(setting)))
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
        // Last of the workspace verbs: it is the one that acts on a workspace as a whole rather
        // than on where you are or what is on it.
        case .swapWorkspace:    return 6
        case .killActive, .toggleFloating, .toggleSplit, .swapSplit, .resizeActive, .growActive: return 7
        case .theme, .removeTheme, .background, .nextBackground: return 8
        case .menu:             return 9
        // With `reload` and `quit` rather than with the theme rows: this is a thing done to
        // toe's own installation, not to how the screen looks.
        case .installSkill, .removeSkill: return 10
        case .reload, .quit:    return 10
        case .exec:             return 11
        }
    }
}
