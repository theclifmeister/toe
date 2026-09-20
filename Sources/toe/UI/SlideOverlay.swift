import AppKit
import ToeCore

/// The workspace slide, done with pictures on a click-through panel.
///
/// Spaces slides because the window server composites the desktop as one texture and can move
/// it. toe has no such handle: the windows on screen belong to other processes, each move is a
/// synchronous Accessibility round trip capped at 250 ms, and the app repaints when it likes —
/// so moving the real windows at animation speed is out, and so is transforming them, which is
/// private SkyLight territory. What is left is what a picture can do: cover the screen with a
/// photograph of the outgoing workspace, make the real switch underneath, photograph the result,
/// and slide the two. The pictures come from `ScreenSnapshot`; the arithmetic of who moves where
/// is `WorkspaceSlide`'s, where the selftest can reach it.
///
/// Three pictures, not two. The first version slid whole screenshots, wallpaper and all, and
/// that is what Spaces does — but Spaces has a different wallpaper per Space, and the same
/// picture leaving by one edge and arriving by the other looked like a mistake. Hyprland's slide
/// moves the windows over a desktop that stays put, so this does too: a picture of the wallpaper
/// alone at the bottom, and the two pictures of the workspaces above it masked to their windows
/// (`WorkspaceSlide.cutouts`), which toe can do because it knows where every window it placed is.
///
/// Or no pictures at all. `SlideStyle.cards` puts a stand-in where each window is — its frame
/// as a rounded rectangle in the theme's colour, the border ring around the focused one — and
/// slides those over the desktop picture read from its file. Everything about a card is
/// something toe already knew, so nothing is photographed and nothing is asked for; and since
/// there is nothing to wait for, the cards move the instant the swipe commits. The same two
/// containers carry them, `outgoing` and `incoming`, as a few layers instead of one picture
/// and a mask, and the same `push` moves them. What is new is the end:
/// the cards come to rest exactly over the real windows, which arrived under them during the
/// slide, and then *dissolve* — the whole panel fades over `dissolve` seconds and the windows
/// are simply there. A picture snaps to the live screen; a card melts into it.
final class SlideOverlay {

    private let panel: NSPanel
    /// The wallpaper, which does not move.
    private let backdrop = CALayer()
    /// The picture of the workspace being left, and the one arriving. Two layers rather than one
    /// composed image, because the incoming picture arrives after the panel is already up — see
    /// `Coordinator.beginSlide` — and its layer sits off to the side until it does.
    private let outgoing = CALayer()
    private let incoming = CALayer()
    /// Each picture's mask: its windows, rounded as the window server rounds them. A mask lives
    /// in its layer's own coordinates, so it slides with the picture it is cut into.
    private let outgoingMask = CAShapeLayer()
    private let incomingMask = CAShapeLayer()
    /// Which slide the layers are showing. A Core Animation completion block runs when its
    /// animation is *removed* as well as when it finishes, so a `cancel` made for a new swipe
    /// would otherwise fire the old slide's completion and take down the panel the new one has
    /// just put up.
    private var generation = 0

    /// The theme, as the cards wear it.
    struct CardStyle {
        var fill: CGColor
        /// What shows behind the cards when there is no desktop picture to show.
        var backdrop: CGColor
        /// The focused card's ring: `BorderOverlay`'s gradient, or nothing with a width of 0.
        var borderWidth: Double
        var borderColors: [CGColor]
        var borderStart: CGPoint
        var borderEnd: CGPoint
    }

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clicks go through to the real windows, which are already in their new places under
        // the pictures; the slide is a picture of a switch that has happened, not a lock.
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        // One level under the menu bar: above every ordinary and floating window, above the Dock
        // (20), below the menu bar (24) and anything that opens from it. The panel only spans
        // the usable area, so the menu bar and the Dock stay where they are while the windows
        // move.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // AppKit animates a panel on and off screen by default — a short zoom with a fade — and
        // on this one that was a bounce: the picture popped in before the slide and shrank away
        // after it, with the live screen showing through the fade. The slide is the only motion
        // this panel is allowed.
        panel.animationBehavior = .none

        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        for layer in [backdrop, outgoing, incoming] {
            layer.contentsGravity = .resize
            layer.anchorPoint = .zero
            view.layer?.addSublayer(layer)
        }
        for mask in [outgoingMask, incomingMask] {
            mask.fillRule = .nonZero          // overlapping windows add up rather than cancel
            mask.anchorPoint = .zero
        }
        panel.contentView = view
    }

    /// Puts `image`, a picture of `area` (AX coordinates), over that area and brings the panel
    /// up. From here until `push` or `cancel` the user is looking at a photograph.
    ///
    /// With a `wallpaper` picture the photograph is cut down to `cutouts` — its windows — and the
    /// wallpaper shows through the rest. Without one there is nothing to show through to, so the
    /// whole picture is used and the wallpaper slides along: the first version's behaviour, kept
    /// as the fallback for a wallpaper that could not be pictured.
    func begin(showing image: CGImage, over area: Box, wallpaper: CGImage?,
               cutouts: [WorkspaceSlide.Cutout]) {
        generation += 1
        let rect = Coordinates.toCocoa(area)
        let bounds = CGRect(origin: .zero, size: rect.size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoing.removeAllAnimations()
        incoming.removeAllAnimations()
        panel.setFrame(rect, display: false)
        panel.contentView?.frame = bounds
        let scale = panel.backingScaleFactor
        for layer in [backdrop, outgoing, incoming, outgoingMask, incomingMask] {
            layer.frame = bounds
            layer.contentsScale = scale
        }
        backdrop.contents = wallpaper
        outgoing.contents = image
        incoming.contents = nil
        if wallpaper != nil {
            outgoingMask.path = Self.path(cutouts, in: bounds)
            outgoing.mask = outgoingMask
        } else {
            outgoing.mask = nil
        }
        incoming.mask = nil
        CATransaction.commit()
        // Sent to the render server now, not at the end of the run loop turn. The caller is about
        // to move the real windows, and a panel whose picture has not landed yet is transparent:
        // it showed the switch for a frame and then snapped back to the picture of what was
        // there before, which read as a flash before the slide. This is half of the fix; the
        // other half is the caller waiting a couple of refreshes before it moves anything — see
        // `Coordinator.slidePanelLatency`.
        CATransaction.flush()

        panel.orderFront(nil)
    }

    /// Puts the cards of the workspace being left over `area` and brings the panel up, with
    /// `desktop` — the desktop picture as `DesktopPictures` decoded it — filling the display's
    /// `frame` behind them, or the style's backdrop colour when there is none yet.
    ///
    /// The desktop picture is placed over the whole display and not just the area, because
    /// that is where the window server draws it: aspect-filled to the display, with the bar's
    /// strip and the menu bar's covering the top of it. The panel's own edge clips the rest.
    func begin(cards: [WorkspaceSlide.Card], over area: Box, display frame: Box,
               desktop: CGImage?, style: CardStyle) {
        generation += 1
        let rect = Coordinates.toCocoa(area)
        let bounds = CGRect(origin: .zero, size: rect.size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoing.removeAllAnimations()
        incoming.removeAllAnimations()
        panel.setFrame(rect, display: false)
        panel.contentView?.frame = bounds
        panel.contentView?.layer?.opacity = 1
        let scale = panel.backingScaleFactor
        for layer in [backdrop, outgoing, incoming] {
            layer.frame = bounds
            layer.contentsScale = scale
        }
        if let desktop {
            let display = Coordinates.toCocoa(frame)
            backdrop.frame = CGRect(x: display.minX - rect.minX, y: display.minY - rect.minY,
                                    width: display.width, height: display.height)
            backdrop.contentsGravity = .resizeAspectFill
            backdrop.masksToBounds = true
            backdrop.contents = desktop
            backdrop.backgroundColor = nil
        } else {
            backdrop.contents = nil
            backdrop.backgroundColor = style.backdrop
        }
        outgoing.contents = nil
        outgoing.mask = nil
        incoming.contents = nil
        incoming.mask = nil
        Self.populate(outgoing, with: cards, style: style, scale: scale)
        CATransaction.commit()
        // Flushed for the same reason as the pictures' `begin`: the caller is about to move the
        // real windows under this, and the panel has to have landed first.
        CATransaction.flush()

        panel.orderFront(nil)
    }

    /// Slides the outgoing picture off in `direction`, with `image` — the picture of what is now
    /// on screen, cut down to `cutouts` — following it in, then takes the panel down and forgets
    /// every picture. A nil `image` still slides the old picture off, over the live screen: a
    /// reveal rather than a push, and better than a jump.
    ///
    /// With a `dissolve` the panel fades out over that many seconds once the pictures have come
    /// to rest, instead of dropping in one frame. Zero for the photographs — a photograph at
    /// rest already *is* the screen under it, and a fade would only blur the moment it is
    /// replaced by the live one.
    func push(_ image: CGImage?, cutouts: [WorkspaceSlide.Cutout],
              direction: WorkspaceSlide.Direction, duration: Double, dissolve: Double = 0,
              completion: @escaping () -> Void) {
        guard panel.isVisible else { completion(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.contents = image
        if backdrop.contents != nil, image != nil {
            incomingMask.path = Self.path(cutouts, in: incoming.bounds)
            incoming.mask = incomingMask
        }
        CATransaction.commit()
        slide(direction: direction, duration: duration, dissolve: dissolve, completion: completion)
    }

    /// The cards' `push`: the arriving workspace's cards follow the leaving ones in, and when
    /// they have stopped over the real windows the panel dissolves off them.
    func push(cards: [WorkspaceSlide.Card], style: CardStyle,
              direction: WorkspaceSlide.Direction, duration: Double, dissolve: Double,
              completion: @escaping () -> Void) {
        guard panel.isVisible else { completion(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        Self.populate(incoming, with: cards, style: style, scale: panel.backingScaleFactor)
        CATransaction.commit()
        slide(direction: direction, duration: duration, dissolve: dissolve, completion: completion)
    }

    /// The motion itself, for either kind of content: the outgoing container off in
    /// `direction`, the incoming one in behind it, then the dissolve if there is one, then
    /// down.
    private func slide(direction: WorkspaceSlide.Direction, duration: Double, dissolve: Double,
                       completion: @escaping () -> Void) {
        generation += 1
        let mine = generation
        let travel = WorkspaceSlide.travel(direction, width: Double(panel.frame.width))

        // One transaction, implicit actions off: the explicit animations below are the whole of
        // the motion. With actions left on, setting the model values would add an implicit
        // animation of the same property on top of the explicit one.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == mine else { return }
            guard dissolve > 0, let root = self.panel.contentView?.layer else {
                self.hide()
                completion()
                return
            }
            // The cards are at rest over the windows they stand for, and the windows have had
            // the whole slide to paint. Fading the panel — the desktop picture with them — is
            // what turns each card into its window in place, rather than the panel going and
            // the windows appearing. Ease-in-out: a fade wants no hurry at either end.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.generation == mine else { return }
                self.hide()
                completion()
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = dissolve
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            root.add(fade, forKey: "dissolve")
            root.opacity = 0
            CATransaction.commit()
        }
        outgoing.add(Self.move(from: 0, to: travel.outgoingEnd, duration: duration), forKey: "slide")
        incoming.add(Self.move(from: travel.incomingStart, to: 0, duration: duration), forKey: "slide")
        // The model values go to where the animation ends, so that a layer is where it looks
        // like it is if anything reads it mid-slide.
        outgoing.position = CGPoint(x: travel.outgoingEnd, y: 0)
        incoming.position = .zero
        CATransaction.commit()
    }

    /// Takes the panel down at once, mid-slide or not. The live screen underneath is already
    /// the end state, so nothing is lost but the rest of the motion.
    func cancel() {
        generation += 1
        outgoing.removeAllAnimations()
        incoming.removeAllAnimations()
        hide()
    }

    private func hide() {
        panel.orderOut(nil)
        panel.contentView?.layer?.removeAllAnimations()
        // A 5K Retina picture is tens of megabytes; three of them are not worth keeping between
        // swipes for the time a capture takes. The cards go too, so that the next slide starts
        // from an empty container either way.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.contentView?.layer?.opacity = 1
        backdrop.contents = nil
        backdrop.backgroundColor = nil
        backdrop.contentsGravity = .resize
        outgoing.contents = nil
        incoming.contents = nil
        outgoing.mask = nil
        incoming.mask = nil
        outgoing.sublayers = nil
        incoming.sublayers = nil
        outgoing.position = .zero
        incoming.position = .zero
        CATransaction.commit()
    }

    // MARK: - Cards

    /// Builds the cards into `container` — a layer per card and one more for the focused one's
    /// ring, in the order given, so the last is on top. A card's coordinates are y-down from
    /// the area's top-left, as a picture's pixels are; a layer's are y-up from the bottom-left,
    /// so each is flipped on the way in, as `path` flips the cutouts.
    private static func populate(_ container: CALayer, with cards: [WorkspaceSlide.Card],
                                 style: CardStyle, scale: CGFloat) {
        container.sublayers = nil
        let height = container.bounds.height
        for card in cards {
            let rect = CGRect(x: card.box.x, y: height - card.box.y - card.box.h,
                              width: card.box.w, height: card.box.h)
            // Core Animation traps on a radius over half the shorter side rather than clamping.
            let radius = min(card.radius, min(rect.width, rect.height) / 2)

            let face = CALayer()
            face.frame = rect
            face.backgroundColor = style.fill
            face.cornerRadius = radius
            face.cornerCurve = .continuous              // the window server's squircle, as the border
            face.masksToBounds = true
            face.contentsScale = scale

            container.addSublayer(face)

            // The ring, outside the card as `BorderOverlay` draws it outside the window: the
            // gradient over the outset rect, masked to a band the border's width. Under the
            // focused card only, which has the ring in the real world too.
            guard card.focused, style.borderWidth > 0 else { continue }
            let w = style.borderWidth
            let ring = CAGradientLayer()
            ring.frame = rect.insetBy(dx: -w, dy: -w)
            ring.colors = style.borderColors
            ring.startPoint = style.borderStart
            ring.endPoint = style.borderEnd
            ring.contentsScale = scale
            let band = CALayer()
            band.frame = CGRect(origin: .zero, size: ring.frame.size)
            band.borderColor = NSColor.white.cgColor
            band.borderWidth = w
            band.cornerRadius = BorderGeometry.outerRadius(inner: radius, width: w)
            band.cornerCurve = .continuous
            band.contentsScale = scale
            ring.mask = band
            container.addSublayer(ring)
        }
    }

    /// The windows as one path, in the layer's coordinates. The cutouts are relative to the
    /// picture's top-left corner with y down, as the picture is; a layer's origin is bottom-left
    /// with y up, so each box is flipped within the bounds on the way in.
    private static func path(_ cutouts: [WorkspaceSlide.Cutout], in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        for cutout in cutouts {
            let box = cutout.box
            let rect = CGRect(x: box.x, y: bounds.height - box.y - box.h, width: box.w, height: box.h)
            // Core Animation traps on a radius over half the shorter side rather than clamping.
            let radius = min(cutout.radius, min(rect.width, rect.height) / 2)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    private static func move(from: Double, to: Double, duration: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        // Ease-out, not ease-in-out: the picture has already been sitting still while the switch
        // was made under it, and a slow start on top of that hold read as hesitation. Fast off
        // the mark and settling at the end is what a swipe's momentum looks like — and there is
        // no overshoot in it, so nothing bounces.
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }
}
