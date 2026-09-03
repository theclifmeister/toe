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

    /// Everything the menu can offer: what is installed, then what is merely available.
    ///
    /// A theme you have beats the same theme upstream, and only appears once — otherwise
    /// downloading Nord would leave you with two rows saying Nord, one of which would offer to
    /// download it again. Installed themes keep the order the disk gave them (sorted by name);
    /// the rest follow, so the list reads as "yours, then everything else".
    public static func merged(installed: [ThemeRef],
                              available: [RemoteTheme]) -> (installed: [ThemeRef],
                                                            available: [RemoteTheme]) {
        let have = Set(installed.map(\.slug))
        return (installed.sorted { $0.name.lowercased() < $1.name.lowercased() },
                available.filter { !have.contains($0.slug) })
    }
}
