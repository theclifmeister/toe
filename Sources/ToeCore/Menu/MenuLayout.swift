import Foundation

/// walker's stylesheet, as numbers.
///
/// Every value here is `omarchy-default/style.css` read literally: GTK's px is a point at scale
/// 1, so the mapping is one for one rather than a reinterpretation. They are `var`s so a test can
/// vary one, not because the menu retheme itself — only `fontSize` is exposed in the config, and
/// scaling the rest independently would be inventing a theme rather than porting one.
public struct MenuMetrics: Equatable, Sendable {
    /// `* { font-size: 18px }`
    public var fontSize: Double
    /// Measured by AppKit and handed in: ToeCore cannot ask a font how tall its line is, and
    /// hard-coding the answer here would drift the moment `font_size` changes. The one seam.
    public var lineHeight: Double
    /// `.box-wrapper { padding: 20px; border: 2px solid @border }`
    public var wrapperPadding: Double = 20
    public var borderWidth: Double = 2
    /// `.search-container { padding: 10px }`, and the box's 10px spacing below it.
    public var searchPadding: Double = 10
    public var boxSpacing: Double = 10
    /// `.item-box { padding-left: 14px }`, `.item-text-box { padding: 14px 0 }`
    public var itemPaddingLeft: Double = 14
    public var itemPaddingVertical: Double = 14
    /// `.normal-icons { -gtk-icon-size: 16px }`, `.item-image { margin-right: 14px }`
    public var iconSide: Double = 16
    public var iconGap: Double = 14
    /// True while the list is a search rather than one level of the tree — every row then has
    /// room for the path it was found at, and they all grow together so the list stays a grid.
    public var showsSubtitles: Bool = false
    /// Measured by AppKit like `lineHeight`, and for the same reason.
    public var subtitleLineHeight: Double = 0
    public var subtitleGap: Double = 2

    public init(fontSize: Double = 18, lineHeight: Double) {
        self.fontSize = fontSize
        self.lineHeight = lineHeight
    }
}

/// Where everything in the quick menu sits, in the panel's own coordinates: origin top-left,
/// y growing downward, which is what `Box` means everywhere else in ToeCore and what a flipped
/// `NSView` draws in. `MenuView` copies four numbers out of these and draws.
public enum MenuLayout {

    /// Border plus padding: the inset from the panel's edge to anything you can read.
    public static func contentInset(_ m: MenuMetrics) -> Double {
        m.borderWidth + m.wrapperPadding
    }

    public static func searchHeight(_ m: MenuMetrics) -> Double {
        m.searchPadding * 2 + m.lineHeight
    }

    public static func rowHeight(_ m: MenuMetrics) -> Double {
        let subtitle = m.showsSubtitles ? m.subtitleGap + m.subtitleLineHeight : 0
        return m.itemPaddingVertical * 2 + m.lineHeight + subtitle
    }

    /// Everything that is not a row: both insets, the search strip, and the gap below it.
    public static func chromeHeight(_ m: MenuMetrics) -> Double {
        contentInset(m) * 2 + searchHeight(m) + m.boxSpacing
    }

    private static func listTop(_ m: MenuMetrics) -> Double {
        contentInset(m) + searchHeight(m) + m.boxSpacing
    }

    // MARK: - The panel

    /// How big the panel wants to be, and how many rows that leaves room for.
    ///
    /// The second half is the point: the keybindings page is fifty rows, which at walker's
    /// metrics is taller than any display, so the height is clamped and the count it reports is
    /// what `MenuState` scrolls against. A menu that grows past the screen edge is not a menu.
    public static func size(rows: Int, width: Double, maxHeight: Double,
                            _ m: MenuMetrics) -> (size: Point, visibleRows: Int) {
        let row = rowHeight(m)
        let chrome = chromeHeight(m)
        let wanted = chrome + Double(rows) * row
        guard wanted > maxHeight else {
            return (Point(x: width, y: wanted), rows)
        }
        let fits = max(1, Int((maxHeight - chrome) / row))
        return (Point(x: width, y: chrome + Double(fits) * row), fits)
    }

    /// Dead centre of the usable area — walker's `valign: center; halign: center`. The usable
    /// area rather than the whole display, so the menu lands where the tiles land.
    public static func centred(size: Point, on usable: Box, verticalBias: Double = 0.5) -> Box {
        Box(x: usable.x + (usable.w - size.x) / 2,
            y: usable.y + (usable.h - size.y) * verticalBias,
            w: size.x, h: size.y)
    }

    // MARK: - The parts

    public static func searchFrame(width: Double, _ m: MenuMetrics) -> Box {
        Box(x: contentInset(m), y: contentInset(m),
            w: width - contentInset(m) * 2, h: searchHeight(m))
    }

    /// The baseline box for the query text, inside the search strip's own 10px padding.
    public static func searchTextOrigin(width: Double, _ m: MenuMetrics) -> Point {
        let strip = searchFrame(width: width, m)
        return Point(x: strip.x + m.searchPadding, y: strip.y + m.searchPadding)
    }

    /// `row` is the on-screen index, not the index into the filtered list — scrolling moves
    /// which item is drawn here, never where here is.
    public static func rowFrame(_ row: Int, width: Double, _ m: MenuMetrics) -> Box {
        Box(x: contentInset(m), y: listTop(m) + Double(row) * rowHeight(m),
            w: width - contentInset(m) * 2, h: rowHeight(m))
    }

    public static func iconFrame(inRow row: Box, _ m: MenuMetrics) -> Box {
        // Centred on the row as a whole, which is where the eye puts it when the row is two
        // lines tall — Omarchy's menu sets its icons the same way.
        Box(x: row.x + m.itemPaddingLeft, y: row.y + (row.h - m.iconSide) / 2,
            w: m.iconSide, h: m.iconSide)
    }

    /// With no icon the title takes the icon's place rather than leaving a hole, so a row that
    /// lost its glyph still reads as a row.
    public static func titleOrigin(inRow row: Box, hasIcon: Bool, _ m: MenuMetrics) -> Point {
        Point(x: row.x + m.itemPaddingLeft + (hasIcon ? m.iconSide + m.iconGap : 0),
              y: row.y + m.itemPaddingVertical)
    }

    /// The path a searched-for row was found at, under its title.
    public static func subtitleOrigin(inRow row: Box, hasIcon: Bool, _ m: MenuMetrics) -> Point {
        let title = titleOrigin(inRow: row, hasIcon: hasIcon, m)
        return Point(x: title.x, y: title.y + m.lineHeight + m.subtitleGap)
    }

    /// The second column. `column` is a fraction of the row for the keybindings page, where the
    /// arrows have to line up with each other; nil right-aligns it, which is where walker puts a
    /// lone value like `on`.
    public static func valueOrigin(inRow row: Box, valueWidth: Double, column: Double?,
                                   _ m: MenuMetrics) -> Point {
        let x = column.map { row.x + row.w * $0 }
            ?? (row.x + row.w - m.itemPaddingLeft - valueWidth)
        return Point(x: x, y: row.y + m.itemPaddingVertical)
    }

    /// What is left for the second column once the title has taken the room it needs. A value
    /// wider than this is truncated rather than drawn over the title — which is what a long one
    /// did before this existed.
    public static func valueSpace(inRow row: Box, titleEnd: Double, _ m: MenuMetrics) -> Double {
        max(0, row.x + row.w - m.itemPaddingLeft - m.iconGap - titleEnd)
    }

    /// The trailing `›` on a row that leads somewhere.
    public static func chevronOrigin(inRow row: Box, width: Double, _ m: MenuMetrics) -> Point {
        Point(x: row.x + row.w - m.itemPaddingLeft - width, y: row.y + m.itemPaddingVertical)
    }

    // MARK: - Hit testing

    /// Which on-screen row a click landed on — `WorkspaceStrip.hit`, one axis further along.
    /// The search strip and the padding below the last row are not rows.
    public static func row(at point: Point, rows: Int, width: Double, _ m: MenuMetrics) -> Int? {
        let inset = contentInset(m)
        guard point.x >= inset, point.x <= width - inset else { return nil }
        let top = listTop(m)
        guard point.y >= top else { return nil }
        let index = Int((point.y - top) / rowHeight(m))
        return index < rows ? index : nil
    }

    /// Keeps the selection on screen, moving by as few rows as will do it.
    public static func scroll(offset: Int, selection: Int, count: Int, visibleRows: Int) -> Int {
        guard count > visibleRows else { return 0 }
        var offset = min(max(offset, 0), count - visibleRows)
        if selection < offset { offset = selection }
        if selection >= offset + visibleRows { offset = selection - visibleRows + 1 }
        return min(max(offset, 0), count - visibleRows)
    }
}
