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

    var isShowing: Bool { panel.isVisible }

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

    /// Slides the outgoing picture off in `direction`, with `image` — the picture of what is now
    /// on screen, cut down to `cutouts` — following it in, then takes the panel down and forgets
    /// every picture. A nil `image` still slides the old picture off, over the live screen: a
    /// reveal rather than a push, and better than a jump.
    func push(_ image: CGImage?, cutouts: [WorkspaceSlide.Cutout],
              direction: WorkspaceSlide.Direction, duration: Double,
              completion: @escaping () -> Void) {
        guard panel.isVisible else { completion(); return }
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
            self.hide()
            completion()
        }
        incoming.contents = image
        if backdrop.contents != nil, image != nil {
            incomingMask.path = Self.path(cutouts, in: incoming.bounds)
            incoming.mask = incomingMask
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
        // A 5K Retina picture is tens of megabytes; three of them are not worth keeping between
        // swipes for the time a capture takes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.contents = nil
        outgoing.contents = nil
        incoming.contents = nil
        outgoing.mask = nil
        incoming.mask = nil
        outgoing.position = .zero
        incoming.position = .zero
        CATransaction.commit()
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
