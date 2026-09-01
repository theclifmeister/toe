import Foundation

/// A keystroke, once the quick menu has decided what it means.
public enum MenuKey: Equatable {
    case character(Character)
    case backspace
    case deleteWord
    case clearLine
    case up, down, home, end, pageUp, pageDown
    case enter, escape, tab
}

public extension MenuKey {

    /// Translates a raw keystroke. `characters` must be `NSEvent.charactersIgnoringModifiers`.
    ///
    /// That last part is load-bearing, and it is why this mapping lives in ToeCore where the
    /// selftest can pin it: SUPER *is* Option by default, so a user who opens the menu with
    /// ⌥Space and keeps ⌥ held while typing produces `å ∂ ƒ` in `event.characters`. Option-modified
    /// letters have to come through as the plain letter or the filter is unusable for exactly the
    /// people most likely to be using it.
    ///
    /// Returns nil for anything the menu should not act on — Command-anything, in particular, so
    /// ⌘Q and ⌘Tab still mean what they always mean.
    static func from(keyCode: UInt32, characters: String, modifiers: Modifiers) -> MenuKey? {
        if modifiers.contains(.command) { return nil }

        switch keyCode {
        case 0x7E: return .up
        case 0x7D: return .down
        case 0x24, 0x4C: return .enter          // Return and the keypad's Enter
        case 0x35: return .escape
        case 0x33: return .backspace
        case 0x30: return .tab
        case 0x73: return .home
        case 0x77: return .end
        case 0x74: return .pageUp
        case 0x79: return .pageDown
        default: break
        }

        // Emacs-style navigation, as walker and every dmenu-alike accept it.
        if modifiers.contains(.control) {
            switch characters.lowercased() {
            case "n": return .down
            case "p": return .up
            case "w": return .deleteWord
            case "u": return .clearLine
            case "a": return .home
            case "e": return .end
            case "h": return .backspace
            default: return nil
            }
        }

        guard let character = characters.first, characters.count == 1 else { return nil }
        // Printable only: no control characters, no function-key private-use scalars.
        guard !character.isNewline,
              let scalar = character.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value < 0xE000
        else { return nil }
        return .character(character)
    }
}
