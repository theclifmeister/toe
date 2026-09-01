import Foundation

/// Rewrites individual scalar values in an existing TOML document, in place.
///
/// Deliberately *not* a serialiser. `TOML.swift` cannot round-trip a config file: its parser
/// discards comments and hands back an unordered dictionary, and toe.toml is roughly two-thirds
/// comments — comments that *are* the documentation, explaining hot reloading and carrying each
/// section's Omarchy provenance. Regenerating the file would throw all of that away.
///
/// So this only ever replaces the value span of a bare key inside a named single table, inserts
/// that key if the table is there without it, or appends the table if it is missing entirely.
/// Leading whitespace, the alignment padding before `=`, and any trailing comment all survive.
/// It never touches `[[arrays of tables]]`.
public enum TOMLEdit {

    public struct Edit: Equatable {
        public let table: String
        public let key: String
        public let value: TOMLValue
        public init(table: String, key: String, value: TOMLValue) {
            self.table = table
            self.key = key
            self.value = value
        }
    }

    public static func apply(_ edits: [Edit], to text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        // Grouped so a table is only walked once however many of its keys are being set.
        for table in orderedTables(of: edits) {
            let keyed = edits.filter { $0.table == table }
            lines = applyToTable(table, keyed, lines)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - One table at a time

    private static func orderedTables(of edits: [Edit]) -> [String] {
        var seen = Set<String>()
        return edits.compactMap { seen.insert($0.table).inserted ? $0.table : nil }
    }

    private static func applyToTable(_ table: String, _ edits: [Edit], _ lines: [String]) -> [String] {
        var lines = lines
        var pending = edits
        /// The index just past the table's last key-bearing line — where a missing key goes, so it
        /// lands inside its own section rather than at the end of the file.
        var insertionPoint: Int?
        var current: String?

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let header = tableHeader(of: line) {
                // `nil` for `[[array]]`: a header we must never treat as a target, so that
                // `[[float]]` can never be mistaken for `[float]`.
                current = header
                if header == table { insertionPoint = index + 1 }
                index += 1
                continue
            }
            guard current == table else { index += 1; continue }

            if let name = keyName(of: line) {
                insertionPoint = index + 1
                if let edit = pending.first(where: { $0.key == name }) {
                    lines[index] = replacingValue(in: line, with: serialise(edit.value))
                    pending.removeAll { $0.key == name }
                }
            }
            index += 1
        }

        guard !pending.isEmpty else { return lines }

        if let point = insertionPoint {
            lines.insert(contentsOf: pending.map { "\($0.key) = \(serialise($0.value))" }, at: point)
        } else {
            // The table is not in the file at all. Append it, with a blank line to separate it
            // from whatever came before.
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("[\(table)]")
            lines.append(contentsOf: pending.map { "\($0.key) = \(serialise($0.value))" })
            lines.append("")
        }
        return lines
    }

    // MARK: - Line classification

    /// The table this line opens, or nil if it is not a single-table header. `[[float]]` returns
    /// nil *and* is treated as leaving the target table, which the caller relies on.
    private static func tableHeader(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        if trimmed.hasPrefix("[[") { return "" }        // an array of tables: never a target
        guard let close = trimmed.firstIndex(of: "]") else { return nil }
        let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : unquoted(name)
    }

    /// The bare or quoted key this line assigns to, or nil for a comment, a blank line, or
    /// anything without an `=` outside a string.
    private static func keyName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let equals = equalsIndex(in: line) else { return nil }
        let name = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : unquoted(name)
    }

    /// The first `=` that is not inside a quoted string.
    private static func equalsIndex(in line: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if escaped {
                escaped = false
            } else if c == "\\", quote == "\"" {
                escaped = true
            } else if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" {
                return nil                      // a comment before any `=`
            } else if c == "=" {
                return i
            }
            i = line.index(after: i)
        }
        return nil
    }

    private static func unquoted(_ s: String) -> String {
        guard s.count >= 2, let first = s.first, first == "\"" || first == "'", s.last == first
        else { return s }
        return String(s.dropFirst().dropLast())
    }

    /// Replaces only the span between `=` and any trailing comment, so the leading whitespace, the
    /// padding that keeps a block's `=` in a column, and the comment itself are all preserved.
    private static func replacingValue(in line: String, with value: String) -> String {
        guard let equals = equalsIndex(in: line) else { return line }
        let afterEquals = line.index(after: equals)
        let rest = line[afterEquals...]

        // Where the value starts, and where a trailing comment starts (outside any string).
        var quote: Character?
        var escaped = false
        var commentStart: String.Index?
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if escaped {
                escaped = false
            } else if c == "\\", quote == "\"" {
                escaped = true
            } else if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" {
                commentStart = i
                break
            }
            i = rest.index(after: i)
        }

        let leading = rest.prefix { $0 == " " || $0 == "\t" }
        let gap = leading.isEmpty ? " " : String(leading)
        if let commentStart {
            // Keep the run of whitespace immediately before the comment, so the comment column
            // survives too.
            let beforeComment = rest[rest.startIndex..<commentStart]
            let trailing = beforeComment.reversed().prefix { $0 == " " || $0 == "\t" }
            return String(line[line.startIndex...equals]) + gap + value
                + String(trailing) + String(rest[commentStart...])
        }
        return String(line[line.startIndex...equals]) + gap + value
    }

    // MARK: - Values

    /// Only the scalars this ever writes. Arrays and inline tables are not expressible on
    /// purpose: this is a value substituter, not a serialiser.
    private static func serialise(_ value: TOMLValue) -> String {
        switch value {
        case .string(let s):
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .int(let i):
            return String(i)
        case .double(let d):
            // `5.0` rather than `5`, so the value still reads as a float on the way back in.
            return d == d.rounded() ? String(format: "%.1f", d) : String(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .array, .table:
            preconditionFailure("TOMLEdit writes scalars only; got \(value)")
        }
    }
}
