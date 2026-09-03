import AppKit
import ToeCore

/// Everything the view needs for one frame. A snapshot rather than the `MenuState` itself:
/// `MenuState` is a struct, and handing it over would hand over a copy that the view could
/// mutate into a second, silently divergent menu.
struct MenuSnapshot {
    var prompt: String
    var query: String
    /// Only the rows on screen. `MenuState` decided which those are.
    var rows: [MenuItem]
    /// Where the selection sits among them, if it is on screen at all.
    var selectedRow: Int?
    var metrics: MenuMetrics
    /// The second column's position: a fraction of the row on the keybindings page, where the
    /// arrows have to line up; nil elsewhere, which right-aligns it.
    var valueColumn: Double?
    var background: RGBA
    var foreground: RGBA
    var accent: RGBA
    var border: RGBA
    var opacity: Double
}

/// The quick menu, drawn.
///
/// One `draw(_:)` over the whole panel rather than a layer or a subview per row. `BorderOverlay`
/// is CALayer because its entire state is one rectangle and one radius, which the GPU can
/// re-render without the view ever redrawing; `StatusItem` draws into an `NSImage` because it
/// has no view at all, only a text attachment. A list of text rows rebuilt on every keystroke is
/// neither: per-row layers would mean allocating and tearing down a sublayer for every filtered
/// row to express in an object graph what twenty lines express directly, and `CATextLayer` sets
/// text less well than `NSAttributedString` does.
///
/// Flipped, because `Box` and `MenuLayout` are: origin top-left, y downward. That makes a frame
/// from `MenuLayout` into an `NSRect` by copying four numbers, and leaves `Coordinates.toCocoa`
/// to be called once, for the panel itself.
final class MenuView: NSView {

    var snapshot: MenuSnapshot? {
        didSet { needsDisplay = true }
    }

    var onKeyDown: ((NSEvent) -> Void)?
    var onSelectRow: ((Int) -> Void)?
    var onActivateRow: ((Int) -> Void)?

    private var mouseDownRow: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let s = snapshot else { return }
        let m = s.metrics
        let width = Double(bounds.width)

        // `.box-wrapper { background: alpha(@base, 0.95) }`. The alpha belongs to the fill, never
        // to `panel.alphaValue` — that would fade the text along with the ground behind it.
        NSColor(s.background.withAlpha(s.opacity)).setFill()
        bounds.fill()

        // `border: 2px solid @border`, square: a borderless panel has no corner radius to fight,
        // and walker's wrapper sets none. Inset by half the width so the stroke lands inside the
        // panel, and snapped to device pixels so it stays crisp on a 1× display.
        if m.borderWidth > 0 {
            let inset = CGFloat(m.borderWidth / 2)
            let rect = backingAlignedRect(bounds.insetBy(dx: inset, dy: inset),
                                          options: [.alignAllEdgesNearest])
            let path = NSBezierPath(rect: rect)
            path.lineWidth = CGFloat(m.borderWidth)
            NSColor(s.border).setStroke()
            path.stroke()
        }

        // `.search-container { background: @base }` — opaque, over the 95% wrapper.
        let strip = rect(MenuLayout.searchFrame(width: width, m))
        NSColor(s.background).setFill()
        strip.fill()

        let textFont = MenuFont.text(size: m.fontSize)
        let iconFont = MenuFont.icons(size: m.iconSide)
        let origin = MenuLayout.searchTextOrigin(width: width, m)
        if s.query.isEmpty {
            // `.input placeholder { opacity: 0.5 }`
            let strip = MenuLayout.searchFrame(width: width, m)
            draw(s.prompt,
                 in: NSRect(x: origin.x, y: origin.y,
                            width: strip.w - m.searchPadding * 2, height: m.lineHeight),
                 font: textFont, colour: s.foreground.withAlpha(0.5), alignment: .left)
        } else {
            let typed = draw(s.query, at: origin, font: textFont, colour: s.foreground)
            // A caret, not blinking: a timer redrawing a window that lives for a second earns
            // nothing, and walker's does not read as blinking at a glance either.
            NSColor(s.foreground).setFill()
            NSRect(x: origin.x + Double(typed), y: origin.y,
                   width: 2, height: m.lineHeight).fill()
        }

        for (index, item) in s.rows.enumerated() {
            let row = MenuLayout.rowFrame(index, width: width, m)
            let selected = index == s.selectedRow
            if let fraction = item.progress {
                // The accent, well down in alpha — the colour the selected row already draws its
                // text in, so a filling row belongs to the theme rather than being the one thing
                // in the menu that ignores it. Under the selection wash rather than over it, so
                // that the row you are standing on still reads as the row you are standing on
                // while it fills.
                NSColor(s.accent.withAlpha(0.3)).setFill()
                rect(MenuLayout.progressFrame(inRow: row, fraction: fraction)).fill()
            }
            if selected {
                // `child:selected { background: alpha(@text, 0.07) }`
                NSColor(s.foreground.withAlpha(0.07)).setFill()
                rect(row).fill()
            }
            // `child:selected .item-box * { color: @selected-text }` — the whole row, icon
            // included, takes the accent when it is the one under the cursor.
            //
            // A disabled row takes neither: Omarchy dims one to say "you already have this", and
            // half alpha is the same signal the subtitle already uses for a line that is context
            // rather than choice. It can never be the selected row — `MenuState` steps the cursor
            // over it — so the two cases do not have to compose.
            let colour = item.isDisabled ? s.foreground.withAlpha(0.4)
                                         : (selected ? s.accent : s.foreground)

            if let icon = item.icon {
                let box = MenuLayout.iconFrame(inRow: row, m)
                if let iconFont {
                    // Centred in the 16 pt box rather than sitting on the text baseline: the
                    // glyphs are square and the row is not.
                    let glyph = NSAttributedString(string: MenuFont.glyph(for: icon),
                                                   attributes: [.font: iconFont,
                                                                .foregroundColor: NSColor(colour)])
                    let size = glyph.size()
                    glyph.draw(at: NSPoint(x: box.x + (box.w - Double(size.width)) / 2,
                                           y: box.y + (box.h - Double(size.height)) / 2))
                } else if let image = NSImage(systemSymbolName: MenuFont.symbolName(for: icon),
                                              accessibilityDescription: nil) {
                    let configured = image.withSymbolConfiguration(
                        NSImage.SymbolConfiguration(pointSize: CGFloat(m.iconSide), weight: .regular))
                    configured?.isTemplate = true
                    NSColor(colour).set()
                    configured?.draw(in: rect(box))
                }
            }

            let title = MenuLayout.titleOrigin(inRow: row, hasIcon: item.icon != nil, m)
            let titleWidth = Double(measure(item.title, font: textFont))
            let rightEdge = row.x + row.w - m.itemPaddingLeft

            if let value = item.value {
                // The two columns are laid out together, because whatever one takes the other
                // cannot have. Before this they were placed independently, and a value longer
                // than the gap between them drew straight through the title.
                let valueBox: NSRect
                let titleLimit: Double
                if let column = s.valueColumn {
                    // The keybindings page: a fixed column, so every arrow lines up with the one
                    // above it. The title yields to it.
                    let x = row.x + row.w * column
                    valueBox = NSRect(x: x, y: title.y, width: rightEdge - x, height: m.lineHeight)
                    titleLimit = x - m.iconGap
                } else {
                    let space = MenuLayout.valueSpace(inRow: row, titleEnd: title.x + titleWidth, m)
                    let natural = Double(measure(value, font: textFont))
                    let fits = min(natural, space)
                    valueBox = NSRect(x: rightEdge - fits, y: title.y,
                                      width: fits, height: m.lineHeight)
                    titleLimit = rightEdge
                }
                draw(item.title,
                     in: NSRect(x: title.x, y: title.y,
                                width: max(0, titleLimit - title.x), height: m.lineHeight),
                     font: textFont, colour: colour, alignment: .left)
                // Below about a character there is nothing to say and room only to say it badly.
                if valueBox.width >= CGFloat(m.fontSize) / 2 {
                    draw(value, in: valueBox, font: textFont, colour: colour,
                         alignment: s.valueColumn == nil ? .right : .left)
                }
            } else {
                draw(item.title,
                     in: NSRect(x: title.x, y: title.y,
                                width: max(0, rightEdge - title.x), height: m.lineHeight),
                     font: textFont, colour: colour, alignment: .left)
            }

            if let subtitle = item.subtitle, m.showsSubtitles {
                // Always dimmed, selected row included: it is where the row lives, not what the
                // row is, and it should read as the smaller of the two lines at a glance.
                let at = MenuLayout.subtitleOrigin(inRow: row, hasIcon: item.icon != nil, m)
                draw(subtitle,
                     in: NSRect(x: at.x, y: at.y, width: max(0, rightEdge - at.x),
                                height: m.subtitleLineHeight),
                     font: MenuFont.text(size: m.fontSize * QuickMenu.subtitleScale),
                     colour: s.foreground.withAlpha(0.5), alignment: .left)
            }

            if item.value == nil, item.leadsOn {
                // walker marks a row that goes somewhere with a trailing `›`. Drawn in the text
                // font, not the icon one — it is punctuation, and it is what omarchy-menu emits.
                let text = NSAttributedString(string: "›",
                                              attributes: [.font: textFont,
                                                           .foregroundColor: NSColor(colour)])
                let at = MenuLayout.chevronOrigin(inRow: row, width: Double(text.size().width), m)
                text.draw(at: NSPoint(x: at.x, y: at.y))
            }
        }
    }

    @discardableResult
    private func draw(_ text: String, at point: Point, font: NSFont, colour: RGBA) -> CGFloat {
        let string = NSAttributedString(string: text,
                                        attributes: [.font: font,
                                                     .foregroundColor: NSColor(colour)])
        string.draw(at: NSPoint(x: point.x, y: point.y))
        return string.size().width
    }

    /// Drawn into a box rather than at a point, so anything too long for its share of the row is
    /// cut with an ellipsis instead of running into whatever is beside it.
    private func draw(_ text: String, in rect: NSRect, font: NSFont, colour: RGBA,
                      alignment: NSTextAlignment) {
        guard rect.width > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text,
                           attributes: [.font: font,
                                        .foregroundColor: NSColor(colour),
                                        .paragraphStyle: paragraph]).draw(in: rect)
    }

    private func measure(_ text: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private func rect(_ box: Box) -> NSRect {
        NSRect(x: box.x, y: box.y, width: box.w, height: box.h)
    }

    // MARK: - Events

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    /// Swallowed rather than passed on: with no key equivalents to service, the responder chain
    /// would otherwise beep at every keystroke the menu handles itself.
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownRow = row(for: event)
        if let row = mouseDownRow { onSelectRow?(row) }
    }

    override func mouseUp(with event: NSEvent) {
        // Only when it is let go over the row it went down on, the way every other menu behaves.
        if let row = row(for: event), row == mouseDownRow { onActivateRow?(row) }
        mouseDownRow = nil
    }

    private func row(for event: NSEvent) -> Int? {
        guard let s = snapshot else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return MenuLayout.row(at: Point(x: Double(point.x), y: Double(point.y)),
                              rows: s.rows.count, width: Double(bounds.width), s.metrics)
    }
}
