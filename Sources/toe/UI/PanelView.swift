import AppKit
import ToeCore

/// A panel, drawn — `MenuView`'s way, one `draw(_:)` over the card, with Omarchy's panel
/// pieces (`PanelHero`, `PanelSlider`, `ToggleSwitch`, `CursorSurface`) as the things it
/// draws into the frames `PanelLayout` handed it.
///
/// The chrome is the quick menu's: the same 95% ground, the same 2pt border, the same wash
/// under the cursor and the accent for the row it is on. What is Omarchy's panel styling and
/// not walker's — the small-caps status lines, the dim labels, the fills of a switch and a
/// slider — is `Style.qml`'s state tokens read as alphas on the foreground, cited where used.
///
/// Flipped, like `MenuView` and `BarView`, so a `Box` is an `NSRect` by copying four numbers.
final class PanelView: NSView {

    enum Button { case left, right }

    var snapshot: PanelSnapshot? {
        didSet { needsDisplay = true }
    }

    var onKeyDown: ((NSEvent) -> Void)?
    /// The pointer resting on a row — moves the cursor, upstream's `onContainsMouseChanged`.
    var onHover: ((Int?) -> Void)?
    var onPress: ((Int?, Button, Point) -> Void)?
    var onDrag: ((Int?, Point) -> Void)?
    var onRelease: ((Int?) -> Void)?
    /// The wheel: whole notches for a slider, and the raw points for scrolling the card.
    var onScroll: ((Int?, Int, Double) -> Void)?

    private var scrollAccumulator: Double = 0
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let s = snapshot else { return }
        let st = s.style
        let m = st.metrics
        let fg = st.foreground

        // `.box-wrapper { background: alpha(@base, 0.95) }`, and the 2pt border inside it —
        // exactly `MenuView`'s ground, so the two surfaces read as one family.
        NSColor(st.background.withAlpha(st.opacity)).setFill()
        bounds.fill()
        if m.borderWidth > 0 {
            let inset = CGFloat(m.borderWidth / 2)
            let rect = backingAlignedRect(bounds.insetBy(dx: inset, dy: inset), options: [.alignAllEdgesNearest])
            let path = NSBezierPath(rect: rect)
            path.lineWidth = CGFloat(m.borderWidth)
            NSColor(st.border).setStroke()
            path.stroke()
        }

        // The content, clipped to the inside of the border and scrolled by `offset`.
        NSGraphicsContext.saveGraphicsState()
        let clip = bounds.insetBy(dx: CGFloat(m.borderWidth), dy: CGFloat(m.borderWidth))
        NSBezierPath(rect: clip).addClip()
        let shift = NSAffineTransform()
        shift.translateX(by: 0, yBy: CGFloat(-s.offset))
        shift.concat()

        for (index, row) in s.rows.enumerated() where index < s.frames.count {
            let frame = rect(s.frames[index])
            // Off the card entirely: nothing to draw, and the strings are not free.
            guard frame.maxY - CGFloat(s.offset) >= 0, frame.minY - CGFloat(s.offset) <= bounds.height else { continue }
            let selected = index == s.selection
            let alpha = row.dimmed ? 0.45 : 1
            let colour = (selected ? st.accent : fg).withAlpha(alpha)

            switch row.kind {
            case .hero(let glyph, let title, let status, let trailing):
                drawHero(glyph: glyph, title: title, status: status, trailing: trailing,
                         in: frame, selected: selected, s)

            case .header(let text, let trailing):
                // `PanelSectionHeader`: caption, bold, dim — `Qt.darker(fg, 1.4)` — with the
                // overshoot reserved at the top.
                let top = frame.minY + CGFloat((m.pointSize(.caption) * 0.15).rounded(.up))
                let box = NSRect(x: frame.minX, y: top, width: frame.width, height: CGFloat(m.lineHeight(.caption)))
                draw(text.uppercased(), in: box, font: .caption, colour: fg.withAlpha(0.7), bold: true, kern: 1.2, s)
                if let trailing {
                    draw(trailing, in: box.insetBy(dx: CGFloat(m.sliderInset), dy: 0), font: .caption,
                         colour: fg.withAlpha(0.7), bold: true, alignment: .right, s)
                }

            case .slider(_, let value, let dimmed):
                if selected { wash(frame, s) }
                drawSlider(value: value, dimmed: dimmed, in: s.frames[index], s)

            case .progress(let fraction):
                // The power panel's bar: a track at 0.12, filled in the foreground, never
                // thinner than it is tall.
                let radius = frame.height / 2
                NSColor(fg.withAlpha(0.12)).setFill()
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
                let fill = NSRect(x: frame.minX, y: frame.minY,
                                  width: max(frame.height, frame.width * CGFloat(fraction)), height: frame.height)
                NSColor(fg).setFill()
                NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()

            case .info(let cells):
                // `InfoPair`s in equal columns `space(20)` apart: the label dim at the left of
                // its cell, the value at the right.
                guard !cells.isEmpty else { break }
                let spacing = CGFloat(m.space(20))
                let cellWidth = (frame.width - spacing * CGFloat(cells.count - 1)) / CGFloat(cells.count)
                for (i, cell) in cells.enumerated() {
                    let box = NSRect(x: frame.minX + (cellWidth + spacing) * CGFloat(i), y: frame.minY,
                                     width: cellWidth, height: frame.height)
                    draw(cell.label, in: box, font: .bodySmall, colour: fg.withAlpha(0.6), s)
                    draw(cell.value, in: box, font: .bodySmall, colour: fg, alignment: .right, s)
                }

            case .pick(let glyph, let label, let detail, let current):
                // `CursorSurface`: the hover fill under the cursor, the selected fill under
                // the one in effect, and the label bold when it is.
                if selected {
                    wash(frame, s)
                } else if current {
                    NSColor(fg.withAlpha(0.18)).setFill()
                    frame.fill()
                }
                let glyphBox = NSRect(x: frame.minX + CGFloat(m.sliderInset), y: frame.minY,
                                      width: CGFloat(m.glyphSlot), height: frame.height)
                draw(glyph, in: glyphBox, font: .title, colour: colour, alignment: .center, s)
                let textX = glyphBox.maxX + CGFloat(m.glyphGap)
                let textWidth = frame.maxX - CGFloat(m.sliderInset) - textX
                if let detail {
                    let name = NSRect(x: textX, y: frame.minY + CGFloat(m.tallRowPadding / 2), width: textWidth,
                                      height: CGFloat(m.lineHeight(.body)))
                    draw(label, in: name, font: .body, colour: colour, s)
                    let line = NSRect(x: textX, y: name.maxY + CGFloat(m.space(1)), width: textWidth,
                                      height: CGFloat(m.lineHeight(.caption)))
                    draw(detail, in: line, font: .caption,
                         colour: current || selected ? colour : fg.withAlpha(0.66 * alpha), s)
                } else {
                    let name = NSRect(x: textX, y: frame.minY, width: textWidth, height: frame.height)
                    draw(label, in: name, font: .body, colour: colour, bold: current, s)
                }

            case .separator:
                // `PanelSeparator`: the foreground at 0.12, one point.
                NSColor(fg.withAlpha(0.12)).setFill()
                frame.fill()

            case .action(let label):
                if selected { wash(frame, s) }
                let box = frame.insetBy(dx: CGFloat(m.sliderInset), dy: 0)
                draw(label, in: box, font: .body, colour: colour, s)
                // walker's `›` for a row that goes somewhere, in the text font as `MenuView`
                // draws it.
                draw("›", in: box, font: .body, colour: colour, alignment: .right, s)

            case .note(let text):
                draw(text, in: frame.insetBy(dx: CGFloat(m.sliderInset), dy: 0), font: .body,
                     colour: fg.withAlpha(0.6), s)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// `child:selected { background: alpha(@text, 0.07) }` — the menu's wash, under the cursor.
    private func wash(_ frame: NSRect, _ s: PanelSnapshot) {
        NSColor(s.style.foreground.withAlpha(0.07)).setFill()
        frame.fill()
    }

    /// `PanelHero`: the glyph at display size on the left, the title bold with the status in
    /// small caps under it, and on the right either the big number or the switch.
    private func drawHero(glyph: String, title: String, status: String, trailing: PanelRow.HeroTrailing?,
                          in frame: NSRect, selected: Bool, _ s: PanelSnapshot) {
        let st = s.style, m = st.metrics, fg = st.foreground
        if selected { wash(frame, s) }
        let glyphString = attributed(glyph, font: .display, colour: fg, s)
        let glyphSize = glyphString.size()
        glyphString.draw(at: NSPoint(x: frame.minX, y: frame.midY - glyphSize.height / 2))

        var trailingWidth: CGFloat = 0
        switch trailing {
        case .text(let text):
            let number = attributed(text, font: .displayLarge, colour: fg, bold: true, s)
            let size = number.size()
            number.draw(at: NSPoint(x: frame.maxX - size.width, y: frame.midY - size.height / 2))
            trailingWidth = size.width + CGFloat(m.space(10))
        case .toggle(let on):
            let width = CGFloat(m.toggleWidth + m.togglePad * 2)
            let height = CGFloat(m.toggleHeight + m.togglePad * 2)
            drawToggle(on: on, hot: selected,
                       in: NSRect(x: frame.maxX - width, y: frame.midY - height / 2, width: width, height: height), s)
            trailingWidth = width + CGFloat(m.space(12))
        case nil:
            break
        }

        let textX = frame.minX + glyphSize.width + CGFloat(m.heroGap)
        let textWidth = max(0, frame.maxX - trailingWidth - textX)
        let titleHeight = CGFloat(m.lineHeight(.title))
        let statusHeight = CGFloat(m.lineHeight(.caption))
        let stack = titleHeight + CGFloat(m.space(2)) + statusHeight
        let top = frame.midY - stack / 2
        draw(title, in: NSRect(x: textX, y: top, width: textWidth, height: titleHeight),
             font: .title, colour: selected ? st.accent : fg, bold: true, s)
        draw(status.uppercased(), in: NSRect(x: textX, y: top + titleHeight + CGFloat(m.space(2)),
                                             width: textWidth, height: statusHeight),
             font: .caption, colour: fg.withAlpha(0.7), bold: true, kern: 1.2, s)
    }

    /// `ToggleSwitch`, square because the menu's corners are: the track at the normal fill
    /// with its hairline border when off, the selected fill and no border when on; the knob
    /// in the foreground, a shade darker when off; a ring outside the track when the cursor
    /// is on it, `Border.controlSpec("hover-cursor")`.
    private func drawToggle(on: Bool, hot: Bool, in box: NSRect, _ s: PanelSnapshot) {
        let st = s.style, m = st.metrics, fg = st.foreground
        if hot {
            let ring = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            NSColor(fg.withAlpha(0.25)).setStroke()
            ring.stroke()
        }
        let track = NSRect(x: box.midX - CGFloat(m.toggleWidth) / 2, y: box.midY - CGFloat(m.toggleHeight) / 2,
                           width: CGFloat(m.toggleWidth), height: CGFloat(m.toggleHeight))
        NSColor(fg.withAlpha(on ? 0.18 : 0.04)).setFill()
        track.fill()
        if !on {
            let edge = NSBezierPath(rect: track.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            NSColor(fg.withAlpha(0.4)).setStroke()
            edge.stroke()
        }
        let knob = CGFloat(max(6, (m.toggleHeight * 0.72).rounded()))
        let inset = CGFloat(max(1, ((m.toggleHeight - Double(knob)) / 2).rounded()))
        let x = on ? track.maxX - inset - knob : track.minX + inset
        NSColor(on ? fg : fg.withAlpha(0.8)).setFill()
        NSRect(x: x, y: track.midY - knob / 2, width: knob, height: knob).fill()
    }

    /// `PanelSlider`: the track at the selected fill, the fill in the foreground, the knob in
    /// the foreground with a 2pt edge in the background so it stands off the fill. Muted
    /// draws the lot at half.
    private func drawSlider(value: Double, dimmed: Bool, in row: Box, _ s: PanelSnapshot) {
        let st = s.style, m = st.metrics
        let alpha = dimmed ? 0.5 : 1
        let fg = st.foreground.withAlpha(alpha)
        let track = rect(PanelLayout.sliderTrack(inRow: row, m))
        let radius = track.height / 2
        NSColor(st.foreground.withAlpha(0.18 * alpha)).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(value), height: track.height)
        NSColor(fg).setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        let knob = rect(PanelLayout.knobFrame(value: value, inRow: row, m))
        let path = NSBezierPath(ovalIn: knob.insetBy(dx: 1, dy: 1))
        NSColor(fg).setFill()
        path.fill()
        path.lineWidth = 2
        NSColor(st.background).setStroke()
        path.stroke()
    }

    // MARK: - Text

    private func attributed(_ text: String, font: PanelFont, colour: RGBA, bold: Bool = false,
                            kern: Double = 0, alignment: NSTextAlignment = .left,
                            _ s: PanelSnapshot) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: MenuFont.text(size: s.style.metrics.pointSize(font)),
            .foregroundColor: NSColor(colour),
            .paragraphStyle: paragraph,
        ]
        // The bundled face is Regular only, so bold is a stroke around the fill — the same
        // trick every browser plays on a family with no bold — rather than 2.6 MB of Bold
        // in the bundle for a few headers.
        if bold { attributes[.strokeWidth] = -2.5 }
        if kern != 0 { attributes[.kern] = kern }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Text centred vertically in a box, cut with an ellipsis rather than run out of it.
    private func draw(_ text: String, in box: NSRect, font: PanelFont, colour: RGBA, bold: Bool = false,
                      kern: Double = 0, alignment: NSTextAlignment = .left, _ s: PanelSnapshot) {
        guard box.width > 0, !text.isEmpty else { return }
        let string = attributed(text, font: font, colour: colour, bold: bold, kern: kern, alignment: alignment, s)
        let height = string.size().height
        string.draw(in: NSRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height))
    }

    private func rect(_ box: Box) -> NSRect {
        NSRect(x: box.x, y: box.y, width: box.w, height: box.h)
    }

    // MARK: - Events

    override func keyDown(with event: NSEvent) { onKeyDown?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }

    override func mouseMoved(with event: NSEvent) { onHover?(row(for: event)) }
    override func mouseDown(with event: NSEvent) { onPress?(row(for: event), .left, point(for: event)) }
    override func rightMouseDown(with event: NSEvent) { onPress?(row(for: event), .right, point(for: event)) }
    override func mouseDragged(with event: NSEvent) { onDrag?(row(for: event), point(for: event)) }
    override func mouseUp(with event: NSEvent) { onRelease?(row(for: event)) }

    override func scrollWheel(with event: NSEvent) {
        // `BarView.scrollWheel`'s accumulator, so a trackpad's stream of small deltas is one
        // notch per notch's worth over a slider; the raw delta goes with it for scrolling.
        let delta = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY) / 10
                                                    : Double(event.scrollingDeltaY)
        if scrollAccumulator * delta < 0 { scrollAccumulator = 0 }
        scrollAccumulator += delta
        let steps = scrollAccumulator < 0 ? Int(scrollAccumulator.rounded(.up))
                                          : Int(scrollAccumulator.rounded(.down))
        scrollAccumulator -= Double(steps)
        let points = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY)
                                                     : Double(event.scrollingDeltaY) * 10
        onScroll?(row(for: event), steps, points)
    }

    /// The pointer in content coordinates — scrolled, so a row's frame is what it is hit by.
    private func point(for event: NSEvent) -> Point {
        let p = convert(event.locationInWindow, from: nil)
        return Point(x: Double(p.x), y: Double(p.y) + (snapshot?.offset ?? 0))
    }

    private func row(for event: NSEvent) -> Int? {
        guard let s = snapshot else { return nil }
        return PanelLayout.row(at: point(for: event), frames: s.frames)
    }
}
