import AppKit
import ToeCore

/// The one place toe's animations are drawn: a click-through panel per display, over every
/// window and under the menu bar, that the workspace slide and the tile snap both play on.
///
/// toe cannot animate the windows themselves — each move is a blocking Accessibility round trip,
/// the app repaints when it likes, and transforming another process's window is private SkyLight
/// territory — so every animation it has is the same trick: cover the area, make the real change
/// once underneath, move stand-ins on the cover, and take the cover away when they have come to
/// rest over the windows they stand for. Until this existed the slide and the tile snap each had
/// a panel of their own, configured setting for setting alike, with a backdrop and a dissolve
/// apiece, and nothing to say which of them was on a display: the two could stack, and a card
/// from one was drawn under the other's desktop picture. Now a display has one `OverlayStage`
/// and whoever is animating on it has *claimed* it; a second claim evicts the first, which is
/// told so that a completion of its own arriving later takes nothing down.
final class OverlayHost {

    private var stages: [UInt32: OverlayStage] = [:]

    /// The stage on `display`, now `owner`'s. A different owner holding it is evicted first —
    /// its `onEvict` runs, and the stage is reset under it — and `onEvict` is what this owner
    /// will be told when its own turn comes.
    func claim(_ display: UInt32, by owner: AnyObject,
               onEvict: @escaping () -> Void) -> OverlayStage {
        let stage = stages[display] ?? OverlayStage(display: display)
        stages[display] = stage
        if let current = stage.owner, current !== owner {
            let evicted = stage.onEvict
            stage.hide()
            evicted?()
        }
        stage.owner = owner
        stage.onEvict = onEvict
        return stage
    }

    /// Takes `stage` down if `owner` still holds it, and lets it go. A stage someone else has
    /// claimed since is theirs and is left alone.
    func release(_ stage: OverlayStage, by owner: AnyObject) {
        guard stage.owner === owner else { return }
        stage.hide()
        stage.owner = nil
        stage.onEvict = nil
    }

    /// Whether `owner` is still the one animating on `stage`.
    func holds(_ stage: OverlayStage, _ owner: AnyObject) -> Bool { stage.owner === owner }
}

/// One display's panel, and the two layers every animation on it shares: the backdrop that
/// stands in for the desktop, and `content`, where the owner puts whatever moves.
final class OverlayStage {

    let display: UInt32
    private let panel: NSPanel
    /// The desktop: the desktop picture, a picture of the wallpaper, or the theme's colour.
    /// It does not move.
    let backdrop = CALayer()
    /// The owner's. Emptied on every `prepare` and `hide`.
    let content = CALayer()

    fileprivate weak var owner: AnyObject?
    fileprivate var onEvict: (() -> Void)?
    /// Bumped by every `prepare`, `hide` and `holdDissolve`, so that a dissolve's completion —
    /// which Core Animation runs when the fade is *removed* as well as when it finishes — finds
    /// the stage has moved on and takes nothing down.
    private var generation = 0
    private(set) var isDissolving = false

    var isVisible: Bool { panel.isVisible }
    var bounds: CGRect { content.bounds }
    var scale: CGFloat { panel.backingScaleFactor }
    private var root: CALayer? { panel.contentView?.layer }

    fileprivate init(display: UInt32) {
        self.display = display
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clicks go through to the real windows, which are already in their new places under
        // the stand-ins; an animation is a picture of a change that has happened, not a lock.
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
        // on the slide that was a bounce: the picture popped in before the slide and shrank away
        // after it, with the live screen showing through the fade. The animations on the stage
        // are the only motion this panel is allowed.
        panel.animationBehavior = .none

        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        for layer in [backdrop, content] {
            layer.contentsGravity = .resize
            layer.anchorPoint = .zero
            view.layer?.addSublayer(layer)
        }
        panel.contentView = view
    }

    /// Frames the panel over `area` (AX coordinates), fully opaque and empty, ready for the owner
    /// to fill. Not on screen until `show`. Call inside the owner's own transaction with actions
    /// disabled, or nothing here is instant.
    func prepare(over area: Box) {
        generation += 1
        isDissolving = false
        let rect = Coordinates.toCocoa(area)
        let bounds = CGRect(origin: .zero, size: rect.size)
        root?.removeAllAnimations()
        root?.opacity = 1
        panel.setFrame(rect, display: false)
        panel.contentView?.frame = bounds
        for layer in [backdrop, content] {
            layer.removeAllAnimations()
            layer.frame = bounds
            layer.contentsScale = panel.backingScaleFactor
        }
        backdrop.contents = nil
        backdrop.backgroundColor = nil
        backdrop.contentsGravity = .resize
        backdrop.masksToBounds = false
        content.sublayers = nil
        content.contents = nil
        content.mask = nil
    }

    /// The desktop picture — as `DesktopPictures` decoded it — filling the display's `frame`
    /// behind the area, or `fallback` when there is none yet.
    ///
    /// Placed over the whole display and not just the area, because that is where the window
    /// server draws it: aspect-filled to the display, with the bar's strip and the menu bar's
    /// covering the top of it. The panel's own edge clips the rest.
    func setDesktop(_ image: CGImage?, display frame: Box, area: Box, fallback: CGColor) {
        guard let image else {
            backdrop.contents = nil
            backdrop.backgroundColor = fallback
            return
        }
        let display = Coordinates.toCocoa(frame)
        let rect = Coordinates.toCocoa(area)
        backdrop.frame = CGRect(x: display.minX - rect.minX, y: display.minY - rect.minY,
                                width: display.width, height: display.height)
        backdrop.contentsGravity = .resizeAspectFill
        backdrop.masksToBounds = true
        backdrop.contents = image
        backdrop.backgroundColor = nil
    }

    /// Sends what the owner has built to the render server and puts the panel up.
    ///
    /// Flushed now, not at the end of the run loop turn: the caller is about to move the real
    /// windows, and a panel whose layers have not landed yet is transparent — it showed the
    /// change for a frame and then snapped back to the stand-ins, which read as a flash before
    /// the animation. This is half of the fix; the other half is the caller waiting a couple of
    /// refreshes before it moves anything — see `Coordinator.slidePanelLatency`.
    func show() {
        CATransaction.flush()
        panel.orderFront(nil)
    }

    /// Fades the whole panel — stand-ins and desktop together — over `duration`, then takes it
    /// down and calls `completion`. This is what turns each card into its window in place,
    /// rather than the panel going and the windows appearing. Ease-in-out: a fade wants no hurry
    /// at either end. A `prepare`, `hide` or `holdDissolve` in the meantime cancels the rest,
    /// completion included.
    func dissolve(over duration: Double, completion: @escaping () -> Void) {
        generation += 1
        let mine = generation
        guard duration > 0, let root else { hide(); completion(); return }
        isDissolving = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == mine else { return }
            self.hide()
            completion()
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = root.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        root.add(fade, forKey: "dissolve")
        root.opacity = 0
        CATransaction.commit()
    }

    /// Stops a dissolve that has started and makes the panel opaque again: something is about to
    /// move again under it. Instant, because the real windows under a half-faded panel are
    /// already where the stand-ins are, and the moment the panel is opaque again is the moment
    /// the next move can be made under it.
    func holdDissolve() {
        guard isDissolving else { return }
        generation += 1
        isDissolving = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root?.removeAnimation(forKey: "dissolve")
        root?.opacity = 1
        CATransaction.commit()
    }

    /// Takes the panel down at once and lets go of every picture on it. A 5K Retina picture is
    /// tens of megabytes; nothing on a stage is worth keeping between animations.
    func hide() {
        generation += 1
        isDissolving = false
        panel.orderOut(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root?.removeAllAnimations()
        root?.opacity = 1
        backdrop.contents = nil
        backdrop.backgroundColor = nil
        backdrop.contentsGravity = .resize
        content.removeAllAnimations()
        content.sublayers = nil
        content.mask = nil
        CATransaction.commit()
    }
}

/// The theme, as the cards wear it — on the slide and on the tile snap alike.
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

/// One window's stand-in: a rounded rectangle in the theme's colour, and for the focused window
/// the border ring around it, as `BorderOverlay` draws it outside the window — the gradient over
/// the outset rect, masked to a band the border's width. Nothing else: no icon, no title — see
/// `WorkspaceSlide.Card` on why.
///
/// Its frames are layer frames: y up from the bottom-left of whatever it is in. The callers
/// flip from the AX boxes they have.
final class Card {
    let face = CALayer()
    private(set) var ring: CAGradientLayer?
    private var band: CALayer?
    private let radius: Double
    private let width: Double

    /// `radius` is the window's own corner radius; `ringed` whether it wears the border.
    init(radius: Double, ringed: Bool, style: CardStyle, scale: CGFloat) {
        self.radius = radius
        width = ringed ? style.borderWidth : 0
        face.backgroundColor = style.fill
        face.cornerCurve = .continuous              // the window server's squircle, as the border
        face.masksToBounds = true
        face.contentsScale = scale
        face.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        guard width > 0 else { return }
        let ring = CAGradientLayer()
        ring.colors = style.borderColors
        ring.startPoint = style.borderStart
        ring.endPoint = style.borderEnd
        ring.contentsScale = scale
        let band = CALayer()
        band.borderColor = NSColor.white.cgColor
        band.borderWidth = width
        band.cornerCurve = .continuous
        band.contentsScale = scale
        ring.mask = band
        self.ring = ring
        self.band = band
    }

    /// The face, then the ring over it — the ring lies over the neighbours' gaps.
    func add(to container: CALayer) {
        container.addSublayer(face)
        if let ring { container.addSublayer(ring) }
    }

    func remove() {
        face.removeFromSuperlayer()
        ring?.removeFromSuperlayer()
    }

    /// Stacking within the container: higher is nearer the front, the ring just over its face.
    func setDepth(_ depth: Int) {
        face.zPosition = CGFloat(2 * depth)
        ring?.zPosition = CGFloat(2 * depth + 1)
    }

    /// Puts the card at `rect` now, with nothing animating — the model value every animation
    /// ends on. The corner radius is the one for `smallest`, the smallest size the card will
    /// pass through, because Core Animation traps on a radius over half the shorter side rather
    /// than clamping it, and the radius is not animated.
    func place(_ rect: CGRect, smallest: CGSize? = nil) {
        let size = smallest ?? rect.size
        let r = min(radius, min(size.width, size.height, rect.width, rect.height) / 2)
        face.cornerRadius = max(r, 0)
        face.frame = rect
        guard let ring, let band else { return }
        let outer = rect.insetBy(dx: -width, dy: -width)
        ring.frame = outer
        band.frame = CGRect(origin: .zero, size: outer.size)
        band.cornerRadius = BorderGeometry.outerRadius(inner: face.cornerRadius, width: width)
    }

    /// Runs the card through `rects` — keyframes `step` seconds apart, starting at `begin` on
    /// the media clock — and leaves its model value on the last. `position` and `bounds.size`,
    /// because a frame is not animatable and its two parts are; the ring and its band follow
    /// the same path grown by the border, since a mask does not follow its layer's bounds on its
    /// own.
    func animate(_ rects: [CGRect], step: Double, begin: CFTimeInterval) {
        for layer in [face, ring, band].compactMap({ $0 }) {
            layer.removeAnimation(forKey: "snap.position")
            layer.removeAnimation(forKey: "snap.size")
        }
        guard let last = rects.last else { return }
        let smallest = rects.reduce(CGSize(width: CGFloat.infinity, height: .infinity)) {
            CGSize(width: min($0.width, $1.width), height: min($0.height, $1.height))
        }
        place(last, smallest: smallest)
        guard rects.count > 1 else { return }
        let duration = step * Double(rects.count - 1)
        func run(_ layer: CALayer, _ frames: [CGRect], origin: Bool) {
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = frames.map {
                origin ? CGPoint(x: $0.width / 2, y: $0.height / 2) : CGPoint(x: $0.midX, y: $0.midY)
            }
            let size = CAKeyframeAnimation(keyPath: "bounds.size")
            size.values = frames.map { $0.size }
            for animation in [position, size] {
                animation.duration = duration
                animation.beginTime = begin
                animation.calculationMode = .linear
                // Begun a moment in the past, from where the model has the card now: filled
                // backwards so it is never drawn at its model value first.
                animation.fillMode = .backwards
            }
            layer.add(position, forKey: "snap.position")
            layer.add(size, forKey: "snap.size")
        }
        run(face, rects, origin: false)
        guard let ring, let band else { return }
        let outer = rects.map { $0.insetBy(dx: -width, dy: -width) }
        run(ring, outer, origin: false)
        run(band, outer, origin: true)
    }
}
