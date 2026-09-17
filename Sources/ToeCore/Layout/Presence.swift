import Foundation

/// Which of the tiles on screen the window server says are not there — the failsafe behind
/// #147, decided here so the selftest can reach it.
///
/// The tracker learns that a window has left in two ways only: `kAXUIElementDestroyed` or
/// `kAXWindowMiniaturized` on the element, and the application terminating. A window that goes
/// native fullscreen is neither — macOS moves it to a Space of its own and it keeps its tile,
/// which the desktop then shows as a hole — and a `Destroyed` an application never delivers
/// leaves a tile forever. Both are visible to the window server: `CGWindowListCopyWindowInfo`
/// lists every window that exists and says, per window, whether it is on the Space the user is
/// looking at. That is the whole input here, and it costs one call and no Accessibility.
///
/// A tile is judged against that list per display, and only on a display the user is provably
/// looking at the desktop of. Two things say they are not. From a fullscreen Space every desktop
/// tile reads "off screen" while the fullscreen window — a tile itself, until this suspends it
/// — reads on; so a display with an on-screen window covering its usable area is showing a
/// fullscreen Space and is left alone. (Measured: the fullscreen window's bounds are the display
/// less the menu bar, which is the usable area or more. A lone ungapped tile covers it too, and
/// skipping that display costs nothing — one window leaving a tree of one leaves no hole.) And
/// a display with no tile on screen at all — a lock screen, an animation nobody measured — is
/// left alone as well, because the failure that must not happen is every tile on a display
/// leaving the tree at once and coming back in whatever order.
public enum Presence {

    /// What the window server said, reduced to what matters.
    public struct Sample: Equatable {
        /// Every window that exists, on any Space, minimized, hidden or not.
        public var existing: Set<WindowID>
        /// Those on the Space their display is showing. A window parked off-screen by a
        /// workspace switch is *on* screen by this measure — it is on the current Space, just
        /// outside the display — which is why only the visible plan's tiles are ever judged.
        public var onScreen: Set<WindowID>
        /// The bounds of the on-screen windows at an ordinary level — the levels a tile or a
        /// fullscreen window lives at. Separate from `onScreen`, and narrower, because the
        /// Dock keeps a display-sized window on screen at all times at a level of its own,
        /// and counting that would say every display is showing a fullscreen Space.
        public var covering: [WindowID: Box]

        public init(existing: Set<WindowID>, onScreen: Set<WindowID>, covering: [WindowID: Box]) {
            self.existing = existing
            self.onScreen = onScreen
            self.covering = covering
        }

        /// Whether a fullscreen Space is what this display is showing.
        func isCovered(_ monitor: Monitor) -> Bool {
            covering.values.contains { $0.contains(monitor.usable) }
        }
    }

    /// What to do about it.
    public struct Verdict: Equatable {
        /// Tiles the window server does not list at all: closed, and the tracker never heard.
        /// Certain on one sample — a window is not briefly nonexistent.
        public var gone: Set<WindowID> = []
        /// Tiles that exist but are on another Space — fullscreen, dragged to another desktop
        /// in Mission Control, or an application hidden with `prevent_hiding` off. A
        /// candidate until `Watch` has seen it twice: a fullscreen transition takes ~560 ms
        /// and the answer flickers on the way.
        public var away: Set<WindowID> = []
        /// Suspended windows that are on screen again, and want their tile back. A candidate
        /// until `Watch` has seen it twice, for the same reason as `away`, from the other side:
        /// the first look at a window on its way *to* fullscreen finds it on screen and not yet
        /// covering the display, which reads as a return and is not one.
        public var returned: Set<WindowID> = []

        public init(gone: Set<WindowID> = [], away: Set<WindowID> = [], returned: Set<WindowID> = []) {
            self.gone = gone
            self.away = away
            self.returned = returned
        }

        public var isEmpty: Bool { gone.isEmpty && away.isEmpty && returned.isEmpty }
    }

    /// - Parameters:
    ///   - tiles: the visible plan's tiled windows, grouped by the display they are on.
    ///   - monitors: the displays, for their usable areas. A display `tiles` names that is not
    ///     here is not judged for "away" — nothing is known about what it is showing.
    ///   - suspended: the windows that have left the tree and are waiting to come back.
    public static func assess(tiles: [UInt32: Set<WindowID>],
                              monitors: [Monitor],
                              suspended: Set<WindowID>,
                              sample: Sample) -> Verdict {
        var verdict = Verdict()
        let onScreen = sample.onScreen
        for (monitorID, ids) in tiles {
            // Gone is gone whatever the display is showing; the guards below are about "away".
            let gone = ids.subtracting(sample.existing)
            verdict.gone.formUnion(gone)
            let present = ids.subtracting(gone)
            guard let monitor = monitors.first(where: { $0.id == monitorID }),
                  !sample.isCovered(monitor),
                  !present.isDisjoint(with: onScreen)
            else { continue }
            verdict.away.formUnion(present.subtracting(onScreen))
        }
        // A suspended window the window server has lost is simply gone — there is no tile to
        // reap, and nothing to wait for. One that is on screen again wants its tile back — unless
        // what it is on screen *as* is the fullscreen window, which is the same window on the
        // same Space of its own, with the user looking at it: covering a display is not a return.
        verdict.gone.formUnion(suspended.subtracting(sample.existing))
        verdict.returned = suspended.intersection(onScreen).filter { id in
            !monitors.contains { sample.covering[id]?.contains($0.usable) == true }
        }
        return verdict
    }

    /// The two-look rule for `away` and `returned`. `gone` passes straight through; a window
    /// is only confirmed away, or back, once a second look at least `minimumAge` after the
    /// first has said the same — long enough apart to outlast a Space transition. Consecutive
    /// looks are not enough on their own: a stack change is reported three times over 400 ms,
    /// and the second of those is the same transition as the first, not evidence about it.
    public struct Watch: Equatable {
        public let minimumAge: TimeInterval
        /// When each candidate was first seen, by the caller's clock.
        private var pendingAway: [WindowID: TimeInterval] = [:]
        private var pendingReturn: [WindowID: TimeInterval] = [:]

        public init(minimumAge: TimeInterval) {
            self.minimumAge = minimumAge
        }

        /// Whether anything is waiting for its second look — the caller's cue to take one,
        /// `minimumAge` from now.
        public var isPending: Bool { !pendingAway.isEmpty || !pendingReturn.isEmpty }

        /// - Parameter now: any monotonic clock, in seconds. Only differences are read.
        public mutating func confirm(_ verdict: Verdict, now: TimeInterval) -> Verdict {
            var out = verdict
            out.away = Self.settle(&pendingAway, candidates: verdict.away, now: now, age: minimumAge)
            out.returned = Self.settle(&pendingReturn, candidates: verdict.returned, now: now, age: minimumAge)
            return out
        }

        /// Keeps the candidates still being reported, forgets the ones that are not, and
        /// returns — and drops — those that have been reported for long enough.
        private static func settle(_ pending: inout [WindowID: TimeInterval],
                                   candidates: Set<WindowID>,
                                   now: TimeInterval, age: TimeInterval) -> Set<WindowID> {
            var confirmed: Set<WindowID> = []
            var next: [WindowID: TimeInterval] = [:]
            for id in candidates {
                let since = pending[id] ?? now
                // Ten milliseconds of slack: the second look is scheduled `age` after the first
                // and read off a different clock, and a look that is late by nothing should not
                // have to wait for the next one.
                if now - since >= age - 0.01 {
                    confirmed.insert(id)
                } else {
                    next[id] = since
                }
            }
            pending = next
            return confirmed
        }
    }
}
