import AppKit
import ToeCore

/// PROTOTYPE — the tile snap, animated with stand-ins (`[animations] tile_snap`, off by default).
///
/// The same trick as `SlideOverlay`'s cards, pointed at a layout change instead of a workspace
/// switch. Moving the real windows at animation speed is out for the reasons that panel's doc
/// comment gives — every step is a blocking Accessibility round trip, the app repaints when it
/// likes, and each step would trip `windowFrameChangedExternally`'s corrections — so the real
/// frames are written once, underneath, and what moves is a card per window on a click-through
/// panel over the display: from where each window was to where it is going, on the GPU, in step
/// with the display. When the cards have stopped over the real windows the panel dissolves and
/// the windows, which have had the whole motion to repaint at their new size, are simply there.
///
/// toe cannot hide a window without SIP off, so the panel covers the whole tiling area and
/// draws *every* window on it — the ones that do not move as well, and the floats — over the
/// desktop picture. A panel that drew only the movers would sweep their cards across windows
/// that have already jumped to their new places underneath.
///
/// One of these per display that has something moving; see `Coordinator.beginTileSnap`. Not the
/// final architecture: no shared animation model, no retargeting — a render that moves a tile
/// mid-snap cancels this one and starts the next from the frames the last one was heading for.
final class TileSnapOverlay {

    /// One window's stand-in: where it was and where it is going, both relative to the area's
    /// top-left with y down, as `WorkspaceSlide.Card`'s box is. A nil `from` is a window that
    /// had nowhere to come from on this display, and fades in at its new frame instead.
    struct Move {
        var id: WindowID
        var from: Box?
        var to: Box
        var radius: Double
        var focused: Bool
    }

    private let panel: NSPanel
    /// The desktop picture's container: the ground the cards move over, and the layer the
    /// holes are cut in when the windows that stay put are shown live — see `run`.
    private let ground = CALayer()
    private let backdrop = CALayer()
    private let groundMask = CAShapeLayer()
    private let cards = CALayer()
    /// Bumped by every `run` and `cancel`, so the completion of an animation that was removed
    /// rather than finished — Core Animation calls it either way — takes down nothing.
    private var generation = 0
    private(set) var isRunning = false

    /// Hyprland's `easeOutQuint`, the curve Omarchy's `windows` animation uses: fast off the
    /// mark and a long, soft landing, with no overshoot.
    private static let curve = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    init() {
        // The panel is `SlideOverlay`'s, setting for setting, for the reasons given there.
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none

        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        for layer in [ground, cards] {
            layer.anchorPoint = .zero
            view.layer?.addSublayer(layer)
        }
        backdrop.anchorPoint = .zero
        ground.addSublayer(backdrop)
        groundMask.anchorPoint = .zero
        groundMask.fillRule = .evenOdd          // the area, less every hole
        panel.contentView = view
    }

    /// Puts the cards up over `area` at their old frames and sets them moving to their new ones
    /// at once, over `desktop` filling the display's `frame` — `SlideOverlay`'s backdrop rule.
    /// After `duration` the panel fades over `dissolve` and comes down, and `completion` runs.
    ///
    /// `opacity` is the whole panel's — desktop and cards together — so that below 1 the real
    /// windows show through. They have already jumped to their new frames by then, so what
    /// shows is the end state ghosted under the motion.
    ///
    /// With `liveStill` a window that is not moving gets no card at all: the ground has a hole
    /// cut where it is (grown by the ring for the focused one, so the real border shows too) and
    /// the real window is simply seen. That is safe for tiles because tiles never overlap, so no
    /// moving window's new frame lies inside a still one's hole; a moving card that sweeps over a
    /// hole is drawn on top of it, as the moving window would be.
    ///
    /// The caller writes the real frames a couple of refreshes *after* this returns, not before:
    /// the panel has to be composited before anything under it moves, or the windows' jump
    /// shows for a frame first. See `Coordinator.slidePanelLatency`.
    func run(_ moves: [Move], over area: Box, display frame: Box, desktop: CGImage?,
             style: SlideOverlay.CardStyle, duration: Double, dissolve: Double,
             opacity: Double, liveStill: Bool, completion: @escaping () -> Void) {
        generation += 1
        let mine = generation
        isRunning = true
        let rect = Coordinates.toCocoa(area)
        let bounds = CGRect(origin: .zero, size: rect.size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.contentView?.layer?.removeAllAnimations()
        panel.setFrame(rect, display: false)
        panel.contentView?.frame = bounds
        panel.contentView?.layer?.opacity = Float(opacity)
        let scale = panel.backingScaleFactor
        ground.frame = bounds
        cards.frame = bounds
        cards.sublayers = nil
        backdrop.contentsScale = scale
        if let desktop {
            let display = Coordinates.toCocoa(frame)
            backdrop.frame = CGRect(x: display.minX - rect.minX, y: display.minY - rect.minY,
                                    width: display.width, height: display.height)
            backdrop.contentsGravity = .resizeAspectFill
            backdrop.masksToBounds = true
            backdrop.contents = desktop
            backdrop.backgroundColor = nil
        } else {
            backdrop.frame = bounds
            backdrop.contents = nil
            backdrop.backgroundColor = style.backdrop
        }
        if liveStill {
            let path = CGMutablePath()
            path.addRect(bounds)
            for move in moves where move.from == move.to {
                let w = move.focused ? style.borderWidth : 0
                let rect = CGRect(x: move.to.x - w, y: bounds.height - move.to.y - move.to.h - w,
                                  width: move.to.w + 2 * w, height: move.to.h + 2 * w)
                let radius = min(move.radius + w, min(rect.width, rect.height) / 2)
                path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            }
            groundMask.frame = bounds
            groundMask.path = path
            ground.mask = groundMask
        } else {
            ground.mask = nil
        }
        CATransaction.commit()

        // A second transaction for the motion, so its completion block — the start of the
        // dissolve — is the moves' own and not the setup's.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == mine else { return }
            guard dissolve > 0, let root = self.panel.contentView?.layer else {
                self.hide(); completion(); return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.generation == mine else { return }
                self.hide(); completion()
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity
            fade.toValue = 0
            fade.duration = dissolve
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            root.add(fade, forKey: "dissolve")
            root.opacity = 0
            CATransaction.commit()
        }
        let height = bounds.height
        for move in moves where !(liveStill && move.from == move.to) {
            add(move, to: cards, height: height, style: style, scale: scale, duration: duration)
        }
        CATransaction.commit()
        // Sent now rather than at the end of the run loop turn, as `SlideOverlay.begin` does:
        // the caller is about to move the real windows.
        CATransaction.flush()
        panel.orderFront(nil)
    }

    /// Takes the panel down at once. The real windows under it are already where the model
    /// says — or about to be, a refresh or two from now — so nothing is lost but the motion.
    func cancel() {
        guard isRunning else { return }
        generation += 1
        hide()
    }

    private func hide() {
        isRunning = false
        panel.orderOut(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.contentView?.layer?.removeAllAnimations()
        panel.contentView?.layer?.opacity = 1
        cards.sublayers = nil
        ground.mask = nil
        backdrop.contents = nil
        backdrop.backgroundColor = nil
        CATransaction.commit()
    }

    // MARK: - Cards

    /// A card for `move` in `container`, its model frame the new one and an animation from the
    /// old — and the focused one's ring with it, the gradient and the band that masks it each
    /// animated the same way, since a mask does not follow its layer's bounds on its own.
    private func add(_ move: Move, to container: CALayer, height: CGFloat,
                     style: SlideOverlay.CardStyle, scale: CGFloat, duration: Double) {
        func flip(_ box: Box) -> CGRect {
            CGRect(x: box.x, y: height - box.y - box.h, width: box.w, height: box.h)
        }
        let to = flip(move.to)
        let from = move.from.map(flip)
        // Core Animation traps on a radius over half the shorter side rather than clamping, and
        // the radius is not animated, so it has to fit the smaller of the two frames.
        let smallest = min(to.width, to.height, from?.width ?? .infinity, from?.height ?? .infinity)
        let radius = min(move.radius, smallest / 2)

        let face = CALayer()
        face.frame = to
        face.backgroundColor = style.fill
        face.cornerRadius = radius
        face.cornerCurve = .continuous
        face.contentsScale = scale
        container.addSublayer(face)
        animate(face, from: from, to: to, duration: duration)

        guard move.focused, style.borderWidth > 0 else { return }
        let w = style.borderWidth
        let ringTo = to.insetBy(dx: -w, dy: -w)
        let ringFrom = from?.insetBy(dx: -w, dy: -w)
        let ring = CAGradientLayer()
        ring.frame = ringTo
        ring.colors = style.borderColors
        ring.startPoint = style.borderStart
        ring.endPoint = style.borderEnd
        ring.contentsScale = scale
        let band = CALayer()
        band.frame = CGRect(origin: .zero, size: ringTo.size)
        band.borderColor = NSColor.white.cgColor
        band.borderWidth = w
        band.cornerRadius = BorderGeometry.outerRadius(inner: radius, width: w)
        band.cornerCurve = .continuous
        band.contentsScale = scale
        ring.mask = band
        container.addSublayer(ring)
        animate(ring, from: ringFrom, to: ringTo, duration: duration)
        animate(band, from: ringFrom.map { CGRect(origin: .zero, size: $0.size) },
                to: band.frame, duration: duration)
    }

    /// `position` and `bounds` from `from` to `to` — a frame is not animatable, its two parts
    /// are — or, with no `from`, a fade in where the layer already is.
    private func animate(_ layer: CALayer, from: CGRect?, to: CGRect, duration: Double) {
        guard let from else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = duration
            fade.timingFunction = Self.curve
            layer.add(fade, forKey: "snap.opacity")
            return
        }
        guard from != to else { return }
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = CGPoint(x: from.midX, y: from.midY)
        position.toValue = CGPoint(x: to.midX, y: to.midY)
        let bounds = CABasicAnimation(keyPath: "bounds.size")
        bounds.fromValue = from.size
        bounds.toValue = to.size
        for animation in [position, bounds] {
            animation.duration = duration
            animation.timingFunction = Self.curve
        }
        layer.add(position, forKey: "snap.position")
        layer.add(bounds, forKey: "snap.bounds")
    }
}
