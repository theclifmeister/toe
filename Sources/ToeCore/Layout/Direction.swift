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

    /// Which way a list is walked: right and down go forward through it, left and up back.
    /// The grid has no use for this — a tree of tiles is not a list — but a workspace's
    /// detached windows are one, and this is what makes walking it one way the exact inverse
    /// of walking it the other.
    public var isForward: Bool { self == .right || self == .down }

    public var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}
