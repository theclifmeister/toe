import Foundation

/// The clock's label: Omarchy's format strings, and what right-clicking the clock does to them.
///
/// Omarchy stores the format in Qt's spelling — `dddd HH:mm` — on the clock's `shell.json` entry,
/// and `[bar] clock_format` keeps that spelling so a format copied across reads the same. Qt and
/// ICU disagree on the day-name and hour tokens, so `pattern(_:)` translates before
/// `DateFormatter` sees it; everything else, quotes included, is the same in both.
///
/// Pure Foundation, and so in ToeCore and the selftest: a format ring that cycled wrongly would
/// otherwise be found by right-clicking a clock ten times.
public enum ClockFormat {

    /// Omarchy's `format` default for a horizontal bar.
    public static let defaultFormat = "dddd HH:mm"

    /// `CLOCK_FORMATS` from `panels/clock/Model.js`, in its order: right-clicking the clock walks
    /// these. Each locale-shaped time preset is followed by its 12-hour twin, so the walk from a
    /// 24-hour label to the same label in AM/PM is one click rather than a lap of the ring; the
    /// ISO preset is deliberately without one, since ISO 8601 is a 24-hour clock.
    public static let presets = [
        "dddd HH:mm",
        "dddd h:mm AP",
        "dddd HH:mm:ss",
        "dddd h:mm:ss AP",
        "HH:mm",
        "h:mm AP",
        "ddd d MMM HH:mm",
        "ddd d MMM h:mm AP",
        "d MMMM 'W'ww yyyy",
        "yyyy-MM-dd HH:mm",
    ]

    /// The presets, plus `current` at the end when it is something else — a hand-written format
    /// stays reachable rather than being lost on the first right-click. The order must not
    /// depend on which entry is current: the result is written back to the config, and a ring
    /// that reshuffled itself around the current value would bounce between two entries instead
    /// of walking.
    public static func ring(current: String) -> [String] {
        var ring = presets
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, !ring.contains(trimmed) { ring.append(trimmed) }
        return ring
    }

    /// The entry after `current` in its ring, wrapping. A current that is not in the ring cannot
    /// happen — `ring(current:)` puts it there — but an empty one starts the walk at the top.
    public static func next(after current: String) -> String {
        let ring = ring(current: current)
        guard let index = ring.firstIndex(of: current.trimmingCharacters(in: .whitespaces)) else {
            return ring[0]
        }
        return ring[(index + 1) % ring.count]
    }

    /// Whether the label prints seconds, so the clock ticks once a second only for the formats
    /// that show them and once a minute for the rest. Quoted literals are set aside first: the
    /// `s` in a `'Sat'` is text, and an opening quote with no closing one runs to the end of the
    /// format, as Qt reads it.
    public static func needsSeconds(_ format: String) -> Bool {
        unquoted(format).contains("s")
    }

    /// Whether the format shows a 12-hour clock — Qt's rule: `h` is 1-12 when the format has an
    /// `AP` or `ap` in it, and 0-23 otherwise.
    static func isTwelveHour(_ format: String) -> Bool {
        let bare = unquoted(format)
        return bare.contains("AP") || bare.contains("ap") || bare.contains("A") || bare.contains("a")
    }

    /// The format with its quoted literals blanked, so a search for a token cannot land in text.
    private static func unquoted(_ format: String) -> String {
        var out = ""
        var quoted = false
        for ch in format {
            if ch == "'" { quoted.toggle(); continue }
            out.append(quoted ? " " : ch)
        }
        return out
    }

    /// The same format for `DateFormatter`, token by token.
    ///
    /// Day names are the visible difference — Qt's `dddd` is ICU's `EEEE` — and the hour is the
    /// invisible one: Qt's `h` means 24-hour until an `AP` appears somewhere in the format, where
    /// ICU's `h` is always 12-hour. `AP` and `ap` both become `a`, because ICU has one meridiem
    /// token and the locale decides its case. `ww` is ICU's week of the year, which
    /// `render(_:at:)` makes the ISO week by formatting on an ISO 8601 calendar — Omarchy
    /// substitutes the ISO week in by hand for the same reason, Qt having no week token at all.
    ///
    /// A letter that is not a Qt token is a literal to Qt and a pattern letter to ICU, so it is
    /// quoted on the way through: `d MMMM Wyy` prints a `W` in both, rather than a week-of-month.
    /// Literals that land next to each other — a quoted `'o'`, a `''`, an unquoted `clock` — go
    /// out as one quoted run, because to ICU `'o''clock'` is one literal with an apostrophe in
    /// it and `'o'` `'clock'` side by side is not.
    public static func pattern(_ format: String) -> String {
        let twelveHour = isTwelveHour(format)

        /// Alternating tokens and literals, before the literals are merged.
        enum Piece { case token(String), literal(String) }
        var pieces: [Piece] = []
        let chars = Array(format)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "'" {
                // `''` is a literal quote; otherwise everything to the closing quote is text,
                // and to the end of the format when there is no closing quote, as Qt reads it.
                if i + 1 < chars.count, chars[i + 1] == "'" {
                    pieces.append(.literal("'"))
                    i += 2
                    continue
                }
                var j = i + 1
                while j < chars.count, chars[j] != "'" { j += 1 }
                pieces.append(.literal(String(chars[(i + 1)..<j])))
                i = j + 1
                continue
            }
            guard ch.isLetter, ch.isASCII else {
                pieces.append(.literal(String(ch)))
                i += 1
                continue
            }
            // AP / ap are two letters that are one token, checked before the runs of one letter.
            if i + 1 < chars.count, (ch == "A" && chars[i + 1] == "P") || (ch == "a" && chars[i + 1] == "p") {
                pieces.append(.token("a"))
                i += 2
                continue
            }
            var run = 1
            while i + run < chars.count, chars[i + run] == ch { run += 1 }
            if let token = translate(ch, count: run, twelveHour: twelveHour) {
                pieces.append(.token(token))
            } else {
                pieces.append(.literal(String(repeating: ch, count: run)))
            }
            i += run
        }

        var out = ""
        var literal = ""
        func flush() {
            guard !literal.isEmpty else { return }
            defer { literal = "" }
            // Bare where ICU would read it as text anyway — spaces, colons, dashes — so the
            // common formats come out looking like themselves, and quoted only from the first
            // letter or apostrophe to the last: `d MMMM 'W'ww` keeps its spaces outside the
            // quotes rather than coming out as `d MMMM' W'ww`, which means the same and reads
            // like a mistake.
            func bare(_ ch: Character) -> Bool { !(ch.isLetter && ch.isASCII) && ch != "'" }
            let head = literal.prefix(while: bare)
            guard head.count < literal.count else { out += literal; return }
            let tail = literal.reversed().prefix(while: bare).reversed()
            let core = literal.dropFirst(head.count).dropLast(tail.count)
            out += head + "'" + core.replacingOccurrences(of: "'", with: "''") + "'" + tail
        }
        for piece in pieces {
            switch piece {
            case .literal(let text): literal += text
            case .token(let token): flush(); out += token
            }
        }
        flush()
        return out
    }

    /// The ICU spelling of a run of one Qt token letter, or nil for a letter that is no token.
    private static func translate(_ letter: Character, count: Int, twelveHour: Bool) -> String? {
        let n = min(count, 4)
        switch letter {
        case "d":
            // `d` and `dd` are the day of the month in both; three and four are the day's name.
            return n <= 2 ? String(repeating: "d", count: n) : String(repeating: "E", count: n)
        case "M": return String(repeating: "M", count: n)
        case "y": return String(repeating: "y", count: n)
        case "h": return String(repeating: twelveHour ? "h" : "H", count: min(count, 2))
        case "H": return String(repeating: "H", count: min(count, 2))
        case "m": return String(repeating: "m", count: min(count, 2))
        case "s": return String(repeating: "s", count: min(count, 2))
        // Milliseconds: Qt's `z` is unpadded and `zzz` is three digits; ICU's `S` is a count of
        // fractional digits, which is as close as it comes.
        case "z": return String(repeating: "S", count: min(count, 3))
        // Qt's `t` is the zone abbreviation, which ICU spells `z`.
        case "t": return "z"
        // Not a Qt token: Omarchy substitutes the ISO week for `ww` before formatting, so a
        // format from an Omarchy config means the week by it, and ICU's `w` on an ISO calendar
        // is that week.
        case "w": return String(repeating: "w", count: min(count, 2))
        // Qt 6's one-letter meridiem.
        case "A", "a": return "a"
        default: return nil
        }
    }

    /// The label for `date`, on an ISO 8601 calendar so `ww` is the ISO week and Monday starts
    /// it, as it is under Omarchy. The locale is the caller's: the widget passes the user's, the
    /// selftest a fixed one.
    public static func render(_ format: String, at date: Date,
                              locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = pattern(format)
        return formatter.string(from: date)
    }
}
