import Foundation

/// A parsed colour, in the `#RRGGBB` / `#RRGGBBAA` spellings Hyprland's `rgba()` uses.
///
/// Lives here rather than beside the AppKit code that draws it so it can be tested headlessly:
/// three surfaces need it now — the focus border, the quick menu's accent, and the theme
/// swatch — and a hex parser is exactly the kind of thing that quietly forks into three
/// slightly different versions.
public struct RGBA: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Parses `#RRGGBB` and `#RRGGBBAA`, with `#` or `0x` optional. Alpha defaults to opaque.
    /// Returns nil rather than a fallback colour: the caller knows what its fallback should be.
    public static func parse(hex: String) -> RGBA? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.hasPrefix("0x") || text.hasPrefix("0X") { text.removeFirst(2) }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else {
            return nil
        }
        let hasAlpha = text.count == 8
        return RGBA(r: Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
                    g: Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
                    b: Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
                    a: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }
}
