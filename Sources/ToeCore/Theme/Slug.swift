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
///
/// That holds for the *making* of a slug. The other direction — a name that arrives claiming to
/// be one already, off a filesystem, out of a catalogue, over the socket — is `init?(_:)`, and
/// it is the one place that rule lives too. It used to be spelled `Slug.make(x) == x` at six
/// sites, none of them wrong, and the failure that shape invites is the seventh: a new join of a
/// name onto a path that writes `Slug.make(name)` and forgets the comparison, so `../evil`
/// becomes `evil` and carries on. A `Slug` is a value whose existence *is* the check, so a
/// function that takes one cannot be handed anything else, and there is nothing to forget.
public struct Slug: Hashable, Sendable, CustomStringConvertible {

    /// Long enough for the longest theme name anyone has written; short enough that the result is
    /// still a sane path component.
    private static let limit = 64

    public let value: String

    /// `raw` as a slug, or nil unless it already was one — refused rather than repaired, because
    /// every caller is about to join it onto a path or delete what it names, and a caller that
    /// asked for `../../x` should be told no, not handed a file called something else.
    ///
    /// The empty string is not a slug either. `make("")` is `""`, which is how a theme is
    /// cleared, but as a *name* it names nothing: joined onto a directory it is the directory
    /// itself, which is not a thing to write into or remove. Two of the six sites this replaced
    /// checked for it and four did not; for all four the empty name was either impossible (a
    /// directory entry has a name) or refused one step later (`ThemeDownloader.fetch` would not
    /// download a theme called nothing), so refusing it here changes what is listed only in the
    /// case where the listing was already a promise that could not be kept.
    public init?(_ raw: String) {
        guard !raw.isEmpty, Slug.make(raw) == raw else { return nil }
        value = raw
    }

    public var description: String { value }

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
