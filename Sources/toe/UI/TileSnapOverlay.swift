import AppKit
import ToeCore

/// The tile snap: a layout change — a swap, a split flipping or moving, a window opening,
/// closing or floating — animated with stand-ins (`[animations] tile_snap`).
///
/// The same trick as `SlideOverlay`'s cards, pointed at a layout change instead of a workspace
/// switch, and on the same panels (`OverlayHost`). Moving the real windows at animation speed is
/// out for the reasons that panel's doc comment gives — every step is a blocking Accessibility
/// round trip, the app repaints when it likes, and each step would trip
/// `windowFrameChangedExternally`'s corrections — so the real frames are written once, underneath,
/// and what moves is a card per window on a click-through panel over each display involved: from
/// where each window was to where it is going. When the cards have landed over the real windows,
/// and the windows have said they are there, the panel dissolves and the windows, which have had
/// the whole motion to repaint at their new size, are simply there.
///
/// toe cannot hide a window without SIP off, so the panel covers the whole tiling area and draws
/// *every* window on it — the ones that do not move as well, and the floats — over the desktop
/// picture. A panel that drew only the movers would sweep their cards across windows that have
/// already jumped to their new places underneath; and the prototype's "live" variant, which cut
/// holes for the windows that stayed put, looked wrong on screen, as did a see-through panel.
///
/// The motion is `TileSnap.Motion`'s, a spring per window. It is handed to the render server as
/// keyframes sampled from the model, so the main thread — which spends up to a quarter of a
/// second in an Accessibility call when an app is slow — never has to be on time for a frame.
/// A layout arriving mid-motion *retargets*: each card whose slot changed starts a new leg from
/// where the model says it is now, at the speed it is moving now, which is exactly where the
/// render server is drawing it, since that is what it was given. Reading the presentation layer
/// would give the same position and no velocity.
final class TileSnapOverlay {

    /// A display the snap may draw on: its id, the tiling area the panel covers, the whole frame
    /// the desktop picture fills, and that picture.
    struct Display {
        var id: UInt32
        var area: Box
        var frame: Box
        var desktop: CGImage?
    }

    /// Everything a snap needs to know about the screen, from the coordinator, in AX coordinates.
    struct Scene {
        /// Where every visible window is going.
        var targets: [WindowID: Box]
        /// Where a window new to the motion was before this layout, if anywhere.
        var origins: [WindowID: Box]
        var radii: [WindowID: Double]
        var focused: WindowID?
        /// The window server's order, frontmost first — `WindowStack.frontToBack`.
        var frontToBack: [WindowID]
        var displays: [Display]
        var style: CardStyle
        var spring: TileSnap.Spring
        var dissolve: Double
    }

    /// How long past landing the hand-off waits for a window that has not reported its new frame
    /// before dissolving anyway. An app that refuses the frame — a minimum size bigger than its
    /// tile — never reports one, and the screen is not held for it. Long enough for an app busy
    /// laying itself out at the new size to answer; short enough that a wait is not a hang.
    private static let handoffTimeout: TimeInterval = 0.25

    private let host: OverlayHost
    private var motion: TileSnap.Motion?
    /// One per display the snap is drawing on, until it ends.
    private var stages: [UInt32: StageState] = [:]
    private var focused: WindowID?
    /// Real windows not yet seen at their new frames.
    private var awaiting: Set<WindowID> = []
    private var hasLanded = false
    private var landing: DispatchWorkItem?
    private var deadline: DispatchWorkItem?
    private var dissolving = 0
    /// When the current snap began, for the log line at the hand-off.
    private var began: CFTimeInterval = 0
    /// Called when a snap has finished — dissolved, not cancelled.
    var onFinished: (() -> Void)?

    private final class StageState {
        let stage: OverlayStage
        let area: Box
        var cards: [WindowID: Card] = [:]
        init(stage: OverlayStage, area: Box) { self.stage = stage; self.area = area }

        /// A box in AX coordinates as a layer rect on this stage: relative to the area's
        /// top-left, then flipped, y up.
        func rect(_ box: Box) -> CGRect {
            CGRect(x: box.x - area.x, y: area.h - (box.y - area.y) - box.h, width: box.w, height: box.h)
        }
    }

    init(host: OverlayHost) { self.host = host }

    var isRunning: Bool { motion != nil }

    /// Where the snap last sent `id`, if it has it: for the coordinator, which retargets only
    /// when a window's slot has actually changed.
    func target(of id: WindowID) -> Box? { motion?.tracks[id]?.to }
    var windows: Set<WindowID> { Set(motion?.tracks.keys.map { $0 } ?? []) }
    var focusedWindow: WindowID? { focused }

    /// Starts a snap, or retargets the one in flight, towards `scene`.
    ///
    /// The caller writes the real frames a couple of refreshes *after* this returns, not
    /// before: a stage that has just been put up has to be composited before anything under it
    /// moves, or the windows' jump shows for a frame first. See `Coordinator.slidePanelLatency`.
    func run(_ scene: Scene) {
        let now = CACurrentMediaTime()
        if self.motion == nil { began = now }
        var motion = self.motion ?? TileSnap.Motion(spring: scene.spring)
        motion.spring = scene.spring
        let changed = motion.retarget(to: scene.targets, from: scene.origins, at: now)
        self.motion = motion
        let refocused = focused != scene.focused
        let oldFocus = focused
        focused = scene.focused

        func overlaps(_ box: Box, _ area: Box) -> Bool {
            let clipped = box.intersection(area)
            return clipped.w > 0 && clipped.h > 0
        }
        /// The windows a display has to draw: every window whose card is, or will be, on it.
        func residents(of area: Box) -> [WindowID] {
            motion.tracks.compactMap { id, track in
                let here = track.frame(at: now, motion.spring)
                return overlaps(here, area) || overlaps(track.to, area) ? id : nil
            }
        }
        let order = TileSnap.drawOrder(motion.tracks.keys, frontToBack: scene.frontToBack)
        let depth = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        var fresh: [StageState] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for display in scene.displays {
            let living = residents(of: display.area)
            // A display joins the snap when a card that is moving is on it; one already in the
            // snap stays until the end, so a card that leaves it is not cut off mid-flight.
            let moving = living.contains { id in
                guard let track = motion.tracks[id] else { return false }
                return !track.isWithin(TileSnap.restDistance, at: now, motion.spring)
            }
            var state = stages[display.id]
            if state == nil {
                guard moving else { continue }
                let stage = host.claim(display.id, by: self) { [weak self] in
                    self?.evicted(from: display.id)
                }
                stage.prepare(over: display.area)
                stage.setDesktop(display.desktop, display: display.frame, area: display.area,
                                 fallback: scene.style.backdrop)
                let made = StageState(stage: stage, area: display.area)
                stages[display.id] = made
                fresh.append(made)
                state = made
            }
            guard let state else { continue }
            state.stage.holdDissolve()

            // Cards for windows that have gone — closed, sent away — go with them.
            for (id, card) in state.cards where !living.contains(id) && motion.tracks[id] == nil {
                card.remove()
                state.cards.removeValue(forKey: id)
            }
            for id in living {
                let ringed = id == scene.focused
                let needsRing = refocused && (id == scene.focused || id == oldFocus)
                var card = state.cards[id]
                let isNew = card == nil || needsRing
                if isNew {
                    card?.remove()
                    let made = Card(radius: scene.radii[id] ?? Double(SystemCornerRadius.points),
                                    ringed: ringed, style: scene.style, scale: state.stage.scale)
                    made.add(to: state.stage.content)
                    state.cards[id] = made
                    card = made
                }
                guard let card else { continue }
                card.setDepth(depth[id] ?? order.count)
                // A card made just now — a display joining, a ring moving to another window —
                // takes up the motion where the model has it, as does every card whose slot moved.
                if changed.contains(id) || isNew {
                    let frames = motion.samples(of: id, from: now).map(state.rect)
                    card.animate(frames, step: 1.0 / 120, begin: now)
                }
            }
        }
        CATransaction.commit()
        for state in fresh { state.stage.show() }
        if fresh.isEmpty { CATransaction.flush() }

        guard !stages.isEmpty else { finish(); return }
        awaiting.formIntersection(Set(motion.tracks.keys))
        hasLanded = false
        dissolving = 0
        dissolveDuration = scene.dissolve
        schedule(landingAt: motion.landing(after: now), from: now)
        Log.info("tile snap: \(changed.count) of \(motion.tracks.count) card(s) set moving"
                 + " on \(stages.count) display(s)"
                 + (fresh.isEmpty ? ", retargeted" : "")
                 + (scene.displays.contains { $0.desktop == nil && stages[$0.id] != nil }
                    ? " — no desktop picture yet, over the theme colour" : ""))
    }

    private var dissolveDuration = 0.15

    /// The windows whose real frames are being written for the layout `run` was just given: the
    /// hand-off waits for each to report its new frame.
    func expect(_ ids: Set<WindowID>) {
        guard isRunning else { return }
        awaiting.formUnion(ids.intersection(windows))
    }

    /// A real window has reported the frame it was written: one fewer to wait for.
    func arrived(_ id: WindowID) {
        guard awaiting.remove(id) != nil, hasLanded, awaiting.isEmpty else { return }
        handOff()
    }

    /// Takes every stage down at once. The real windows under them are already where the model
    /// says — or about to be, a refresh or two from now — so nothing is lost but the motion.
    func cancel() {
        guard isRunning else { return }
        teardown()
    }

    // MARK: - The hand-off

    private func schedule(landingAt time: Double, from now: Double) {
        landing?.cancel()
        deadline?.cancel()
        deadline = nil
        let work = DispatchWorkItem { [weak self] in self?.landed() }
        landing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, time - now), execute: work)
    }

    /// The cards are within a couple of points of their slots. The real windows are almost
    /// always there already — they were written 35 ms in — and then the dissolve starts now;
    /// one that has not said so yet gets `handoffTimeout`.
    private func landed() {
        landing = nil
        hasLanded = true
        guard awaiting.isEmpty else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Log.info("tile snap: \(self.awaiting.count) window(s) never reported their frame,"
                         + " dissolving anyway")
                self.handOff()
                self.awaiting.removeAll()
            }
            deadline = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.handoffTimeout, execute: work)
            return
        }
        handOff()
    }

    private func handOff() {
        deadline?.cancel()
        deadline = nil
        guard dissolving == 0 else { return }
        Log.info("tile snap: dissolving after \(Int((CACurrentMediaTime() - began) * 1000)) ms"
                 + (awaiting.isEmpty ? "" : ", \(awaiting.count) window(s) not heard from"))
        dissolving = stages.count
        for (_, state) in stages {
            state.stage.dissolve(over: dissolveDuration) { [weak self] in
                guard let self else { return }
                self.dissolving -= 1
                if self.dissolving == 0 { self.finish() }
            }
        }
    }

    private func finish() {
        teardown()
        onFinished?()
    }

    private func teardown() {
        landing?.cancel()
        deadline?.cancel()
        landing = nil
        deadline = nil
        for (_, state) in stages { host.release(state.stage, by: self) }
        stages.removeAll()
        motion = nil
        focused = nil
        awaiting.removeAll()
        hasLanded = false
        dissolving = 0
    }

    /// The slide has taken a display: the snap gives it up there, and is over if that was the
    /// last one it had.
    private func evicted(from display: UInt32) {
        stages.removeValue(forKey: display)
        if stages.isEmpty { teardown(); return }
        // Its dissolve, if it had one, will never report: the hide that evicted it saw to that.
        if dissolving > 0 {
            dissolving -= 1
            if dissolving == 0 { finish() }
        }
    }
}
