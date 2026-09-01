import AppKit
import ToeCore

/// The prompt line and the rows, drawn by hand.
///
/// Not an `NSTableView`, and not because a table would be hard: a table brings a scroll view, cell
/// reuse and a selection-highlight system that fights a custom accent — and decisively it wants the
/// arrow keys for itself, so its keys would have to be intercepted anyway. `MenuState` already owns
/// the scroll offset and the selection, so a table would only duplicate that state.
///
/// There is no `NSTextField` either. Characters go straight into `MenuState.query`, which keeps one
/// source of truth for what is on screen. The cost is no input method: CJK input will not work in
/// the query. For a fuzzy filter over a built-in Latin list that is the right trade, but it is a
/// real limitation and the README says so.
final class QuickMenuView: NSView {

    /// Set by the controller; the view never mutates the menu itself.
    var state: MenuState?
    var accent: NSColor = .controlAccentColor
    var onKey: ((NSEvent) -> Void)?

    private let promptFont = NSFont.systemFont(ofSize: 15, weight: .regular)
    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let matchFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let detailFont = NSFont.systemFont(ofSize: 12, weight: .regular)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }        // top-down, so row 0 is the first one drawn

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        // Deliberately no `super.keyDown` fallthrough: `NSResponder`'s default path ends in
        // `NSBeep`, and the menu owns the keyboard outright for as long as it is open. Every
        // keystroke is either handled or swallowed, never bounced.
        onKey?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // CTRL+N and friends arrive here rather than in keyDown.
        guard event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.command) else { return false }
        onKey?(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) { /* nothing to do; do not beep */ }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let state else { return }
        let pad = QuickMenuGeometry.padding

        drawPrompt(state, in: NSRect(x: pad, y: 0,
                                     width: bounds.width - 2 * pad,
                                     height: QuickMenuGeometry.promptHeight))

        // The hairline between the prompt and the list.
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        NSRect(x: 0, y: QuickMenuGeometry.promptHeight,
               width: bounds.width, height: QuickMenuGeometry.separatorHeight).fill()

        let rows = state.rows
        var y = QuickMenuGeometry.promptHeight + QuickMenuGeometry.separatorHeight + pad
        if rows.isEmpty {
            drawNoMatches(at: y)
            return
        }

        let first = state.scrollOffset
        let last = min(rows.count, first + state.visibleRows)
        for index in first..<last {
            let rect = NSRect(x: pad, y: y, width: bounds.width - 2 * pad,
                              height: QuickMenuGeometry.rowHeight)
            draw(rows[index], in: rect, selected: index == state.selection)
            y += QuickMenuGeometry.rowHeight
        }
        drawScrollHint(rows: rows.count, first: first, last: last)
    }

    private func drawPrompt(_ state: MenuState, in rect: NSRect) {
        // Where you are, as a trail — "Go › Style › Theme" — because a filtered list gives no other
        // clue how deep you have gone.
        let trail = state.breadcrumb.dropFirst().joined(separator: " › ")
        let placeholder = trail.isEmpty ? state.prompt : "\(state.breadcrumb[0]) › \(trail)…"

        let text: NSAttributedString
        if state.query.isEmpty {
            text = NSAttributedString(string: placeholder, attributes: [
                .font: promptFont, .foregroundColor: NSColor.placeholderTextColor,
            ])
        } else {
            text = NSAttributedString(string: state.query, attributes: [
                .font: promptFont, .foregroundColor: NSColor.labelColor,
            ])
        }
        let size = text.size()
        let y = rect.midY - size.height / 2
        text.draw(at: NSPoint(x: rect.minX, y: y))

        // A solid caret rather than a blinking one: nothing here is a text field, and a cursor that
        // blinks on a surface open for a second and a half is just flicker.
        accent.withAlphaComponent(0.9).setFill()
        let caretX = rect.minX + (state.query.isEmpty ? 0 : size.width + 2)
        NSRect(x: caretX, y: y + 2, width: 2, height: size.height - 4).fill()
    }

    private func drawNoMatches(at y: CGFloat) {
        let text = NSAttributedString(string: "No matches", attributes: [
            .font: titleFont, .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        text.draw(at: NSPoint(x: QuickMenuGeometry.padding + 4,
                              y: y + (QuickMenuGeometry.rowHeight - text.size().height) / 2))
    }

    private func draw(_ row: MenuRow, in rect: NSRect, selected: Bool) {
        let entry = row.entry

        if selected {
            accent.withAlphaComponent(0.20).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.fill()
        }

        var x = rect.minX + 6

        // The checkmark occupies the same slot whether or not it is there, so rows do not shift
        // as the ticked one moves.
        let tickWidth: CGFloat = 14
        if entry.isOn, let tick = NSImage(systemSymbolName: "checkmark",
                                          accessibilityDescription: nil) {
            tick.isTemplate = true
            let side: CGFloat = 10
            drawTemplate(tick, in: NSRect(x: x, y: rect.midY - side / 2, width: side, height: side),
                         tint: accent)
        }
        x += tickWidth

        if let image = MenuIconRenderer.image(for: entry.icon) {
            let side = MenuIconRenderer.side
            let box = NSRect(x: x, y: rect.midY - side / 2, width: side, height: side)
            if image.isTemplate {
                drawTemplate(image, in: box, tint: colour(for: entry, selected: selected))
            } else {
                image.draw(in: box)
            }
        }
        x += MenuIconRenderer.side + 8

        // A submenu marker on the right, so a row that drills down looks like one before you
        // press anything.
        var rightEdge = rect.maxX - 6
        if entry.isSubmenu, let chevron = NSImage(systemSymbolName: "chevron.right",
                                                  accessibilityDescription: nil) {
            chevron.isTemplate = true
            let side: CGFloat = 9
            rightEdge -= side
            drawTemplate(chevron,
                         in: NSRect(x: rightEdge, y: rect.midY - side / 2, width: side, height: side),
                         tint: NSColor.tertiaryLabelColor)
            rightEdge -= 6
        }

        // The title gets what it needs and the detail gets what is left. walker is 295pt wide, and
        // keeping that fidelity means something has to give: a truncated hint beats a truncated name,
        // so the title is served first and the detail takes the remainder or is dropped.
        let title = attributedTitle(entry, offsets: row.offsets, selected: selected)
        let titleSize = title.size()
        let detail = entry.detail.map { detailText($0) }
        let detailSize = detail?.size() ?? .zero

        let available = max(0, rightEdge - x)
        let titleWidth = min(titleSize.width, max(0, available - detailSize.width - 10))
        title.draw(with: NSRect(x: x, y: rect.midY - titleSize.height / 2,
                                width: titleWidth, height: titleSize.height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // A hint narrower than this is unreadable anyway, so it is left off rather than shown as
        // an ellipsis.
        if let detail {
            let width = min(detailSize.width, max(0, available - titleWidth - 10))
            if width >= 16 {
                detail.draw(with: NSRect(x: rightEdge - width,
                                         y: rect.midY - detailSize.height / 2,
                                         width: width, height: detailSize.height),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
        }
    }

    /// Bold on the characters the query matched, so you can see *why* a row is in the list.
    private func attributedTitle(_ entry: MenuEntry, offsets: [Int], selected: Bool)
        -> NSAttributedString {
        let colour = self.colour(for: entry, selected: selected)
        // Without an explicit truncating line-break mode, `truncatesLastVisibleLine` has nothing to
        // act on and a long title is clipped mid-glyph instead of ellipsised.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: entry.title, attributes: [
            .font: titleFont, .foregroundColor: colour, .paragraphStyle: paragraph,
        ])
        guard entry.isEnabled else { return text }
        for offset in offsets where offset < entry.title.count {
            text.addAttributes([.font: matchFont, .foregroundColor: colour],
                               range: NSRange(location: offset, length: 1))
        }
        return text
    }

    private func detailText(_ detail: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .right
        return NSAttributedString(string: detail, attributes: [
            .font: detailFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
    }

    /// `selected` is not consulted: the highlight is a tinted fill behind unchanged text rather
    /// than an inverted row, which is what keeps a themed accent legible in both appearances.
    private func colour(for entry: MenuEntry, selected: Bool) -> NSColor {
        entry.isSelectable ? .labelColor : .tertiaryLabelColor
    }

    /// A template image drawn in a colour, which `NSImage` will not do on its own.
    private func drawTemplate(_ image: NSImage, in rect: NSRect, tint: NSColor) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        image.draw(in: rect)
        tint.set()
        rect.fill(using: .sourceAtop)
        context.restoreGraphicsState()
    }

    /// Faint arrows when the list runs past the window, since there is no scroll bar to say so.
    private func drawScrollHint(rows: Int, first: Int, last: Int) {
        NSColor.tertiaryLabelColor.setFill()
        let x = bounds.width - QuickMenuGeometry.padding - 3
        if first > 0 {
            NSRect(x: x, y: QuickMenuGeometry.promptHeight + 6, width: 3, height: 3).fill()
        }
        if last < rows {
            NSRect(x: x, y: bounds.height - 9, width: 3, height: 3).fill()
        }
    }

    // MARK: - Accessibility

    // A hand-drawn list is invisible to VoiceOver without help. This is the minimum: the panel
    // says what it is and announces the row the selection lands on. Exposing each row as an
    // `NSAccessibilityElement` would be better and is not done yet.
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { state?.prompt }
    override func accessibilityValue() -> Any? { state?.selectedRow?.entry.title }

    func announceSelection() {
        guard let title = state?.selectedRow?.entry.title else { return }
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
