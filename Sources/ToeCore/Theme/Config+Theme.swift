import Foundation

public extension Config {

    /// The theme's colours, over the top of whatever the file said.
    ///
    /// Separate from `parse`, and deliberately: `parse` is pure text, and resolving a name to a
    /// theme means looking in `~/.config/toe/themes` — so the config that comes out of `parse` is
    /// always the file as written, and this is the one step that needs a disk to have been read.
    /// It is also what keeps the selftest able to assert what the shipped config *says* while the
    /// Coordinator asserts what it *does*.
    ///
    /// The theme wins outright. With `[theme] name` set, the colour keys in `[border]` and
    /// `[menu]` are not consulted at all — not merged with, not warned about. Not merged, because
    /// a merge would mean a theme that recoloured your border and not your menu depending on which
    /// keys you happened to have written, which is a rule nobody could hold in their head. And not
    /// warned about, because the config toe ships sets every one of those keys explicitly and the
    /// menu writes `[theme] name` into that same file: a "this key is ignored" warning would fire
    /// for every single user the first time they picked a theme, five deep in a tooltip. The
    /// comment blocks in the file say it instead, where there is room to say it once and properly.
    ///
    /// What a theme does not touch: `width`, `angle`, `radius`, `enabled`, `opacity`, `font_size`
    /// and the two menu widths. Those are sizes and behaviours, and `colors.toml` has nothing to
    /// say about them — Omarchy's own theme template sets `col.active_border` and nothing else.
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

        // The resolved name, not the one the file spelled: the menu marks its current row by
        // comparing against this, and `name = "Tokyo Night"` should still tick Tokyo Night.
        out.theme.name = theme.slug
        return out
    }
}
