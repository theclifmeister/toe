import Foundation

public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down

    /// Accepts Hyprland's single-letter form (`l`, `r`, `u`/`t`, `d`/`b`) and full words.
    public init?(_ s: String) {
        switch s.lowercased() {
        case "l", "left":          self = .left
        case "r", "right":         self = .right
        case "u", "t", "up", "top": self = .up
        case "d", "b", "down", "bottom": self = .down
        default: return nil
        }
    }

    /// The single letter Hyprland writes, which is also what `Direction.init` reads back.
    public var hyprlandLetter: String {
        switch self {
        case .left: return "l"
        case .right: return "r"
        case .up: return "u"
        case .down: return "d"
        }
    }

    /// For menu rows and anything else user-facing.
    public var label: String { rawValue.capitalized }

    public var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}
