import Foundation

/// walker's metrics, so toe's menu is the same size and shape as the one it is reproducing.
///
/// Omarchy calls `omarchy-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630`. Those
/// two numbers are kept as-is. 295pt is tight for a long window title, which is why the row
/// renderer gives the title priority and truncates the trailing detail instead: walker is
/// fixed-width, and growing the panel per submenu would break the resemblance more than a
/// truncated hint does.
public enum QuickMenuGeometry {

    public static let width: Double = 295
    public static let maxHeight: Double = 630
    public static let promptHeight: Double = 40
    public static let rowHeight: Double = 30
    public static let padding: Double = 8
    public static let cornerRadius: Double = 12
    /// The hairline between the prompt and the list.
    public static let separatorHeight: Double = 1

    /// How many rows fit. Never less than one — an empty list still needs somewhere to say so.
    public static func visibleRows(maxHeight: Double = QuickMenuGeometry.maxHeight) -> Int {
        let forRows = maxHeight - chrome
        return max(1, Int((forRows / rowHeight).rounded(.down)))
    }

    /// Everything that is not a row: the prompt line, the separator, and the padding above and
    /// below the list.
    public static var chrome: Double { promptHeight + separatorHeight + 2 * padding }

    public static func height(rowCount: Int) -> Double {
        min(maxHeight, chrome + Double(max(0, rowCount)) * rowHeight)
    }

    /// Centred on the given usable area, in AX coordinates. Slightly above centre — walker sits
    /// where your eyes already are rather than in the dead middle of the screen.
    public static func frame(rowCount: Int, on usable: Box) -> Box {
        let h = height(rowCount: rowCount)
        let w = min(width, usable.w)
        let x = usable.x + (usable.w - w) / 2
        let y = usable.y + max(0, (usable.h - h) * 0.35)
        return Box(x: x.rounded(), y: y.rounded(), w: w, h: h)
    }
}
