import Foundation

/// The arithmetic of the tile snap: where every window's stand-in is at any moment between the
/// layout it left and the layout it is heading for. Here rather than in `TileSnapOverlay` for the
/// reason `WorkspaceSlide` and `BorderGeometry` are where they are — the selftest can reach
/// ToeCore and cannot reach a layer, and the motion is the part that has to be right on every
/// keypress.
///
/// **Why a spring and not a curve.** The prototype ran each card along Hyprland's `easeOutQuint`
/// for a fixed time, and a layout arriving mid-motion — SUPER+equal held down, two quick
/// SUPER+SHIFT+arrows — could only cancel it and start the next from where the real windows had
/// already gone: a run of short jumps. A timing curve has no answer to "carry on from here, at
/// this speed, somewhere else"; a spring is nothing *but* that answer. Its state is a position
/// and a velocity, a new target is a new rest point, and the motion through the change is
/// continuous in both — one glide that bends, which is what UIKit and SwiftUI retarget with for
/// the same reason. The bounce that makes it a spring is also the landing the snap wanted: the
/// card arrives with enough speed to pass its slot by a little and settles back, which reads as
/// a window that clicked into place rather than one that coasted to a stop.
///
/// **The parameters are SwiftUI's**, `Spring(duration:bounce:)`, because they are the two a
/// person can reason about: `duration` is how long the motion takes to look done (the period of
/// the undamped spring, 2π/ω), and `bounce` is how far it overshoots — 0 is critically damped,
/// a glide with no overshoot at all; 0.2 passes a 1000-point move's slot by about 15 points.
/// Stiffness and damping are derived from those and never appear in the config.
///
/// Times are seconds on whatever clock the caller keeps — `CACurrentMediaTime` in the overlay,
/// whole numbers in the selftest. Boxes are any one coordinate space; the four numbers of a box
/// move as four independent springs with the same constants, which, being linear, is the same
/// motion as springing its edges.
public enum TileSnap {

    /// Within this of its slot, in every component and with speed to match, a card is at rest:
    /// the keyframes stop there and the layer's model value — the slot itself — takes over.
    /// Half a point is under what a Retina display can show of a moving edge.
    public static let restDistance = 0.5

    /// Within this, the card is close enough to the real window under it for the panel to start
    /// dissolving: the last of the motion finishes under the fade, where a couple of points of
    /// difference between a card and its window cannot be seen. Waiting for `restDistance`
    /// instead would hold the real windows back for the spring's whole tail, which is the
    /// part of the motion nobody can see.
    public static let landDistance = 2.0

    /// How far in from each side a window with nowhere to come from starts — a window that has
    /// just been created somewhere off the display, say. Its card springs out to full size in its
    /// slot, which with any bounce at all is a small pop rather than a fade.
    public static let appearInset = 0.04

    // MARK: - The spring

    public struct Spring: Equatable, Sendable {
        /// Seconds: the period of the undamped spring, roughly when the motion looks done.
        public var duration: Double
        /// 0 for no overshoot, towards 1 for more. Kept below 1 by the config's bounds.
        public var bounce: Double

        public init(duration: Double, bounce: Double) {
            self.duration = max(duration, 0.01)
            self.bounce = min(max(bounce, 0), 0.95)
        }

        /// Natural angular frequency.
        public var omega: Double { 2 * .pi / duration }
        /// Damping ratio.
        public var zeta: Double { 1 - bounce }

        /// The overshoot of a move from rest, as a fraction of its length: the first peak past
        /// the slot. Zero for a critically damped spring. For the report and the selftest; the
        /// motion does not use it.
        public var overshoot: Double {
            guard zeta < 1 else { return 0 }
            return exp(-.pi * zeta / sqrt(1 - zeta * zeta))
        }

        /// One axis: the displacement from the rest point and the velocity, `t` seconds after it
        /// was at `d0` moving at `v0`. Closed form, so evaluating it at any time costs the same
        /// and a retarget does not accumulate the error a stepped integration would.
        public func state(d0: Double, v0: Double, t: Double) -> (d: Double, v: Double) {
            let w = omega, z = zeta
            guard t > 0 else { return (d0, v0) }
            if z < 1 {
                let wd = w * sqrt(1 - z * z)
                let decay = exp(-z * w * t)
                let b = (v0 + z * w * d0) / wd
                let c = cos(wd * t), s = sin(wd * t)
                let d = decay * (d0 * c + b * s)
                let v = decay * ((b * wd - z * w * d0) * c - (d0 * wd + z * w * b) * s)
                return (d, v)
            }
            // Critically damped.
            let decay = exp(-w * t)
            let b = v0 + w * d0
            let d = decay * (d0 + b * t)
            let v = decay * (b - w * (d0 + b * t))
            return (d, v)
        }

        /// The spring's energy expressed as a distance: the furthest from rest it can ever be
        /// again. `E = v² + ω²d²` only ever falls under damping (dE/dt = −4ζω v²), so once this
        /// is under a threshold the axis stays under it for good — which is what makes it the
        /// test for "at rest" rather than |d| alone, which is zero at every crossing.
        public func reach(d: Double, v: Double) -> Double {
            sqrt(v * v / (omega * omega) + d * d)
        }
    }

    // MARK: - One window

    /// One leg of one window's motion: from `from`, already moving at `velocity`, towards `to`,
    /// starting at `start`. A retarget ends a leg and starts the next from wherever this one
    /// had got to.
    public struct Track: Equatable, Sendable {
        public var from: Box
        public var to: Box
        /// Points per second, per component, in the box's own four numbers.
        public var velocity: Box
        public var start: Double

        public init(from: Box, to: Box, velocity: Box = Box(x: 0, y: 0, w: 0, h: 0), start: Double) {
            self.from = from; self.to = to; self.velocity = velocity; self.start = start
        }

        /// Where the card is at `t`, and how fast it is moving.
        public func state(at t: Double, _ spring: Spring) -> (frame: Box, velocity: Box) {
            let elapsed = t - start
            let f = components(from), g = components(to), v = components(velocity)
            var frame = [Double](repeating: 0, count: 4)
            var speed = [Double](repeating: 0, count: 4)
            for i in 0..<4 {
                let s = spring.state(d0: f[i] - g[i], v0: v[i], t: elapsed)
                frame[i] = g[i] + s.d
                speed[i] = s.v
            }
            return (box(frame), box(speed))
        }

        public func frame(at t: Double, _ spring: Spring) -> Box { state(at: t, spring).frame }

        /// Whether every component's reach is under `distance` at `t` — and so stays under it.
        public func isWithin(_ distance: Double, at t: Double, _ spring: Spring) -> Bool {
            let s = state(at: t, spring)
            let d = components(s.frame), g = components(to), v = components(s.velocity)
            return (0..<4).allSatisfy { spring.reach(d: d[$0] - g[$0], v: v[$0]) < distance }
        }

        /// The first moment the track is within `distance` for good. The reach falls
        /// monotonically, so a bisection finds it; the bracket is doubled from the spring's own
        /// duration until it holds, and capped so a nonsense input cannot spin.
        public func time(within distance: Double, _ spring: Spring) -> Double {
            if isWithin(distance, at: start, spring) { return start }
            var hi = spring.duration
            var guardrail = 0
            while !isWithin(distance, at: start + hi, spring), guardrail < 20 {
                hi *= 2; guardrail += 1
            }
            var lo = 0.0
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if isWithin(distance, at: start + mid, spring) { hi = mid } else { lo = mid }
            }
            return start + hi
        }
    }

    // MARK: - Every window

    /// The snap in progress: a track per window on the panel, all on one spring.
    public struct Motion: Equatable, Sendable {
        public var spring: Spring
        public private(set) var tracks: [WindowID: Track] = [:]

        public init(spring: Spring) { self.spring = spring }

        /// Points every window at the frame `targets` gives it, at `t`.
        ///
        /// - A window with a track keeps it when its target has not changed — a retarget for
        ///   one tile must not restart the others' motion — and otherwise starts a new leg from
        ///   exactly where and how fast it is moving now. That is the retarget, and it is why a
        ///   held SUPER+equal reads as one glide.
        /// - A window new to the motion starts from `origins` — where it was before this layout
        ///   — at rest. With no origin it starts `appearInset` smaller than its slot, centred.
        /// - A window no longer in `targets` is dropped: closed, sent to another workspace, or
        ///   gone from every display.
        ///
        /// Answers the windows whose track changed, which are the ones whose layers want new
        /// keyframes.
        @discardableResult
        public mutating func retarget(to targets: [WindowID: Box], from origins: [WindowID: Box],
                                      at t: Double) -> Set<WindowID> {
            var changed: Set<WindowID> = []
            for id in tracks.keys where targets[id] == nil {
                tracks.removeValue(forKey: id)
            }
            for (id, to) in targets {
                if let track = tracks[id] {
                    guard track.to != to else { continue }
                    let now = track.state(at: t, spring)
                    tracks[id] = Track(from: now.frame, to: to, velocity: now.velocity, start: t)
                } else {
                    let from = origins[id] ?? TileSnap.appearing(to)
                    tracks[id] = Track(from: from, to: to, start: t)
                }
                changed.insert(id)
            }
            return changed
        }

        public func frame(of id: WindowID, at t: Double) -> Box? {
            tracks[id]?.frame(at: t, spring)
        }

        /// When every card is within `landDistance` of its slot: the moment the panel may begin
        /// to dissolve. `t` when nothing is moving.
        public func landing(after t: Double) -> Double {
            tracks.values.map { $0.time(within: TileSnap.landDistance, spring) }.reduce(t, max)
        }

        /// When the last card is at rest.
        public func rest(after t: Double) -> Double {
            tracks.values.map { $0.time(within: TileSnap.restDistance, spring) }.reduce(t, max)
        }

        /// The frames of `id` from `t` every `step` seconds until it is at rest, the last one
        /// its slot exactly: the keyframes the overlay hands the render server, so that the
        /// motion runs off the main thread and an Accessibility write that blocks it for a
        /// quarter of a second cannot make a card stutter. Linear between samples; at 120 a
        /// second that is finer than any display shows. A single frame means at rest already.
        public func samples(of id: WindowID, from t: Double, step: Double = 1.0 / 120) -> [Box] {
            guard let track = tracks[id] else { return [] }
            let end = track.time(within: TileSnap.restDistance, spring)
            guard end > t else { return [track.to] }
            var out: [Box] = []
            var time = t
            while time < end {
                out.append(track.frame(at: time, spring))
                time += step
            }
            out.append(track.to)
            return out
        }
    }

    /// Where a window with nowhere to come from starts: its slot, a little smaller.
    public static func appearing(_ to: Box) -> Box {
        let dx = to.w * appearInset, dy = to.h * appearInset
        return Box(x: to.x + dx, y: to.y + dy, w: to.w - 2 * dx, h: to.h - 2 * dy)
    }

    // MARK: - Stacking

    /// The windows in `ids`, back to front, by the window server's own order — `frontToBack` is
    /// `CGWindowListCopyWindowInfo`'s, which lists the frontmost first. A window the list does
    /// not have (one created a moment ago, or a read that failed) goes on top, in id order so a
    /// dictionary's ordering cannot leak in: a new window is the frontmost thing on screen,
    /// almost always, and the card that is wrong for a moment is better on top than buried.
    public static func drawOrder(_ ids: some Sequence<WindowID>, frontToBack: [WindowID]) -> [WindowID] {
        var rank: [WindowID: Int] = [:]
        for (index, id) in frontToBack.enumerated() where rank[id] == nil { rank[id] = index }
        return ids.sorted { a, b in
            switch (rank[a], rank[b]) {
            case let (x?, y?): return x > y
            case (nil, nil): return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
}

private func components(_ b: Box) -> [Double] { [b.x, b.y, b.w, b.h] }
private func box(_ c: [Double]) -> Box { Box(x: c[0], y: c[1], w: c[2], h: c[3]) }
