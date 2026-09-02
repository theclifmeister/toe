import Foundation

/// A binding, written the way Omarchy writes one: `SUPER + SHIFT + R`.
///
/// `Binding.describedShortcut` already exists and is deliberately left alone — it echoes the
/// config's own spelling (`super-shift-r`) back into an error message, which is what you want
/// when the thing being reported is the line you typed. This is the other direction: what the
/// keybindings list shows a reader who has never opened the config.
public enum ShortcutFormatter {

    public static func describe(_ binding: Binding, superKey: Modifiers) -> String {
        describe(modifiers: binding.modifiers, keyName: binding.keyName, superKey: superKey)
    }

    public static func describe(modifiers: Modifiers, keyName: String, superKey: Modifiers) -> String {
        var parts: [String] = []
        var rest = modifiers

        // SUPER first and its bits taken out, so the modifier that means SUPER is never also
        // printed under its own name. A binding written `alt-t` and one written `super-t` reach
        // this with the same mask and both read `SUPER + T` — correct rather than lossy: with
        // `super_key = "alt"` they are the same key.
        if !superKey.isEmpty, rest.contains(superKey) {
            parts.append("SUPER")
            rest.subtract(superKey)
        }
        if rest.contains(.control) { parts.append("CTRL") }
        if rest.contains(.option) { parts.append("ALT") }
        if rest.contains(.shift) { parts.append("SHIFT") }
        if rest.contains(.command) { parts.append("CMD") }

        parts.append(key(keyName))
        return parts.joined(separator: " + ")
    }

    /// Arrows as arrows, the named keys as words, and punctuation as the character it types —
    /// `SUPER + ,` reads as the key you press, where `SUPER + COMMA` reads as a config file.
    private static func key(_ name: String) -> String {
        switch name.lowercased() {
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return", "enter": return "ENTER"
        case "escape", "esc": return "ESC"
        case "delete", "backspace": return "DELETE"
        case "comma", ",": return ","
        case "period", ".": return "."
        case "slash", "/": return "/"
        case "backslash", "\\": return "\\"
        case "semicolon", ";": return ";"
        case "quote", "'": return "'"
        case "grave", "`": return "`"
        case "minus", "-": return "-"
        case "equal", "=": return "="
        case "leftbracket", "[": return "["
        case "rightbracket", "]": return "]"
        default: return name.uppercased()
        }
    }
}
