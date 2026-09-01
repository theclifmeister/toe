import Foundation

/// A focus-border gradient, named after the Omarchy theme it comes from.
///
/// Hyprland writes `col.active_border = rgba(7aa2f7ee) rgba(bb9af7ee) 45deg`; toe's spelling is
/// `#rrggbbaa`, so an Omarchy theme converts by dropping `rgba(` and `)` and prefixing `#` — the
/// `ee` alpha is already toe's own default. Values are lifted from each theme's `hyprland.conf`
/// rather than eyeballed from its palette, which is the same standard the dwindle port holds
/// itself to.
public struct BorderTheme: Equatable, Sendable {
    public let id: String
    public let name: String
    public let activeStart: String
    public let activeEnd: String

    public init(id: String, name: String, activeStart: String, activeEnd: String) {
        self.id = id
        self.name = name
        self.activeStart = activeStart
        self.activeEnd = activeEnd
    }

    public static let all: [BorderTheme] = [
        BorderTheme(id: "toe",         name: "toe",         activeStart: "#33ccffee", activeEnd: "#00ff99ee"),
        BorderTheme(id: "tokyonight",  name: "Tokyo Night", activeStart: "#7aa2f7ee", activeEnd: "#bb9af7ee"),
        BorderTheme(id: "catppuccin",  name: "Catppuccin",  activeStart: "#89b4faee", activeEnd: "#cba6f7ee"),
        BorderTheme(id: "nord",        name: "Nord",        activeStart: "#88c0d0ee", activeEnd: "#5e81acee"),
        BorderTheme(id: "gruvbox",     name: "Gruvbox",     activeStart: "#fabd2fee", activeEnd: "#d65d0eee"),
        BorderTheme(id: "everforest",  name: "Everforest",  activeStart: "#a7c080ee", activeEnd: "#7fbbb3ee"),
        BorderTheme(id: "rosepine",    name: "Rosé Pine",   activeStart: "#ebbcbaee", activeEnd: "#c4a7e7ee"),
        BorderTheme(id: "kanagawa",    name: "Kanagawa",    activeStart: "#7e9cd8ee", activeEnd: "#957fb8ee"),
        BorderTheme(id: "matteblack",  name: "Matte Black", activeStart: "#8a8a8dee", activeEnd: "#4a4a4dee"),
    ]

    /// Which theme, if any, the running config matches — so the menu can tick one without
    /// storing any state of its own. Compared on the parsed colours rather than the strings, so
    /// `#7AA2F7EE` and `#7aa2f7ee` are the same theme.
    public static func matching(_ border: BorderConfig) -> BorderTheme? {
        let start = RGBA.parse(hex: border.activeStart)
        let end = RGBA.parse(hex: border.activeEnd)
        return all.first {
            RGBA.parse(hex: $0.activeStart) == start && RGBA.parse(hex: $0.activeEnd) == end
        }
    }
}

/// The three gaps presets under Style.
///
/// Deliberately separate from the themes rather than folded into them: in Omarchy `looknfeel.conf`
/// is shared across every theme and only the colours change, so a "theme" that also moved your
/// gaps would be inventing a relationship the reference does not have.
public struct GapsPreset: Equatable, Sendable {
    public let id: String
    public let name: String
    public let inner: Int
    public let outer: Int

    public static let all: [GapsPreset] = [
        GapsPreset(id: "tight",   name: "Tight",   inner: 0,  outer: 0),
        GapsPreset(id: "omarchy", name: "Omarchy", inner: 5,  outer: 10),
        GapsPreset(id: "roomy",   name: "Roomy",   inner: 10, outer: 20),
    ]
}
