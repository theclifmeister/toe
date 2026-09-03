import Foundation

/// What went wrong reading a `colors.toml`.
///
/// Named keys rather than a single "bad theme", because the file is one a user may have written
/// by hand and the menu bar tooltip is where they will read this.
public enum PaletteError: Error, CustomStringConvertible, Equatable {
    /// A key toe needs is not in the file.
    case missing(String)
    /// A key is there and is not a colour.
    case notAColour(key: String, value: String)

    public var description: String {
        switch self {
        case .missing(let key):
            return "no \(key) in colors.toml"
        case .notAColour(let key, let value):
            return "\(key) = \"\(value)\" in colors.toml is not a colour"
        }
    }
}

/// A theme's colours — Omarchy's `themes/<name>/colors.toml`, mirrored key for key.
///
/// The key names are Omarchy's, and the file keeps its name, deliberately: a theme in
/// `~/.config/toe/themes` is meant to be a folder copied straight across from an Omarchy install,
/// backgrounds and all, and a format that is *nearly* theirs would be worse than either having
/// their format or having an obviously different one.
///
/// Hex strings rather than `RGBA`, because `BorderConfig` and `MenuConfig` hold hex strings:
/// keeping them as text means applying a theme is an assignment, and leaves `Hex.rgba` in the one
/// place it already lives — the layer that draws.
///
/// Only three of these are read today. The rest are stored because the file is being mirrored and
/// it costs nothing, so the day the workspace strip or the selected menu row wants a themed
/// colour, `color4` is already here rather than being a second pass over everyone's themes.
public struct Palette: Equatable, Sendable {

    public var accent: String
    public var background: String
    public var foreground: String
    public var cursor: String?
    public var selectionForeground: String?
    public var selectionBackground: String?
    /// `color0` … `color15`, sixteen slots, nil where the file left one out.
    public var terminal: [String?]

    public init(accent: String, background: String, foreground: String,
                cursor: String? = nil,
                selectionForeground: String? = nil, selectionBackground: String? = nil,
                terminal: [String?] = Array(repeating: nil, count: Palette.terminalSlots)) {
        self.accent = accent
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selectionForeground = selectionForeground
        self.selectionBackground = selectionBackground
        self.terminal = terminal
    }

    public static let terminalSlots = 16

    public func color(_ index: Int) -> String? {
        guard terminal.indices.contains(index) else { return nil }
        return terminal[index]
    }

    /// Every colour this palette actually carries, keyed the way the file keys them — so a test
    /// can assert they all parse without naming each one, and a warning can name the one that
    /// does not.
    public var colours: [(key: String, value: String)] {
        var out: [(String, String)] = [("accent", accent), ("background", background),
                                       ("foreground", foreground)]
        if let cursor { out.append(("cursor", cursor)) }
        if let selectionForeground { out.append(("selection_foreground", selectionForeground)) }
        if let selectionBackground { out.append(("selection_background", selectionBackground)) }
        for (index, colour) in terminal.enumerated() {
            if let colour { out.append(("color\(index)", colour)) }
        }
        return out
    }
}

public extension Palette {

    /// Reads a `colors.toml`.
    ///
    /// `accent`, `background` and `foreground` are required, because they are the three toe
    /// actually paints with and a theme missing one of them would silently keep whatever colour
    /// was there before. Everything else is optional.
    ///
    /// Every colour is checked through `Hex.rgba` here rather than at the far end, so a typo is
    /// named while it still has a key beside it — `Hex.rgba` answers nil rather than substituting
    /// a colour precisely so that this layer can do that.
    static func parse(_ toml: String) throws -> Palette {
        let table = try TOML.parse(toml)

        func colour(_ key: String) throws -> String? {
            guard let value = table[key] else { return nil }
            guard let text = value.stringValue else {
                throw PaletteError.notAColour(key: key, value: "\(value)")
            }
            guard Hex.rgba(text) != nil else {
                throw PaletteError.notAColour(key: key, value: text)
            }
            return text
        }

        func required(_ key: String) throws -> String {
            guard let value = try colour(key) else { throw PaletteError.missing(key) }
            return value
        }

        return Palette(
            accent: try required("accent"),
            background: try required("background"),
            foreground: try required("foreground"),
            cursor: try colour("cursor"),
            selectionForeground: try colour("selection_foreground"),
            selectionBackground: try colour("selection_background"),
            terminal: try (0..<Palette.terminalSlots).map { try colour("color\($0)") }
        )
    }
}
