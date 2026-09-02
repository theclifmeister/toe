import Foundation

/// One hotkey.
public struct Binding: Equatable {
    public let modifiers: Modifiers
    public let keyCode: UInt32
    public let keyName: String
    public let command: Command
    /// The binding string exactly as written in the config, for error messages.
    public let source: String

    public var describedShortcut: String {
        let mods = modifiers.description
        return mods.isEmpty ? keyName : "\(mods)-\(keyName)"
    }
}

public enum BindingError: Error, CustomStringConvertible {
    case unknownKey(String)
    case noKey(String)

    public var description: String {
        switch self {
        case .unknownKey(let k): return "unknown key '\(k)'"
        case .noKey(let s): return "no key in '\(s)'"
        }
    }
}

public enum BindingParser {

    private static let modifierNames: [String: Modifiers] = [
        "shift": .shift,
        "ctrl": .control, "control": .control,
        "cmd": .command, "command": .command, "meta": .command,
        "alt": .option, "opt": .option, "option": .option,
    ]

    /// Parses both spellings so bindings can be pasted from either a dash-style config
    /// (`"alt-shift-1"`) or an Omarchy one (`"SUPER SHIFT, 1"`).
    ///
    /// `super` resolves to whatever `general.super_key` says — Option by default, which is
    /// the same physical key position as SUPER on a PC keyboard and leaves ⌘-anything alone.
    public static func parse(_ spec: String, superKey: Modifiers) throws -> (Modifiers, UInt32, String) {
        var rest = spec.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: " ")
        var modifiers: Modifiers = []

        // Consume modifier tokens greedily from the left, so a literal `-` key still works.
        outer: while true {
            rest = rest.trimmingCharacters(in: .whitespaces)
            let lowered = rest.lowercased()
            for (name, mod) in modifierNames.sorted(by: { $0.key.count > $1.key.count }) {
                if let separatorIndex = matchModifier(lowered, name) {
                    modifiers.insert(mod)
                    rest = String(rest[rest.index(rest.startIndex, offsetBy: separatorIndex)...])
                    continue outer
                }
            }
            if let separatorIndex = matchModifier(lowered, "super") {
                modifiers.insert(superKey)
                rest = String(rest[rest.index(rest.startIndex, offsetBy: separatorIndex)...])
                continue outer
            }
            break
        }

        let key = rest.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw BindingError.noKey(spec) }
        guard let code = KeyCodes.code(for: key) else { throw BindingError.unknownKey(key) }
        return (modifiers, code, key.lowercased())
    }

    /// If `lowered` starts with `name` followed by a separator, returns the offset just past
    /// the separator. There must be something after it — so `"minus"` is never eaten as a
    /// modifier and `"alt-"` binds the `-` key.
    private static func matchModifier(_ lowered: String, _ name: String) -> Int? {
        guard lowered.hasPrefix(name), lowered.count > name.count else { return nil }
        let separator = Array(lowered)[name.count]
        guard separator == "-" || separator == "+" || separator == " " else { return nil }
        guard lowered.count > name.count + 1 else { return nil }
        return name.count + 1
    }
}
