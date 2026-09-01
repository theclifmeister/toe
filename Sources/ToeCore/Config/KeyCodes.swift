import Foundation

/// Carbon modifier masks (`Events.h`). Declared here rather than imported so ToeCore stays
/// free of Carbon and remains testable.
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 0x0100)   // cmdKey
    public static let shift   = Modifiers(rawValue: 0x0200)   // shiftKey
    public static let option  = Modifiers(rawValue: 0x0800)   // optionKey
    public static let control = Modifiers(rawValue: 0x1000)   // controlKey

    public var description: String {
        var parts: [String] = []
        if contains(.control) { parts.append("ctrl") }
        if contains(.option) { parts.append("alt") }
        if contains(.shift) { parts.append("shift") }
        if contains(.command) { parts.append("cmd") }
        return parts.joined(separator: "-")
    }
}

/// Virtual key codes (`kVK_*`). Only the keys a window manager binds are listed.
public enum KeyCodes {
    public static let table: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,

        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16,
        "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,

        "equal": 0x18, "=": 0x18, "minus": 0x1B, "-": 0x1B,
        "rightbracket": 0x1E, "]": 0x1E, "leftbracket": 0x21, "[": 0x21,
        "quote": 0x27, "'": 0x27, "semicolon": 0x29, ";": 0x29,
        "backslash": 0x2A, "\\": 0x2A, "comma": 0x2B, ",": 0x2B,
        "slash": 0x2C, "/": 0x2C, "period": 0x2F, ".": 0x2F, "grave": 0x32, "`": 0x32,

        "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31,
        "backspace": 0x33, "delete": 0x33, "escape": 0x35, "esc": 0x35,
        "forwarddelete": 0x75, "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,

        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,

        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
        "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]

    public static func code(for name: String) -> UInt32? {
        table[name.lowercased()]
    }
}
