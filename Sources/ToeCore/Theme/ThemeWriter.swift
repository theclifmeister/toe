import Foundation

/// Sets `[theme] name` in a config file without disturbing anything else in it.
///
/// Line surgery rather than a parse and a re-serialise, deliberately. This is the user's own
/// file: their comments, their alignment, their ordering, and — per the header of the shipped
/// config — a file they are told to treat as code. A round trip through `TOML.parse` would hand
/// back something they did not write, with the comments gone. So the value between the quotes is
/// the only thing that moves, and every other byte comes out the way it went in.
///
/// The cost of that choice is that this cannot see everything a TOML parser can. `["theme"]` is
/// legal and is the *same table* as `[theme]`; so is a header split oddly across whitespace, and
/// `[theme]` can appear inside a comment or a string where it means nothing at all. The two
/// recognisable shapes are handled below; the rest is covered by the caller re-parsing this
/// function's output and refusing to write when it does not say what it was asked to say. That
/// guard is what turns a case this gets wrong from *your config is broken* into *toe declined to
/// edit your config, and said so in the log*.
public enum ThemeWriter {

    /// The theme's name is slugified on the way in, so nothing this returns can break the file it
    /// is going into: a slug has no quote, no bracket and no newline in it by construction, which
    /// is a stronger guarantee than escaping and one that only has to hold in one place.
    public static func settingTheme(_ name: String, in toml: String) -> String {
        let slug = Slug.make(name)

        // Split on "\n" and rejoin on "\n", never on newlines generally: `TOML.parse` normalises
        // CRLF on the way in, but this writes a file back, and silently converting a file someone
        // saved from Windows would be a diff they never asked for. A trailing "\r" simply rides
        // along at the end of its line — and lands in the tail that `replacingName` preserves.
        var lines = toml.components(separatedBy: "\n")

        var inTheme = false
        var themeHeader: Int?
        var replaced = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if let header = tableName(trimmed) {
                inTheme = (header == "theme")
                if inTheme, themeHeader == nil { themeHeader = index }
                continue
            }
            if inTheme, !replaced, let rewritten = replacingName(in: lines[index], with: slug) {
                lines[index] = rewritten
                replaced = true
            }
        }

        if replaced { return lines.joined(separator: "\n") }

        let crlf = lines.contains { $0.hasSuffix("\r") }
        let ending = crlf ? "\r" : ""

        if let header = themeHeader {
            lines.insert("name = \"\(slug)\"" + ending, at: header + 1)
            return lines.joined(separator: "\n")
        }

        // Appended at the end rather than inserted anywhere tidier, because a table header
        // terminates the table before it: an append can never land in the middle of somebody's
        // `[binds]` or `[[float]]`, and an insert can. Configs written before themes existed take
        // this path exactly once, and every later change takes the replace path above.
        // A carriage return belongs at the *end* of the line it terminates, before the newline.
        // Writing `"\n" + ending` put it at the start of the next one instead, which fed a stray
        // CR and a LF-only blank line into a file this whole type exists to preserve byte for
        // byte — and the obvious `contains("[theme]\r\n")` assertion passed either way.
        var out = toml
        // Asked of the bytes, not of `hasSuffix("\n")`. CR-LF is a *single* Swift `Character`, so
        // a file ending in one has no `Character` equal to "\n" at the end and `hasSuffix` answers
        // false — which quietly added a second blank line to every CRLF file. Same trap
        // `TOML.parse` carries a comment about, one type over.
        if !out.isEmpty, out.utf8.last != UInt8(ascii: "\n") { out += ending + "\n" }
        out += "\(ending)\n[theme]\(ending)\nname = \"\(slug)\"\(ending)\n"
        return out
    }

    /// The table a header line names, or nil if the line is not a header.
    ///
    /// `[[float]]` answers with a name that cannot be `theme`, which is what makes an array of
    /// tables count as *leaving* the theme table rather than being ignored inside it.
    private static func tableName(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("[") else { return nil }
        if trimmed.hasPrefix("[[") {
            guard trimmed.contains("]]") else { return nil }
            return "[[array]]"                      // never equal to a bare key
        }
        guard let close = trimmed.firstIndex(of: "]") else { return nil }
        var inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        // `["theme"]` is the same table as `[theme]`, and it is the shape most likely to be
        // written by a generator rather than by hand.
        for quote in ["\"", "'"] where inner.hasPrefix(quote) && inner.hasSuffix(quote) && inner.count >= 2 {
            inner = String(inner.dropFirst().dropLast())
        }
        return inner
    }

    /// `name = "old"  # comment` becomes `name = "new"  # comment`, and anything that is not a
    /// `name` assignment is left alone.
    ///
    /// Everything before the value and everything after it is copied through untouched, which is
    /// what keeps a column of aligned `=` aligned and a trailing comment attached to the line it
    /// was written on.
    private static func replacingName(in line: String, with slug: String) -> String? {
        let chars = Array(line)
        var i = 0

        func skipSpaces() { while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 } }

        skipSpaces()
        guard i < chars.count else { return nil }

        var key = ""
        if chars[i] == "\"" || chars[i] == "'" {
            let quote = chars[i]
            i += 1
            while i < chars.count, chars[i] != quote { key.append(chars[i]); i += 1 }
            guard i < chars.count else { return nil }
            i += 1
        } else {
            while i < chars.count, chars[i].isLetter || chars[i].isNumber
                    || chars[i] == "_" || chars[i] == "-" {
                key.append(chars[i]); i += 1
            }
        }
        guard key == "name" else { return nil }

        skipSpaces()
        guard i < chars.count, chars[i] == "=" else { return nil }
        i += 1
        skipSpaces()
        let valueStart = i

        // Where the old value ends. A quoted value ends at its closing quote; anything else —
        // a number, a bare word, a config in the middle of being edited — ends at whitespace or
        // at the `#` that starts a comment. Either way the tail is preserved verbatim.
        if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
            let quote = chars[i]
            i += 1
            while i < chars.count, chars[i] != quote {
                if chars[i] == "\\", i + 1 < chars.count { i += 1 }
                i += 1
            }
            guard i < chars.count else { return nil }       // unterminated: leave it well alone
            i += 1
        } else {
            while i < chars.count, chars[i] != "#", !chars[i].isWhitespace { i += 1 }
        }

        return String(chars[0..<valueStart]) + "\"\(slug)\"" + String(chars[i...])
    }
}
