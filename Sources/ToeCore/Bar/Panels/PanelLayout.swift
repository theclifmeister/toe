import Foundation

/// The type scale a panel draws in — `Style.font` upstream, as roles.
public enum PanelFont: Equatable, Hashable, Sendable, CaseIterable {
    case caption, bodySmall, body, subtitle, title, heading, display, displayLarge
}

/// Omarchy's `Style` tokens for a popup, at the bar's size.
///
/// Upstream every one of these derives from `[font] base-size` through `Style.fontPx` and
/// `Style.space`, and a panel scales as a whole when the base size changes. toe's base is
/// `[bar] font_size` — a panel belongs to the bar, and reads at the bar's size rather than the
/// quick menu's 18pt, which is a menu you look at across the room. The chrome — border, the
/// wash under the cursor, the colours — is the quick menu's, as #177 settled, and comes from
/// `[menu]` through the view; only the numbers are here.
public struct PanelMetrics: Equatable, Sendable {
    /// `Style.font.body` at `[font] base-size` 12.
    public static let referenceFontSize: Double = 12

    public var fontSize: Double
    /// A line's height as a multiple of the point size, measured by AppKit and handed in —
    /// ToeCore cannot ask a font how tall it is, the same seam as `MenuMetrics.lineHeight`.
    /// The default is JetBrainsMono's own (ascent 1020, descent 300 per em), so the selftest
    /// lays panels out at the numbers a real one draws.
    public var lineRatio: Double = 1.32

    public init(fontSize: Double = referenceFontSize) {
        self.fontSize = fontSize
    }

    /// `Style.fontScale`.
    var scale: Double { fontSize / Self.referenceFontSize }

    /// `Style.space`: the token at 12px, scaled and rounded, never under 1.
    public func space(_ base: Double) -> Double { max(1, (base * scale).rounded()) }

    /// `Style.fontPx`: the role's multiplier over the base, rounded, never under 1.
    public func pointSize(_ font: PanelFont) -> Double {
        let multiplier: Double
        switch font {
        case .caption:      multiplier = 0.833
        case .bodySmall:    multiplier = 0.917
        case .body:         multiplier = 1
        case .subtitle:     multiplier = 1.083
        case .title:        multiplier = 1.167
        case .heading:      multiplier = 1.333
        case .display:      multiplier = 2
        case .displayLarge: multiplier = 2.333
        }
        return max(1, (fontSize * multiplier).rounded())
    }

    public func lineHeight(_ font: PanelFont) -> Double {
        (pointSize(font) * lineRatio).rounded(.up)
    }

    // MARK: - `Style.spacing` and the card

    /// `popupPadding`: the inset from the card's border to its content.
    public var padding: Double { space(14) }
    /// The card's border, `Border.surfaceSpec("popups", …, space(2))`.
    public var borderWidth: Double { space(2) }
    /// `Style.gapsOut`: between the bar and the card, and from the card to the screen edge.
    public var gap: Double { space(5) }
    /// `KeyboardPanel.contentWidth`: `space(380)` for every panel but the calendar's 560.
    public var width: Double { space(380) }
    public var calendarWidth: Double { space(560) }
    /// The column's spacing between blocks — hero, bar, stats, separator.
    public var blockGap: Double { space(14) }
    /// Between a section header and its first row.
    public var headerGap: Double { space(6) }
    /// Between the rows of a list. Upstream's lists disagree with each other — 4, 6 and 10 —
    /// and one number keeps the six panels to one rhythm.
    public var listGap: Double { space(6) }
    /// `Style.spacing.xl`: the vertical padding of a one-line list row.
    public var rowPadding: Double { space(10) }
    /// `Style.spacing.rowPaddingX`: the vertical padding of a two-line one.
    public var tallRowPadding: Double { space(12) }
    /// `PanelSlider`: the track's inset from the row, its height and the knob's size.
    public var sliderInset: Double { space(6) }
    public var trackHeight: Double { max(4, (space(28) * 0.11).rounded()) }
    public var knobSize: Double { max(14, (space(28) * 0.38).rounded()) }
    /// `ToggleSwitch`: 22 tall, 1.9 as wide, ringed by `cursorPad` 6 on every side.
    public var toggleHeight: Double { max(22, (space(28) * 0.55).rounded()) }
    public var toggleWidth: Double { (toggleHeight * 1.9).rounded() }
    public var togglePad: Double { space(6) }
    /// The gap between the hero's glyph and its labels, `space(14)`; between a list row's
    /// glyph and its label, `space(8)`; the glyph's slot in a list row, `space(22)`.
    public var heroGap: Double { space(14) }
    public var glyphGap: Double { space(8) }
    public var glyphSlot: Double { space(22) }
    /// `ensureCursorVisible`'s margin: how close to the edge the cursor's row may scroll.
    public var scrollMargin: Double { space(6) }
    /// The calendar's grid, `panels/clock/Panel.qml`: a 52 × 34 cell, 2 apart, a 32-wide week
    /// column, a 14 gutter between it and the days, a 16-tall heading row 3 above the grid.
    public var calendarCellWidth: Double { space(52) }
    public var calendarCellHeight: Double { space(34) }
    public var calendarCellGap: Double { space(2) }
    public var calendarWeekColumn: Double { space(32) }
    public var calendarGutter: Double { space(14) }
    public var calendarHeadingHeight: Double { space(16) }
    public var calendarHeadingGap: Double { space(3) }
    /// A chevron's hit zone at either end of the month line.
    public var monthChevronZone: Double { space(40) }
}

/// Where everything in a panel sits: the card's own coordinates, origin top-left, y downward,
/// the way `MenuLayout` and `Box` have it. Pure, so the selftest lays a panel out by hand.
public enum PanelLayout {

    /// Border plus padding: the inset from the card's edge to anything you can read.
    public static func contentInset(_ m: PanelMetrics) -> Double {
        m.borderWidth + m.padding
    }

    /// How tall a row of this kind is, from the pieces upstream stacks in it.
    public static func rowHeight(_ row: PanelRow, _ m: PanelMetrics) -> Double {
        switch row.kind {
        case .hero(_, _, _, let trailing):
            // `PanelHero.implicitHeight`: the tallest of the glyph, the two labels and the
            // trailing control — a switch with its cursor ring, or the display-large text.
            let labels = m.lineHeight(.title) + m.space(2) + m.lineHeight(.caption)
            var tallest = max(m.lineHeight(.display), labels)
            switch trailing {
            case .toggle: tallest = max(tallest, m.toggleHeight + m.togglePad * 2)
            case .text:   tallest = max(tallest, m.lineHeight(.displayLarge))
            case nil:     break
            }
            return tallest
        case .header:
            // `PanelSectionHeader.topPadding`: the Nerd Font's outlines run past its ascent,
            // and a header at the top of a clipped list lost the top of its letters to the
            // clip. The overshoot is reserved above every header.
            return m.lineHeight(.caption) + (m.pointSize(.caption) * 0.15).rounded(.up)
        case .slider:
            // `PanelSlider.implicitHeight`, plus `controlGap` for the `CursorSurface` around it.
            return max(m.space(22), m.knobSize + m.space(6)) + m.space(8)
        case .progress:
            return m.space(8)
        case .info:
            return m.lineHeight(.bodySmall)
        case .pick(_, _, let detail, _):
            // One line at title size for the glyph, or two — name and status — at body and
            // caption, as the Bluetooth and network rows are.
            if detail == nil { return m.lineHeight(.title) + m.rowPadding }
            return m.lineHeight(.body) + m.space(1) + m.lineHeight(.caption) + m.tallRowPadding
        case .separator:
            return 1
        case .action, .note:
            return m.lineHeight(.body) + m.rowPadding
        case .calendar:
            return m.calendarHeadingHeight + m.calendarHeadingGap
                + m.calendarCellHeight * 6 + m.calendarCellGap * 5
        case .monthNav:
            // `monthNav.height`: the label's line plus `space(10)`.
            return m.lineHeight(.body) + m.rowPadding
        }
    }

    /// The room between two rows. The column upstream is blocks 14 apart, and inside a block
    /// a header is 6 above its first row and list rows are a few apart; a separator is its
    /// own block, so it gets the block gap on both sides.
    public static func gap(after previous: PanelRow, before next: PanelRow, _ m: PanelMetrics) -> Double {
        switch (previous.kind, next.kind) {
        case (.header, _):
            return m.headerGap
        case (.info, .info), (.progress, .info):
            // `Style.spacing.labelGap` between stat lines, and the stats hang off the bar.
            return m.space(4)
        case (.pick, .pick), (.slider, .pick), (.pick, .action), (.note, .action):
            return m.listGap
        case (.hero, .calendar):
            // The grid sits `space(18)` under the hero's block, past the column's own 8.
            return m.space(26)
        case (.calendar, .monthNav):
            return m.space(8)
        default:
            return m.blockGap
        }
    }

    /// Every row's frame, top to bottom, and how tall the card wants to be for them.
    public static func frames(_ rows: [PanelRow], width: Double,
                              _ m: PanelMetrics) -> (frames: [Box], height: Double) {
        let inset = contentInset(m)
        var y = inset
        var frames: [Box] = []
        for (index, row) in rows.enumerated() {
            if index > 0 { y += gap(after: rows[index - 1], before: row, m) }
            let height = rowHeight(row, m)
            frames.append(Box(x: inset, y: y, w: width - inset * 2, h: height))
            y += height
        }
        return (frames, y + inset)
    }

    // MARK: - The card on the screen

    /// The tallest a card may be under the bar on `display`, `KeyboardPanel.availableCardHeight`:
    /// the screen less the bar, the gap to it and the margin at the bottom.
    public static func maxHeight(display: Box, barHeight: Double, _ m: PanelMetrics) -> Double {
        max(120, display.h - barHeight - m.gap * 2)
    }

    /// Where the card goes: centred under the widget's slot and `gap` below the bar,
    /// `KeyboardPanel.cardOrigin` for a top bar — slid along the bar to stay `gap` inside
    /// the display's edges, so a panel under the rightmost widget hangs inward rather than
    /// off the screen, and its width and height cut to what fits.
    ///
    /// `slotMidX` is in the display's own coordinates, as the bar lays its slots out; the
    /// answer is in Accessibility coordinates, ready for the window.
    public static func anchor(size: Point, underSlotAt slotMidX: Double, barHeight: Double,
                              display: Box, _ m: PanelMetrics) -> Box {
        let width = min(size.x, display.w - m.gap * 2)
        let height = min(size.y, maxHeight(display: display, barHeight: barHeight, m))
        var x = display.x + slotMidX - width / 2
        x = max(display.x + m.gap, min(x, display.maxX - width - m.gap))
        return Box(x: x.rounded(), y: (display.y + barHeight + m.gap).rounded(), w: width, h: height)
    }

    // MARK: - Hit testing and sliders

    /// Which row a point is on, or nil between rows and over the padding.
    public static func row(at point: Point, frames: [Box]) -> Int? {
        frames.firstIndex { point.x >= $0.x && point.x < $0.maxX && point.y >= $0.y && point.y < $0.maxY }
    }

    /// A slider's track inside its row: inset each side, the track's height, centred.
    public static func sliderTrack(inRow row: Box, _ m: PanelMetrics) -> Box {
        Box(x: row.x + m.sliderInset, y: row.y + (row.h - m.trackHeight) / 2,
            w: max(1, row.w - m.sliderInset * 2), h: m.trackHeight)
    }

    /// The value a pointer at `x` asks for — `PanelSlider.valueFromX`, clamped to the track.
    public static func sliderValue(x: Double, inRow row: Box, _ m: PanelMetrics) -> Double {
        let track = sliderTrack(inRow: row, m)
        return max(0, min(1, (x - track.x) / track.w))
    }

    /// Where the knob sits for a value: centred on the fill's end, kept inside the track.
    public static func knobFrame(value: Double, inRow row: Box, _ m: PanelMetrics) -> Box {
        let track = sliderTrack(inRow: row, m)
        let x = max(track.x, min(track.maxX - m.knobSize, track.x + track.w * value - m.knobSize / 2))
        return Box(x: x, y: track.y + track.h / 2 - m.knobSize / 2, w: m.knobSize, h: m.knobSize)
    }

    // MARK: - The calendar

    /// The grid's own box inside its row: `calendarWeekColumn + gap + gutter + gap + 7 cells`
    /// wide, centred, the full row tall.
    public static func calendarGrid(inRow row: Box, _ m: PanelMetrics) -> Box {
        let width = m.calendarWeekColumn + m.calendarCellGap + m.calendarGutter + m.calendarCellGap
            + m.calendarCellWidth * 7 + m.calendarCellGap * 6
        return Box(x: row.x + ((row.w - width) / 2).rounded(), y: row.y, w: width, h: row.h)
    }

    /// The `W` heading over the week numbers — the week-start toggle.
    public static func weekStartCell(inRow row: Box, _ m: PanelMetrics) -> Box {
        let grid = calendarGrid(inRow: row, m)
        return Box(x: grid.x, y: grid.y, w: m.calendarWeekColumn, h: m.calendarHeadingHeight)
    }

    /// The heading over day column `column` (0…6).
    public static func weekdayHeading(_ column: Int, inRow row: Box, _ m: PanelMetrics) -> Box {
        let grid = calendarGrid(inRow: row, m)
        let x = grid.x + m.calendarWeekColumn + m.calendarCellGap + m.calendarGutter + m.calendarCellGap
            + Double(column) * (m.calendarCellWidth + m.calendarCellGap)
        return Box(x: x, y: grid.y, w: m.calendarCellWidth, h: m.calendarHeadingHeight)
    }

    /// The week number beside week `week` (0…5).
    public static func weekNumberCell(_ week: Int, inRow row: Box, _ m: PanelMetrics) -> Box {
        let grid = calendarGrid(inRow: row, m)
        let y = grid.y + m.calendarHeadingHeight + m.calendarHeadingGap
            + Double(week) * (m.calendarCellHeight + m.calendarCellGap)
        return Box(x: grid.x, y: y, w: m.calendarWeekColumn, h: m.calendarCellHeight)
    }

    /// Day `column` of week `week`.
    public static func dayCell(week: Int, column: Int, inRow row: Box, _ m: PanelMetrics) -> Box {
        let heading = weekdayHeading(column, inRow: row, m)
        let number = weekNumberCell(week, inRow: row, m)
        return Box(x: heading.x, y: number.y, w: m.calendarCellWidth, h: m.calendarCellHeight)
    }

    /// The hairline down the gutter, beside the day rows only.
    public static func calendarGutterLine(inRow row: Box, _ m: PanelMetrics) -> Box {
        let grid = calendarGrid(inRow: row, m)
        let top = grid.y + m.calendarHeadingHeight + m.calendarHeadingGap
        return Box(x: grid.x + m.calendarWeekColumn + m.calendarCellGap + (m.calendarGutter / 2).rounded(),
                   y: top, w: 1, h: grid.maxY - top)
    }

    /// What a press on the calendar row lands on: the week-start toggle, or nothing — the days
    /// are looked at, not pressed.
    public static func calendarHitsWeekStart(at point: Point, inRow row: Box, _ m: PanelMetrics) -> Bool {
        let cell = weekStartCell(inRow: row, m)
        return point.x >= cell.x && point.x < cell.maxX && point.y >= cell.y && point.y < cell.maxY
    }

    /// The month line: −1 in the left chevron's zone, +1 in the right's, 0 on the label —
    /// which is the way back to today, as the hero is.
    public static func monthNavStep(x: Double, inRow row: Box, _ m: PanelMetrics) -> Int {
        if x < row.x + m.monthChevronZone { return -1 }
        if x >= row.maxX - m.monthChevronZone { return 1 }
        return 0
    }

    // MARK: - Scrolling

    /// The content offset for a card shorter than its rows: clamped to the content, and moved
    /// by as little as will bring the cursor's row `margin` inside the viewport —
    /// `ensureCursorVisible`. Nothing to scroll answers 0.
    public static func scroll(offset: Double, cursor: Box?, viewport: Double, content: Double,
                              _ m: PanelMetrics) -> Double {
        guard content > viewport else { return 0 }
        var offset = max(0, min(offset, content - viewport))
        if let cursor {
            let margin = m.scrollMargin
            if cursor.y < offset + margin {
                offset = max(0, cursor.y - margin)
            } else if cursor.maxY > offset + viewport - margin {
                offset = cursor.maxY + margin - viewport
            }
        }
        return max(0, min(offset, content - viewport))
    }
}
