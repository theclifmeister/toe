import Foundation

public enum TOMLValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    public var arrayValue: [TOMLValue]? { if case .array(let a) = self { return a }; return nil }
    public var tableValue: [String: TOMLValue]? { if case .table(let t) = self { return t }; return nil }
}

public struct TOMLError: Error, CustomStringConvertible {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }
}

/// A deliberately small TOML parser: tables, arrays of tables, bare and quoted keys, basic
/// and literal strings, integers, floats, booleans, arrays and inline tables. That covers
/// everything toe's config uses and keeps the package dependency-free.
///
/// Not supported: multi-line strings, dates, and dotted keys on the left of `=`.
public enum TOML {

    public static func parse(_ text: String) throws -> [String: TOMLValue] {
        var parser = Parser(text)
        return try parser.parseDocument()
    }

    private final class Node {
        var values: [String: TOMLValue] = [:]
        var tables: [String: Node] = [:]
        var arrays: [String: [Node]] = [:]

        func asTable() -> [String: TOMLValue] {
            var out = values
            for (k, v) in tables { out[k] = .table(v.asTable()) }
            for (k, v) in arrays { out[k] = .array(v.map { .table($0.asTable()) }) }
            return out
        }
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        var line = 1

        init(_ text: String) { chars = Array(text) }

        var atEnd: Bool { i >= chars.count }
        var peek: Character? { atEnd ? nil : chars[i] }

        mutating func advance() -> Character {
            let c = chars[i]
            i += 1
            if c == "\n" { line += 1 }
            return c
        }

        mutating func skipInsignificant(stopAtNewline: Bool = false) {
            while !atEnd {
                let c = chars[i]
                if c == "#" {
                    while !atEnd && chars[i] != "\n" { i += 1 }
                } else if c == "\n" {
                    if stopAtNewline { return }
                    _ = advance()
                } else if c == " " || c == "\t" || c == "\r" {
                    i += 1
                } else {
                    return
                }
            }
        }

        mutating func parseDocument() throws -> [String: TOMLValue] {
            let root = Node()
            var current = root

            while true {
                skipInsignificant()
                guard !atEnd else { break }

                if peek == "[" {
                    current = try parseHeader(root: root)
                } else {
                    let key = try parseKey()
                    skipInsignificant(stopAtNewline: true)
                    guard peek == "=" else {
                        throw TOMLError(line: line, message: "expected '=' after key '\(key)'")
                    }
                    i += 1
                    skipInsignificant(stopAtNewline: true)
                    let value = try parseValue()
                    if current.values[key] != nil {
                        throw TOMLError(line: line, message: "duplicate key '\(key)'")
                    }
                    current.values[key] = value
                }
            }
            return root.asTable()
        }

        mutating func parseHeader(root: Node) throws -> Node {
            i += 1  // '['
            let isArray = peek == "["
            if isArray { i += 1 }

            var path: [String] = []
            while true {
                skipInsignificant(stopAtNewline: true)
                path.append(try parseKey())
                skipInsignificant(stopAtNewline: true)
                if peek == "." { i += 1; continue }
                break
            }

            guard peek == "]" else { throw TOMLError(line: line, message: "unterminated table header") }
            i += 1
            if isArray {
                guard peek == "]" else { throw TOMLError(line: line, message: "expected ']]'") }
                i += 1
            }
            guard !path.isEmpty else { throw TOMLError(line: line, message: "empty table header") }

            var node = root
            for key in path.dropLast() {
                if let existing = node.arrays[key]?.last {
                    node = existing
                } else {
                    if node.tables[key] == nil { node.tables[key] = Node() }
                    node = node.tables[key]!
                }
            }

            let last = path[path.count - 1]
            if isArray {
                let child = Node()
                node.arrays[last, default: []].append(child)
                return child
            } else {
                if node.tables[last] == nil { node.tables[last] = Node() }
                return node.tables[last]!
            }
        }

        mutating func parseKey() throws -> String {
            guard let c = peek else { throw TOMLError(line: line, message: "expected a key") }
            if c == "\"" || c == "'" { return try parseString() }
            var out = ""
            while let c = peek, c.isLetter || c.isNumber || c == "_" || c == "-" {
                out.append(c)
                i += 1
            }
            guard !out.isEmpty else {
                throw TOMLError(line: line, message: "expected a key, found '\(c)'")
            }
            return out
        }

        mutating func parseString() throws -> String {
            let quote = advance()
            var out = ""
            while true {
                guard !atEnd else { throw TOMLError(line: line, message: "unterminated string") }
                let c = advance()
                if c == quote { return out }
                if c == "\n" { throw TOMLError(line: line, message: "unterminated string") }
                if c == "\\" && quote == "\"" {
                    guard !atEnd else { throw TOMLError(line: line, message: "unterminated escape") }
                    let e = advance()
                    switch e {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "\"": out.append("\"")
                    case "'": out.append("'")
                    case "\\": out.append("\\")
                    case "0": out.append("\0")
                    default: throw TOMLError(line: line, message: "unknown escape '\\\(e)'")
                    }
                } else {
                    out.append(c)
                }
            }
        }

        mutating func parseValue() throws -> TOMLValue {
            guard let c = peek else { throw TOMLError(line: line, message: "expected a value") }

            switch c {
            case "\"", "'":
                return .string(try parseString())
            case "[":
                i += 1
                var items: [TOMLValue] = []
                while true {
                    skipInsignificant()
                    if peek == "]" { i += 1; break }
                    items.append(try parseValue())
                    skipInsignificant()
                    if peek == "," { i += 1; continue }
                    skipInsignificant()
                    guard peek == "]" else { throw TOMLError(line: line, message: "expected ',' or ']' in array") }
                    i += 1
                    break
                }
                return .array(items)
            case "{":
                i += 1
                var table: [String: TOMLValue] = [:]
                while true {
                    skipInsignificant(stopAtNewline: true)
                    if peek == "}" { i += 1; break }
                    let key = try parseKey()
                    skipInsignificant(stopAtNewline: true)
                    guard peek == "=" else { throw TOMLError(line: line, message: "expected '=' in inline table") }
                    i += 1
                    skipInsignificant(stopAtNewline: true)
                    table[key] = try parseValue()
                    skipInsignificant(stopAtNewline: true)
                    if peek == "," { i += 1; continue }
                    guard peek == "}" else { throw TOMLError(line: line, message: "expected ',' or '}' in inline table") }
                    i += 1
                    break
                }
                return .table(table)
            default:
                var raw = ""
                while let c = peek, !",]}#\n".contains(c) {
                    raw.append(c)
                    i += 1
                }
                let token = raw.trimmingCharacters(in: .whitespaces)
                if token == "true" { return .bool(true) }
                if token == "false" { return .bool(false) }
                let cleaned = token.replacingOccurrences(of: "_", with: "")
                if !cleaned.contains(".") && !cleaned.lowercased().contains("e"), let n = Int(cleaned) {
                    return .int(n)
                }
                if let d = Double(cleaned) { return .double(d) }
                throw TOMLError(line: line, message: "could not parse value '\(token)'")
            }
        }
    }
}
