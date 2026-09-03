import AppKit
import ToeCore

/// The menu bar item. toe is an `LSUIElement`, so this is its only visible surface.
///
/// The title is the workspace strip in Omarchy's waybar styling — the focused workspace is
/// a filled rounded square, every other one its own digit. Clicking a workspace switches to
/// it, as Omarchy's `on-click: activate` does, and that is the whole of it: waybar's strip
/// has no menu behind it, so neither has this one. Everything the menu used to offer lives
/// on a key binding instead — `reload`, `quit`, and the `exec` that opens the config.
final class StatusItem: NSObject {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var onSelectWorkspace: ((Int) -> Void)?
    /// The one thing a click still has to be able to do while toe is not yet running: without
    /// the permission there is no strip to click, and no menu to offer it from either.
    var onOpenAccessibility: (() -> Void)?
    /// Clicking toe's own mark, at the head of the strip.
    var onOpenMenu: (() -> Void)?

    private var accessibilityGranted = false
    /// What is being fetched, if anything — see `update(workspaces:warnings:…)`.
    private var progress: String?

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
    /// Everything on the strip is set to the digits' cap height and stands on the baseline —
    /// the mark, the markers, and the digits themselves — so the row has one top edge and one
    /// bottom edge rather than three of each.
    ///
    /// Rounded **up** to the half point, never down. Cap height is 9.16pt, which is 18.32 device
    /// pixels: snapping that down to 9pt throws away the top third of a pixel, and the digits
    /// keep it — SF's `1` covers that row 62% and its round digits overshoot to 99%, against 50%
    /// for a shape that stopped at 18. The difference is exactly the one pixel that makes a
    /// drawn glyph sit visibly lower than the type beside it.
    private var capBox: CGFloat { (font.capHeight * 2).rounded(.up) / 2 }
    /// Omarchy's `nf-md-square_rounded`, at that height. It used to be 8pt centred on the cap
    /// height, which left it floating a pixel clear of the baseline and a pixel short of the
    /// digits' tops — and made the mark beside it read as sitting low when it was not.
    private var markerSide: CGFloat { capBox }
    /// The 2.5-on-8 rounding of the original square, kept in proportion.
    private var markerRadius: CGFloat { markerSide * 2.5 / 8 }
    /// The mark is a capital T, so it is set like one: cap height exactly, sitting on the
    /// baseline. Anything taller has to be centred on something, and centring a letter on the
    /// cap height of its neighbours puts it above their tops and below their baseline at once —
    /// which reads as a misalignment however carefully the centring is done.
    private var markHeight: CGFloat { capBox }
    /// The T's bounding box in `scripts/make-icon.swift` is `tWidth` by `tHeight` of the icon's
    /// shape, so the mark keeps that proportion here rather than being squared off.
    private var markWidth: CGFloat { snap(markHeight * 0.52 / 0.60) }
    /// Half a point, which is a whole pixel on every display toe supports. Strokes two points
    /// wide have to land on the grid or they render as three grey ones.
    private func snap(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }

    /// AppKit lands a text attachment's image half a device pixel above the baseline. Measured,
    /// not assumed: without this the mark and the markers rendered with their top and bottom
    /// rows at half coverage while the digits beside them were solid, which is exactly what
    /// reads as a drawn glyph sitting a pixel low next to type.
    private let attachmentNudge: CGFloat = -0.25

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
    ///
    /// - Parameter progress: what is being fetched, if anything. It goes in the strip rather than
    ///   only in the tooltip because a tooltip needs you to already suspect something is
    ///   happening and go looking — and the one moment this matters is a nine-megabyte download
    ///   running with the menu closed and nothing else on screen to say so.
    func update(workspaces: [WorkspaceStrip.State], warnings: [String],
                accessibilityGranted: Bool, progress: String? = nil) {
        self.accessibilityGranted = accessibilityGranted
        self.progress = progress
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
        // After the workspaces, never instead of them: what workspace you are on is the thing
        // this item exists to tell you, and a download must not take that away for a minute.
        // No entry goes into `stripItems`, so the click targets are unchanged and clicking the
        // progress opens the menu like clicking anywhere else on the item.
        if let progress {
            strip.append(spacer)
            strip.append(progressPiece(progress))
        }
        return strip
    }

    /// `⟳ Gruvbox 3/6`, in the same dimmed grey an unfocused workspace takes.
    ///
    /// Static rather than animated: an animation needs a timer running for as long as the
    /// download, and the step count already moves often enough to read as alive. The glyph is
    /// there so a glance finds it without reading the words.
    private func progressPiece(_ text: String) -> NSAttributedString {
        NSAttributedString(string: "⟳ " + text, attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor,
        ])
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
        // The baseline, less the half-pixel an attachment is otherwise offset by.
        attachment.bounds = NSRect(x: 0, y: attachmentNudge, width: markWidth, height: markHeight)
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
            // Set like the digit it replaces: on the baseline, at the digits' height.
            attachment.bounds = NSRect(x: 0, y: attachmentNudge,
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
    /// The gutter goes, as it does in that script under 128px: a gap a quarter of a pixel wide
    /// is grey mud rather than a seam. The stem thickening that goes with it there does *not*,
    /// though — it exists to hold the stem up against a crossbar sitting on a tile, and here
    /// there is no tile and the neighbours are light digits, where a stem half again as wide as
    /// the crossbar reads as a different weight of type. Dropped, the two strokes come out equal,
    /// which is what the icon's own proportions ask for at every size that can afford them.
    ///
    /// `labelColor` rather than white, resolved at draw time like the workspace markers: macOS
    /// darkens the menu bar to suit the desktop picture, and a hardcoded white goes invisible
    /// the moment it does not.
    private func mark() -> NSImage {
        let image = NSImage(size: NSSize(width: markWidth, height: markHeight),
                            flipped: false) { rect in
            NSColor.labelColor.setFill()
            let crossbarHeight = self.snap(rect.height * 0.24)
            let stemWidth = self.snap(rect.width * 0.28)
            let radius: CGFloat = 0.5
            let crossbar = NSRect(x: rect.minX, y: rect.maxY - crossbarHeight,
                                  width: rect.width, height: crossbarHeight)
            let stem = NSRect(x: self.snap(rect.midX - stemWidth / 2), y: rect.minY,
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
