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
/// **Two spellings of that file exist, and both are read.** Omarchy 4 (the `quattro` branch, which
/// is where every release since v3.8.4 has come from) rewrote `colors.toml`: the sixteen
/// `color0`…`color15` slots became named hues — `red`, `bright_cyan`, plus an `orange` and a
/// `brown` that ANSI has no slot for — `cursor` went away, `selection_foreground` and
/// `selection_background` became `selection` and `muted`, and a `mode` key and two ramps of
/// backgrounds and foregrounds arrived. Omarchy 3's spelling is still read because the folders
/// people already copied onto their disks are written in it, and a theme that stopped working
/// because upstream moved on would be toe's bug, not theirs. The three keys toe actually paints
/// with — `accent`, `background`, `foreground` — are spelled the same in both, which is why this
/// change was a widening rather than a migration: nothing had to be translated to keep reading
/// the old files, only looked for under a second name.
///
/// Their *values* mostly did not change either — `background` and `foreground` are identical in
/// all nineteen themes that exist on both branches, and `accent` in eighteen of them. The
/// exception is Kanagawa, whose accent Omarchy changed from `#7e9cd8` to `#dcd7ba` somewhere in
/// the 4 series. That is an upstream theme edit rather than anything toe does, but it is the one
/// case where following the new branch visibly recolours a border, and it is written down here so
/// that the next person to notice it does not go looking for the bug in this file.
///
/// Hex strings rather than `RGBA`, because `BorderConfig` and `MenuConfig` hold hex strings:
/// keeping them as text means applying a theme is an assignment, and leaves `Hex.rgba` in the one
/// place it already lives — the layer that draws.
///
/// Only three of these are read today. The rest are stored because the file is being mirrored and
/// it costs nothing, so the day the workspace strip or the selected menu row wants a themed
/// colour, `color4` — or `blue`, the same thing under Omarchy 4's name for it — is already here
/// rather than being a second pass over everyone's themes.
public struct Palette: Equatable, Sendable {

    /// Whether the theme was drawn for a light desktop or a dark one — Omarchy 4's `mode`.
    ///
    /// Worth keeping even though nothing reads it yet, because it is the one thing in the file
    /// that cannot be worked out from the colours with any confidence: five of the twenty-two
    /// themes upstream are light, and `rose-pine` is one of them despite reading as a dark name.
    public enum Mode: String, Equatable, Sendable {
        case dark, light
    }

    // What toe paints with.
    public var accent: String
    public var background: String
    public var foreground: String

    /// `mode` — Omarchy 4 only, and nil for a theme written in Omarchy 3's spelling.
    public var mode: Mode?

    // Omarchy 4's background ramp, darkest first.
    public var darkerBackground: String?
    public var darkBackground: String?
    public var lighterBackground: String?

    // Omarchy 4's foreground ramp, dimmest first.
    public var darkForeground: String?
    public var lightForeground: String?
    public var brightForeground: String?

    /// `selection` and `muted` — Omarchy 4's replacements for the `selection_*` pair.
    public var selection: String?
    public var muted: String?

    // The two hues ANSI has no slot for, so they cannot live in `terminal`. Present in nineteen
    // of the twenty-two themes upstream; the other three simply leave them out.
    public var orange: String?
    public var brown: String?

    // Omarchy 3 only. Nothing in Omarchy 4's file corresponds to `cursor` at all, and mapping the
    // `selection_*` pair onto `selection`/`muted` was rejected: they matched in three of nineteen
    // themes, which is coincidence, not a mapping.
    public var cursor: String?
    public var selectionForeground: String?
    public var selectionBackground: String?

    /// `color0` … `color15`, sixteen slots, nil where the file left one out.
    ///
    /// Fed from whichever spelling the file used — see `ansiNames` for the mapping and for why
    /// four of the slots are always nil under Omarchy 4.
    public var terminal: [String?]

    public init(accent: String, background: String, foreground: String,
                mode: Mode? = nil,
                darkerBackground: String? = nil,
                darkBackground: String? = nil,
                lighterBackground: String? = nil,
                darkForeground: String? = nil,
                lightForeground: String? = nil,
                brightForeground: String? = nil,
                selection: String? = nil,
                muted: String? = nil,
                orange: String? = nil,
                brown: String? = nil,
                cursor: String? = nil,
                selectionForeground: String? = nil, selectionBackground: String? = nil,
                terminal: [String?] = Array(repeating: nil, count: Palette.terminalSlots)) {
        self.accent = accent
        self.background = background
        self.foreground = foreground
        self.mode = mode
        self.darkerBackground = darkerBackground
        self.darkBackground = darkBackground
        self.lighterBackground = lighterBackground
        self.darkForeground = darkForeground
        self.lightForeground = lightForeground
        self.brightForeground = brightForeground
        self.selection = selection
        self.muted = muted
        self.orange = orange
        self.brown = brown
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

    /// Which ANSI slot each of Omarchy 4's named hues is.
    ///
    /// Not a guess and not the ANSI table copied out of a manual: checked against all nineteen
    /// themes Omarchy publishes on both `master` and `quattro`. Eleven of the twelve agree in
    /// nineteen cases out of nineteen — `red` is `color1` and `bright_cyan` is `color14` in every
    /// single theme — and that unanimity is the licence for reading one spelling as the other.
    ///
    /// `blue` is the twelfth, and agrees in eighteen. The exception is Retro 82, whose Omarchy 3
    /// file put its orange accent `#faa968` in slot 4 and so had no blue in it at all; Omarchy 4
    /// gives it a real one, `#3f8f8a`, and keeps the orange under `orange`. So the odd one out is
    /// a theme upstream corrected, not a slot this mapping is unsure about.
    ///
    /// Slots 0, 7, 8 and 15 — ANSI's blacks and whites — are absent because Omarchy 4 publishes
    /// no key that means them. `muted` lands on `color8` in eight of nineteen themes and
    /// `lighter_background` on `color0` in six, and a mapping that is right a third of the time is
    /// worse than a nil: nil is a slot a future caller can fall back from, and a wrong colour is
    /// one it cannot.
    public static let ansiNames: [Int: String] = [
         1: "red",          2: "green",           3: "yellow",
         4: "blue",         5: "magenta",         6: "cyan",
         9: "bright_red",  10: "bright_green",   11: "bright_yellow",
        12: "bright_blue", 13: "bright_magenta", 14: "bright_cyan",
    ]

    /// Every colour this palette actually carries, keyed the way `colors.toml` keys them — so a
    /// test can assert they all parse without naming each one, and a warning can name the one
    /// that does not.
    ///
    /// The terminal slots are listed under their numbered names whichever spelling they arrived
    /// in, because the number is the thing that is stable: `color1` and `red` are one colour with
    /// two names, and the palette no longer remembers which name the file on disk used.
    public var colours: [(key: String, value: String)] {
        var out: [(String, String)] = [("accent", accent), ("background", background),
                                       ("foreground", foreground)]
        func add(_ key: String, _ value: String?) {
            if let value { out.append((key, value)) }
        }
        add("darker_background", darkerBackground)
        add("dark_background", darkBackground)
        add("lighter_background", lighterBackground)
        add("dark_foreground", darkForeground)
        add("light_foreground", lightForeground)
        add("bright_foreground", brightForeground)
        add("selection", selection)
        add("muted", muted)
        add("orange", orange)
        add("brown", brown)
        add("cursor", cursor)
        add("selection_foreground", selectionForeground)
        add("selection_background", selectionBackground)
        for (index, colour) in terminal.enumerated() {
            if let colour { out.append(("color\(index)", colour)) }
        }
        return out
    }
}

/// Omarchy 4's names for the hues, for callers that would rather say `red` than remember that red
/// is one. Reads across to whichever spelling the file used, so these answer for an Omarchy 3
/// theme too.
public extension Palette {
    var red: String?            { color(1) }
    var green: String?          { color(2) }
    var yellow: String?         { color(3) }
    var blue: String?           { color(4) }
    var magenta: String?        { color(5) }
    var cyan: String?           { color(6) }
    var brightRed: String?      { color(9) }
    var brightGreen: String?    { color(10) }
    var brightYellow: String?   { color(11) }
    var brightBlue: String?     { color(12) }
    var brightMagenta: String?  { color(13) }
    var brightCyan: String?     { color(14) }
}

public extension Palette {

    /// Reads a `colors.toml` in either of Omarchy's two spellings.
    ///
    /// `accent`, `background` and `foreground` are required, because they are the three toe
    /// actually paints with and a theme missing one of them would silently keep whatever colour
    /// was there before. Everything else is optional — which is also what makes reading both
    /// spellings a matter of looking for more keys rather than of deciding which file this is:
    /// the keys the other spelling does not have simply come back nil.
    ///
    /// Every colour is checked through `Hex.rgba` here rather than at the far end, so a typo is
    /// named while it still has a key beside it — `Hex.rgba` answers nil rather than substituting
    /// a colour precisely so that this layer can do that.
    ///
    /// Keys that are not read, deliberately: `hyprland_active_border`,
    /// `hyprland_inactive_border`, `active_border_color` and `active_tab_background`, which a
    /// handful of themes carry as per-app overrides. `hyprland_active_border` is the tempting one
    /// — it is literally the border colour toe paints — and it is a Hyprland gradient string
    /// rather than a colour: `"rgba(26a269ee) rgba(2ec27eee) 45deg"` in `hackerman`. Reading it as
    /// a colour would throw `notAColour` and take three themes down with it, and reading it
    /// properly would mean parsing Hyprland's gradient syntax to arrive at what `accent` already
    /// says.
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

        // A `mode` that is neither `dark` nor `light` reads as nil rather than as an error: it is
        // not a colour, nothing paints with it yet, and a third value arriving upstream should
        // widen what toe knows rather than stop the theme from loading.
        let mode = table["mode"]?.stringValue.flatMap(Mode.init(rawValue:))

        // A numbered slot wins over the named hue where a file somehow has both — a hand-written
        // palette, or one mid-conversion. `color0`…`color15` is the more specific statement of
        // the two, since it names the slot rather than a colour that happens to sit in it.
        let terminal = try (0..<Palette.terminalSlots).map { index -> String? in
            if let numbered = try colour("color\(index)") { return numbered }
            guard let name = Palette.ansiNames[index] else { return nil }
            return try colour(name)
        }

        return Palette(
            accent: try required("accent"),
            background: try required("background"),
            foreground: try required("foreground"),
            mode: mode,
            darkerBackground: try colour("darker_background"),
            darkBackground: try colour("dark_background"),
            lighterBackground: try colour("lighter_background"),
            darkForeground: try colour("dark_foreground"),
            lightForeground: try colour("light_foreground"),
            brightForeground: try colour("bright_foreground"),
            selection: try colour("selection"),
            muted: try colour("muted"),
            orange: try colour("orange"),
            brown: try colour("brown"),
            cursor: try colour("cursor"),
            selectionForeground: try colour("selection_foreground"),
            selectionBackground: try colour("selection_background"),
            terminal: terminal
        )
    }
}
