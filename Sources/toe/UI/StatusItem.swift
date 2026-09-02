import AppKit
import ToeCore

/// The menu bar item. toe is an `LSUIElement`, so this is its only visible surface.
///
/// The title is the workspace strip in Omarchy's waybar styling — the focused workspace is
/// a filled rounded square, every other one its own digit. Clicking a workspace switches to
/// it, as Omarchy's `on-click: activate` does, and that is the whole of it: waybar's strip
/// has no menu behind it, so neither has this one. Everything the menu used to offer lives
/// on a key binding instead — `editconfig`, `reload`, `quit`.
final class StatusItem: NSObject {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var onSelectWorkspace: ((Int) -> Void)?
    /// The one thing a click still has to be able to do while toe is not yet running: without
    /// the permission there is no strip to click, and no menu to offer it from either.
    var onOpenAccessibility: (() -> Void)?
    /// Clicking toe's own mark, at the head of the strip.
    var onOpenMenu: (() -> Void)?

    private var accessibilityGranted = false

    /// waybar's `persistent-workspaces` — how many workspaces keep a slot when empty.
    var persistentWorkspaces = WorkspaceStrip.defaultPersistent

    /// What the strip currently draws, and how wide each item came out — together they turn
    /// a click position back into a workspace.
    private var stripItems: [WorkspaceStrip.Item] = []
    private var stripWidths: [Double] = []

    // Omarchy's bar is JetBrainsMono Nerd Font at 12px with `padding: 0 6px; margin: 0 1.5px`,
    // i.e. a ~15px slot per workspace. These are its equivalents at menu bar size.
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let gap: CGFloat = 7
    private let markerSide: CGFloat = 8
    private let markerRadius: CGFloat = 2.5
    /// toe's mark, a little taller than the digits' cap height so it reads as a logo rather
    /// than a letter that has wandered in from the strip.
    private let markHeight: CGFloat = 11
    /// The T's bounding box in `scripts/make-icon.swift` is `tWidth` by `tHeight` of the icon's
    /// shape, so the mark keeps that proportion here rather than being squared off.
    private var markWidth: CGFloat { (markHeight * 0.52 / 0.60).rounded() }

    /// Omarchy dims empty workspaces with `opacity: 0.5`, and so does toe: the ones you are
    /// using should be the ones your eye lands on, and the rest are there to be counted past
    /// rather than read.
    ///
    /// Built from a dynamic provider rather than `secondaryLabelColor` so it resolves when it
    /// is drawn, against the menu bar's own appearance — which is not always the app's, since
    /// macOS darkens the menu bar to suit the desktop picture.
    private static let dimLabelColor = NSColor(name: "toeDimLabel") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.5)
    }

    override init() {
        super.init()
        item.button?.title = "toe"
        item.button?.target = self
        item.button?.action = #selector(buttonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp])
    }

    /// Cheap: only the title strip is recomputed, from the little the strip reads.
    func update(workspaces: [WorkspaceStrip.State], warnings: [String],
                accessibilityGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        item.button?.attributedTitle = title(for: workspaces)

        // The focused workspace is drawn as a square rather than a digit, so the title on
        // its own no longer reads as anything — spell it out for VoiceOver. With no menu to
        // list them in, config problems are named here too.
        var described = accessibilityGranted
            ? "toe — workspace \(workspaces.first { $0.isFocused }?.index ?? 1)"
            : "toe needs Accessibility permission — click to grant it"
        if !warnings.isEmpty {
            described += "\n" + warnings.joined(separator: "\n")
        }
        item.button?.toolTip = described
        item.button?.setAccessibilityLabel(described)
    }

    // MARK: - The workspace strip

    private func title(for workspaces: [WorkspaceStrip.State]) -> NSAttributedString {
        stripItems = []
        stripWidths = []

        guard accessibilityGranted else {
            return NSAttributedString(string: "toe !", attributes: [
                .font: font, .foregroundColor: NSColor.systemOrange,
            ])
        }

        // With `persistent_workspaces = 0` and nothing open there is no strip at all, and the
        // mark is the whole item — still clickable, which is the point of it being there.
        let items = WorkspaceStrip.items(for: workspaces, persistent: persistentWorkspaces)
        guard !items.isEmpty else {
            return NSAttributedString(attributedString: markPiece)
        }

        let strip = NSMutableAttributedString()
        strip.append(markPiece)
        for item in items {
            if strip.length > 0 { strip.append(spacer) }
            strip.append(piece(for: item))
            stripItems.append(item)
            stripWidths.append(Double(width(of: item)))
        }
        return strip
    }

    /// A fixed `gap` of empty space, kerned rather than padded so its width is exactly known.
    private var spacer: NSAttributedString {
        let space = NSAttributedString(string: " ", attributes: [.font: font]).size().width
        return NSAttributedString(string: " ", attributes: [.font: font, .kern: gap - space])
    }

    /// The mark, plus the gap that separates it from the first workspace.
    private var markPiece: NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = mark()
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - markHeight) / 2,
                                   width: markWidth, height: markHeight)
        let piece = NSMutableAttributedString(attachment: attachment)
        piece.append(spacer)
        return piece
    }

    private func piece(for item: WorkspaceStrip.Item) -> NSAttributedString {
        switch item.marker {
        case .digit:
            return NSAttributedString(string: item.label, attributes: [
                .font: font,
                .foregroundColor: item.dim ? Self.dimLabelColor : NSColor.labelColor,
            ])
        case .focused, .visible:
            let attachment = NSTextAttachment()
            attachment.image = marker(filled: item.marker == .focused, dim: item.dim)
            // Centre the square on the digits' cap height rather than the baseline.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - markerSide) / 2,
                                       width: markerSide, height: markerSide)
            return NSAttributedString(attachment: attachment)
        }
    }

    private func width(of item: WorkspaceStrip.Item) -> CGFloat {
        item.marker == .digit
            ? NSAttributedString(string: item.label, attributes: [.font: font]).size().width
            : markerSide
    }

    /// toe's own mark: the crossbar and stem of the app icon's T, without the tile under it.
    ///
    /// Drawn rather than scaled down from `Toe.icns`, for two reasons. A template image is made
    /// from its alpha, and the icon's alpha is the whole rounded square — as a menu bar template
    /// it would be a solid blob. And the proportions here are the icon's own, read off
    /// `scripts/make-icon.swift`, so the two stay one design rather than two drawings of it.
    ///
    /// This is the icon's small-size representation, which that script already defines: under
    /// 128px it drops the gutter and thickens the stem by 1.22, because a gutter a quarter of a
    /// pixel wide is grey mud and a stem scaled straight down vanishes beside the crossbar.
    ///
    /// `labelColor` rather than white, resolved at draw time like the workspace markers: macOS
    /// darkens the menu bar to suit the desktop picture, and a hardcoded white goes invisible
    /// the moment it does not.
    private func mark() -> NSImage {
        let image = NSImage(size: NSSize(width: markWidth, height: markHeight),
                            flipped: false) { rect in
            NSColor.labelColor.setFill()
            let crossbarHeight = (rect.height * 0.24).rounded()
            let stemWidth = (rect.width * 0.28 * 1.22).rounded()
            let radius: CGFloat = 0.5
            let crossbar = NSRect(x: rect.minX, y: rect.maxY - crossbarHeight,
                                  width: rect.width, height: crossbarHeight)
            let stem = NSRect(x: (rect.midX - stemWidth / 2).rounded(), y: rect.minY,
                              width: stemWidth, height: rect.height - crossbarHeight)
            NSBezierPath(roundedRect: crossbar, xRadius: radius, yRadius: radius).fill()
            NSBezierPath(roundedRect: stem, xRadius: radius, yRadius: radius).fill()
            return true
        }
        // Redrawn on every use, so a light/dark switch cannot leave a stale mark behind.
        image.cacheMode = .never
        return image
    }

    /// `nf-md-square_rounded`, which is what Omarchy marks the active workspace with — drawn
    /// rather than set, so it needs no Nerd Font installed. The drawing handler runs at draw
    /// time, so the colour resolves against whichever appearance the menu bar is in.
    private func marker(filled: Bool, dim: Bool) -> NSImage {
        let side = markerSide, radius = markerRadius
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { square in
            let colour = dim ? Self.dimLabelColor : NSColor.labelColor
            if filled {
                colour.setFill()
                NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius).fill()
            } else {
                colour.setStroke()
                let path = NSBezierPath(roundedRect: square.insetBy(dx: 0.75, dy: 0.75),
                                        xRadius: radius - 0.75, yRadius: radius - 0.75)
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        // Redraw on every use, so a light/dark switch cannot leave a stale square behind.
        image.cacheMode = .never
        return image
    }

    // MARK: - Clicks

    /// A click on a workspace switches to it. A click anywhere else — the padding at either
    /// end, or a strip that has nothing in it — does nothing, exactly as waybar's does.
    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        guard accessibilityGranted else {
            onOpenAccessibility?()
            return
        }

        guard let event = NSApp.currentEvent else { return }
        let x = sender.convert(event.locationInWindow, from: nil).x
        switch WorkspaceStrip.hit(x: Double(x), widths: stripWidths, gap: Double(gap),
                                  buttonWidth: Double(sender.bounds.width),
                                  leading: Double(markWidth + gap)) {
        case .mark:
            onOpenMenu?()
        case .workspace(let index):
            onSelectWorkspace?(stripItems[index].index)
        case nil:
            break
        }
    }
}
