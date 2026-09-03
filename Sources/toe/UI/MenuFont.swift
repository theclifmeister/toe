import AppKit
import CoreText
import ToeCore

/// The quick menu's typeface, and the glyphs its rows lead with.
///
/// Omarchy's walker asks for `monospace`, which its fontconfig resolves to JetBrainsMono Nerd
/// Font — so that is the font the menu in the screenshots is drawn in, text and icons alike.
/// toe ships it rather than looking for it: registered at **process scope**, so nothing is
/// installed, no permission is asked, and it never appears in another application's font menu.
///
/// Shipping it is also what makes the menu look the same on every Mac. Probing for whichever
/// Nerd Font the user happens to have would work — most people who want these glyphs have one —
/// but Hack, JetBrainsMono and CaskaydiaCove have different advances, so two people running the
/// same config would get different row widths. `StatusItem` draws its one marker by hand for the
/// same reason it cannot do so here: a rounded square is a bezier path, and a gear is not.
enum MenuFont {

    private static let familyName = "JetBrainsMono Nerd Font"
    /// `nf-fa-gear`. Any patch level that has the Font Awesome block has every glyph below, so
    /// one probe answers for the set.
    private static let probe: Unicode.Scalar = "\u{F013}"

    /// nil once resolution has run and found nothing — see `family(size:)`.
    private static var resolved: NSFont?
    private static var didResolve = false
    private static var didRegister = false

    // MARK: - The font

    /// Registers the bundled font with this process. Idempotent: the menu opens as often as the
    /// user presses the key, and CoreText answers a second registration of the same file with an
    /// error rather than a shrug.
    static func register() {
        guard !didRegister else { return }
        didRegister = true
        guard let url = Bundle.main.url(forResource: "JetBrainsMonoNerdFont-Regular",
                                        withExtension: "ttf") else {
            Log.error("menu font: JetBrainsMonoNerdFont-Regular.ttf is missing from the bundle "
                      + "— falling back to the system monospace font and SF Symbols")
            return
        }
        var error: Unmanaged<CFError>?
        // `.process`, not `.user`: toe is a window manager, not a font installer.
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
            Log.error("menu font: could not register the bundled font (\(reason))")
            return
        }
    }

    /// The text font at a size, or the system monospace if the bundled one did not register.
    static func text(size: Double) -> NSFont {
        if let font = family(size: size) { return font }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The icon font — the same face. nil when it is unavailable or lacks the glyphs, which is
    /// what sends the drawing to SF Symbols.
    static func icons(size: Double) -> NSFont? {
        guard let font = family(size: size), covers(font, probe) else { return nil }
        return font
    }

    private static func family(size: Double) -> NSFont? {
        if !didResolve {
            didResolve = true
            resolved = NSFont(name: familyName, size: 12)
            if let font = resolved, covers(font, probe) {
                Log.info("menu font: \(familyName), bundled")
            } else if resolved != nil {
                Log.error("menu font: \(familyName) has no icon glyphs — using SF Symbols")
            } else {
                Log.error("menu font: \(familyName) unavailable — using the system monospace "
                          + "font and SF Symbols")
            }
        }
        guard resolved != nil else { return nil }
        return NSFont(name: familyName, size: size)
    }

    /// A name match is not coverage: `NSFont(name:)` will hand back a font that has none of the
    /// private-use plane, and the result would be a row of tofu. Ask for the glyph instead.
    private static func covers(_ font: NSFont, _ scalar: Unicode.Scalar) -> Bool {
        var characters = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else {
            return false
        }
        return glyphs.allSatisfy { $0 != 0 }
    }

    // MARK: - The glyphs

    /// All from the Font Awesome block, the oldest and most universally present part of a Nerd
    /// Font patch — chosen over the Material Design equivalents for exactly that reason.
    static func glyph(for icon: MenuItem.Icon) -> String {
        switch icon {
        case .gear:      return "\u{F013}"   // nf-fa-gear
        case .book:      return "\u{F02D}"   // nf-fa-book
        case .keyboard:  return "\u{F11C}"   // nf-fa-keyboard_o
        case .pencil:    return "\u{F040}"   // nf-fa-pencil
        case .power:     return "\u{F011}"   // nf-fa-power_off
        case .toggleOn:  return "\u{F205}"   // nf-fa-toggle_on
        case .toggleOff: return "\u{F204}"   // nf-fa-toggle_off
        case .paintbrush: return "\u{F1FC}"  // nf-fa-paint_brush
        case .droplet:   return "\u{F043}"   // nf-fa-tint
        case .image:     return "\u{F03E}"   // nf-fa-picture_o
        }
    }

    /// The fallback, when there is no icon font. Apple's iconography rather than Omarchy's,
    /// which is the honest signal that the bundled font did not load.
    static func symbolName(for icon: MenuItem.Icon) -> String {
        switch icon {
        case .gear:      return "gearshape"
        case .book:      return "book"
        case .keyboard:  return "keyboard"
        case .pencil:    return "pencil"
        case .power:     return "power"
        case .toggleOn:  return "switch.2"
        case .toggleOff: return "switch.2"
        case .paintbrush: return "paintbrush"
        case .droplet:   return "drop"
        case .image:     return "photo"
        }
    }
}
