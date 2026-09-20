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

    /// Whether a window on the system is the desktop picture, from what the window list says
    /// about it: its title and its level.
    ///
    /// The wallpaper picture under the slide is a capture of that window alone, and the window
    /// has moved house once already. Through macOS 15 it was the Dock's — `Wallpaper-<name>`,
    /// one per display — and the capture asked for the Dock's windows by bundle identifier. On
    /// macOS 26 the desktop picture is drawn by `WindowManager` (`com.apple.WindowManager`) in a
    /// window titled `Wallpaper`, so a filter on the Dock included nothing on screen and the
    /// window server refused to make the picture: "Failed to start stream due to audio/video
    /// capture failure", once per launch and once per swipe, with the slide silently pushing
    /// the wallpaper along with the windows. So the owner is not named at all — the window is
    /// found by what it *is*, and whoever draws it is who the filter asks for. The two clues are
    /// the ones both owners share: the title starts with `Wallpaper`, and it sits below level
    /// zero, where nothing but the desktop lives (Finder's icon layer and the window server's
    /// own backstop are the neighbours, and neither is called that).
    public static func isDesktopPicture(title: String?, layer: Int) -> Bool {
        layer < 0 && (title ?? "").hasPrefix("Wallpaper")
    }

    /// One window's stand-in on a cards slide: where it is on the area, how it is rounded, and
    /// whether it wears the border. Nothing else — no icon, no title. The first cut drew both,
    /// and the cards read as labels sliding about rather than as windows; a plain rounded
    /// rectangle where each window is, in the theme's colour, reads as the window with its
    /// content taken out, which is what it is.
    public struct Card: Equatable {
        public var id: WindowID
        /// Relative to the area's top-left, y down, like a `Cutout` — but not clipped to it. A
        /// cutout is a hole in a photograph and stops where the photograph does; a card is a
        /// drawn thing with rounded corners and a border, and clipping it would square the
        /// corners off. The panel's own edge does the clipping, and a window that is entirely
        /// elsewhere is left out.
        public var box: Box
        public var radius: Double
        public var focused: Bool

        public init(id: WindowID, box: Box, radius: Double, focused: Bool) {
            self.id = id; self.box = box; self.radius = radius; self.focused = focused
        }
    }

    /// The cards for the windows on `area`, in the order given — which is the order they are
    /// drawn in, so a caller wanting the focused one on top puts it last.
    public static func cards(_ windows: [(id: WindowID, box: Box, radius: Double, focused: Bool)],
                             in area: Box) -> [Card] {
        windows.compactMap { window in
            let clipped = window.box.intersection(area)
            guard clipped.w > 0, clipped.h > 0 else { return nil }
            return Card(id: window.id,
                        box: Box(x: window.box.x - area.x, y: window.box.y - area.y,
                                 w: window.box.w, h: window.box.h),
                        radius: window.radius, focused: window.focused)
        }
    }

    /// What a picture of a workspace is a picture *of*, as far as the slide can tell: which
    /// windows, where, and which one wore the border. Two fingerprints that are equal say a
    /// picture taken under the first still shows the windows where the second has them.
    ///
    /// This is what lets a picture outlive the swipe it was taken for. The slide's second
    /// picture — the workspace coming in — used to be taken after the switch, which meant the
    /// switch, a beat for the apps to paint, and a capture, all before anything moved: some
    /// 260 ms from the fingers committing to the first frame of motion, measured on a 14"
    /// MacBook. But a workspace that was left a minute ago mostly looks as it did when it was
    /// left, and the slide is a third of a second of motion under which nobody reads a terminal
    /// — so the picture taken on the way *out* of a workspace is kept and shown on the way back
    /// *in*, and the live screen replaces it when the slide ends. What must not be stale is
    /// the shape: a window that opened, closed or moved while the workspace was away would show
    /// through its mask as the wrong thing or as a hole, so a kept picture is used only when
    /// the fingerprint it was taken under is the one the workspace has now. Content — what the
    /// windows were showing — is allowed to be a minute old; geometry is not allowed to be a
    /// pixel off. The focused window is part of it because the border ring is in the picture
    /// and its cutout is grown for it; the same picture under a different focus would have the
    /// ring around the wrong window for the length of the slide.
    public struct Fingerprint: Equatable {
        /// The workspace's windows and the frames they were rendered to, tiled and floating.
        public var windows: [WindowID: Box]
        /// The window with the border, if it was one of them.
        public var focused: WindowID?

        public init(windows: [WindowID: Box], focused: WindowID?) {
            self.windows = windows
            self.focused = focused
        }

        /// The fingerprint of `workspace` — the ids of its windows — under `plan`, with the
        /// border on `focused`. A focus on another display's workspace is nobody's here.
        public init(plan: RenderPlan, of workspace: Set<WindowID>, focused: WindowID?) {
            var windows: [WindowID: Box] = [:]
            for (id, box) in plan.frames where workspace.contains(id) { windows[id] = box }
            for (id, box) in plan.floating where workspace.contains(id) { windows[id] = box }
            self.windows = windows
            self.focused = focused.flatMap { workspace.contains($0) ? $0 : nil }
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
