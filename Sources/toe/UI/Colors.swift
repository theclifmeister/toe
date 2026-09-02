import AppKit
import ToeCore

/// `RGBA` is ToeCore's, so that hex parsing can be tested without AppKit; these are the two
/// conversions the drawing side needs, in one place rather than in each of its callers.
extension NSColor {
    convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}

enum Colors {
    /// A configured colour, or the stand-in the drawing chooses when it will not parse. The
    /// config layer has already warned about it by the time this runs — see `Config.parse` —
    /// so this is the second half of that split, not a silent swallow.
    static func rgba(_ hex: String, or fallback: RGBA) -> RGBA {
        Hex.rgba(hex) ?? fallback
    }

    static func cgColor(_ rgba: RGBA) -> CGColor {
        CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}
