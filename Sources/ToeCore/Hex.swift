import Foundation

/// A colour, parsed. Four channels from 0 to 1, which is what CoreGraphics and AppKit both take.
public struct RGBA: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// The same colour at a different opacity — walker's `alpha(@base, 0.95)`.
    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }
}

/// Hyprland's colour spelling: `#RRGGBB` and `#RRGGBBAA`, with the alpha last.
///
/// Lives in ToeCore, away from the drawing that uses it, so the selftest can reach it — the same
/// reason `BorderGeometry` does. It answers nil rather than substituting a colour of its own:
/// the config layer wants to name a typo in the menu bar tooltip, and the drawing layer wants to
/// pick its own stand-in, and one function cannot do both. That is also the whole reason this
/// moved out of `BorderOverlay`, where a mistyped `active_start` quietly drew blue and was
/// mentioned nowhere.
public enum Hex {

    public static func rgba(_ text: String) -> RGBA? {
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("#") {
            body.removeFirst()
        } else if body.lowercased().hasPrefix("0x") {
            body.removeFirst(2)
        }
        // Checked before `UInt64.init`, which would otherwise accept a leading sign.
        guard body.count == 6 || body.count == 8,
              body.allSatisfy(\.isHexDigit),
              let value = UInt64(body, radix: 16)
        else { return nil }

        func channel(_ shift: UInt64) -> Double { Double((value >> shift) & 0xFF) / 255 }

        if body.count == 6 {
            return RGBA(r: channel(16), g: channel(8), b: channel(0), a: 1)
        }
        return RGBA(r: channel(24), g: channel(16), b: channel(8), a: channel(0))
    }
}
