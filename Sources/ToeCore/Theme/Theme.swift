import Foundation

/// A theme that has been *found* — a name and nothing else.
///
/// Split from `Theme` on purpose. The theme list is rebuilt every time the menu opens, and a
/// menu row needs only a name, so discovery stays a directory listing: someone who has copied a
/// whole Omarchy theme collection into `~/.config/toe/themes` has ninety of these, and reading
/// and parsing ninety `colors.toml` files to draw a list is the version of this that does not
/// ship. Only the theme actually in effect is ever read.
public struct ThemeRef: Equatable, Sendable {
    public let slug: String
    public let name: String

    public init(slug: String, name: String) {
        self.slug = slug
        self.name = name
    }
}

/// A theme, read.
public struct Theme: Equatable, Sendable {
    public let slug: String
    public let name: String
    public let palette: Palette

    public init(slug: String, name: String, palette: Palette) {
        self.slug = slug
        self.name = name
        self.palette = palette
    }

    public var ref: ThemeRef { ThemeRef(slug: slug, name: name) }
}

/// The theme list the menu draws.
///
/// toe ships no themes. It used to ship three as Swift literals, and the reason it does not is
/// the same reason it ships no pictures: a theme is somebody else's work, and redistributing it
/// inside a notarised app is an act toe would be performing rather than Omarchy. So the list is
/// what you have on disk plus what Omarchy publishes, and downloading one is you fetching it
/// from the source.
///
/// The consequence, stated because it is a real cost: a fresh install with no network has no
/// themes to choose from until it has fetched the catalogue once. What it does have is toe's own
/// colours, which are `[border]` and `[menu]` in your config — and those defaults are Tokyo
/// Night's palette already, resolved through walker's tokens, so out of the box nothing looks
/// unthemed.
public enum Themes {

    /// Yours, in the order every level that lists them draws them: by name, ignoring case.
    ///
    /// The dedupe that used to live beside this has moved into `MenuModel.installableThemes`,
    /// where a theme you already have is now *listed and dimmed* rather than dropped from the
    /// catalogue — Omarchy's `disabled` guard, and what lets `Install › Style › Theme` stay a
    /// list of everything Omarchy publishes rather than a list that gets shorter every time you
    /// use it.
    public static func ordered(_ installed: [ThemeRef]) -> [ThemeRef] {
        installed.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

public extension Config {

    /// The theme's colours, over the top of whatever the file said.
    ///
    /// Separate from `parse`, and deliberately: `parse` is pure text, and resolving a name to a
    /// theme means looking in `~/.config/toe/themes` — so the config that comes out of `parse` is
    /// always the file as written, and this is the one step that needs a disk to have been read.
    /// It is also what keeps the selftest able to assert what the shipped config *says* while the
    /// Coordinator asserts what it *does*.
    ///
    /// The theme wins outright. With `[theme] name` set, the colour keys in `[border]`, `[menu]`
    /// and `[bar]` are not consulted at all — not merged with, not warned about. Not merged, because
    /// a merge would mean a theme that recoloured your border and not your menu depending on which
    /// keys you happened to have written, which is a rule nobody could hold in their head. And not
    /// warned about, because the config toe ships sets every one of those keys explicitly and the
    /// menu writes `[theme] name` into that same file: a "this key is ignored" warning would fire
    /// for every single user the first time they picked a theme, five deep in a tooltip. The
    /// comment blocks in the file say it instead, where there is room to say it once and properly.
    ///
    /// What a theme does not touch: `width`, `angle`, `radius`, `enabled`, `opacity`, `font_size`,
    /// the two menu widths, and the bar's `height`, `font_size`, `clock_format` and
    /// `battery_percentage`. Those are sizes and behaviours, and `colors.toml` has nothing to say
    /// about them — Omarchy's own theme template sets `col.active_border` and the three bar
    /// colours, and nothing else.
    func applying(_ theme: Theme) -> Config {
        var out = self

        // Both stops the same, because Omarchy's border is one flat colour: its theme template
        // renders `col.active_border = rgb(accent)` — `rgb`, not `rgba`, and not a gradient. The
        // gradient is what toe looks like when you have *not* chosen a theme, and it is still
        // there, untouched, for exactly that case. `angle` goes inert here rather than being
        // cleared, so clearing the theme brings the sweep back the way you left it.
        out.border.activeStart = theme.palette.accent
        out.border.activeEnd = theme.palette.accent

        // walker's own token mapping, the one MenuConfig's defaults were already derived from:
        // @base is the background, @text is the foreground *and* the border, @selected-text is
        // the accent. Setting `border` back to nil is what re-joins it to the foreground — a
        // `menu.border` from the file would otherwise outlive the colours it was chosen against.
        out.menu.background = theme.palette.background
        out.menu.foreground = theme.palette.foreground
        out.menu.accent = theme.palette.accent
        out.menu.border = nil

        // Omarchy's own `shell.toml` template, which is where the bar's colours come from
        // upstream: `background = {{ background }}`, `text = {{ foreground }}`, `active = {{ red
        // }}`. Red is ANSI slot 1 in every theme Omarchy publishes — see `Palette.ansiNames` —
        // and a theme that has left it out (none has) falls back to the accent, which is what
        // "calling attention to itself" means in the rest of the theme.
        out.bar.background = theme.palette.background
        out.bar.foreground = theme.palette.foreground
        out.bar.active = theme.palette.color(1) ?? theme.palette.accent

        // The resolved name, not the one the file spelled: the menu marks its current row by
        // comparing against this, and `name = "Tokyo Night"` should still tick Tokyo Night.
        out.theme.name = theme.slug
        return out
    }
}
