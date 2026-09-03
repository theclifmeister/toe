import Foundation

/// A theme's name on disk.
///
/// Omarchy's `omarchy-theme-set` reduces a display name to a directory name with
/// `tr '[:upper:]' '[:lower:]' | tr ' ' '-'`, and toe accepts the same spellings so that a
/// `theme "Tokyo Night"` line read across from an Omarchy config finds the same directory.
///
/// What Omarchy does not need, and toe does: a slug arriving here has come from the config file
/// or from a `[binds]` line, and it leaves in two directions — appended to `~/.config/toe/themes`
/// as a path component, and written back into the user's own TOML between a pair of quotes. So
/// anything outside `a-z0-9-` is *dropped* rather than escaped, which makes both of those safe by
/// construction rather than by remembering: `../` and a bare `"` are simply not slug characters,
/// and there is no second place that has to know it.
public enum Slug {

    /// Long enough for the longest theme name anyone has written; short enough that the result is
    /// still a sane path component.
    private static let limit = 64

    public static func make(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(min(raw.count, limit))
        for character in raw.lowercased() {
            let mapped: Character?
            switch character {
            case "a"..."z", "0"..."9": mapped = character
            case "_", "-":             mapped = "-"
            // Every kind of whitespace, not just a space: a tab or a newline that has found its
            // way into a name is still a word boundary, and turning it into one keeps two words
            // from being welded together into a directory nobody meant to name.
            case let c where c.isWhitespace: mapped = "-"
            default:                   mapped = nil          // dropped, not escaped
            }
            guard let mapped else { continue }
            // Collapse runs, so "Rose  Pine" and "rose--pine" are the same directory.
            if mapped == "-", out.last == "-" { continue }
            out.append(mapped)
            if out.count == limit { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        while out.hasPrefix("-") { out.removeFirst() }
        return out
    }

    /// A directory name read back as something to put in a menu row: `catppuccin-latte` becomes
    /// `Catppuccin Latte`. Only for themes found on disk, which have nothing but a directory name
    /// to be titled from. The three toe ships carry their own display names instead, so what a
    /// row says is a decision rather than the output of a string transform.
    public static func title(_ slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
