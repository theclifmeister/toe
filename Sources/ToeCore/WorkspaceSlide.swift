import Foundation

/// The arithmetic of the workspace slide: which way the screen moves for a workspace target,
/// and how far each of the two pictures travels. Here rather than in `SlideOverlay` for the
/// reason `BorderGeometry` is where it is — the selftest can reach ToeCore and cannot reach a
/// panel, and the direction is the part worth getting wrong once and never again.
public enum WorkspaceSlide {

    /// Which way the content on screen moves.
    public enum Direction: Equatable {
        case left, right
    }

    /// The direction for a target, or nil for a target that does not slide.
    ///
    /// Follows the target rather than the fingers. `.next` is the workspace to the right of this
    /// one in the strip, so the screen slides left to bring it in — and that holds whichever way
    /// the fingers went, because *Natural scrolling* has already been folded into the target by
    /// `WorkspaceTarget.swipe`. Spaces does the same: with natural scrolling off the desktop
    /// moves against the fingers, and nobody calls that a bug. `.index` and `.former` are nil
    /// because nothing animates them yet; when something does, the sign of the index difference
    /// is the answer.
    public static func direction(for target: WorkspaceTarget) -> Direction? {
        switch target {
        case .next: return .left
        case .previous: return .right
        case .index, .former: return nil
        }
    }

    /// One window's place on a picture of the area, relative to the picture's top-left corner.
    public struct Cutout: Equatable {
        public var box: Box
        public var radius: Double

        public init(box: Box, radius: Double) {
            self.box = box
            self.radius = radius
        }
    }

    /// The windows' places on a picture of `area`, for the mask that lets them slide over a
    /// wallpaper that stays put.
    ///
    /// The pictures are of the whole area, wallpaper included, because that is the only kind a
    /// display capture will give: the window server composites onto an opaque backstop, and a
    /// filter that drops the wallpaper leaves black where it was. toe, though, knows where every
    /// window on the workspace is — it put them there — so the pictures are masked to the
    /// windows and a picture of the wallpaper alone goes underneath, which is what Hyprland's
    /// slide looks like: the windows move and the desktop does not. The cost is that a window
    /// toe did not place — a dialog, a palette — is not in the mask and sits the slide out.
    ///
    /// Clipped to the area, so a window that is half off the display masks only the half that
    /// is on it, and one entirely elsewhere is dropped. Relative to the area's top-left because
    /// that is where the picture's pixels start; the layer that draws it flips y itself.
    public static func cutouts(_ windows: [(box: Box, radius: Double)], in area: Box) -> [Cutout] {
        windows.compactMap { window in
            let clipped = window.box.intersection(area)
            guard clipped.w > 0, clipped.h > 0 else { return nil }
            return Cutout(box: Box(x: clipped.x - area.x, y: clipped.y - area.y, w: clipped.w, h: clipped.h),
                          radius: window.radius)
        }
    }

    /// Where the two pictures start and end, as x offsets from their resting place.
    public struct Travel: Equatable {
        /// Where the outgoing picture ends up: one width off, on the side it leaves by.
        public var outgoingEnd: Double
        /// Where the incoming picture starts: one width off, on the side it comes from.
        public var incomingStart: Double

        public init(outgoingEnd: Double, incomingStart: Double) {
            self.outgoingEnd = outgoingEnd
            self.incomingStart = incomingStart
        }
    }

    /// The outgoing picture leaves in `direction`, and the incoming one follows it in from the
    /// opposite edge, so the two are always one width apart and the seam between them crosses
    /// the screen as one piece — which is what makes a push read as a push.
    public static func travel(_ direction: Direction, width: Double) -> Travel {
        switch direction {
        case .left: return Travel(outgoingEnd: -width, incomingStart: width)
        case .right: return Travel(outgoingEnd: width, incomingStart: -width)
        }
    }
}
