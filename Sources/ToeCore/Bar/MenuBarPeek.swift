import Foundation

/// The bar stepping aside for the menu bar under it: hold the pointer at the top edge of a
/// display and that display's bar goes, showing the menu bar it was covering; move off the
/// strip and it comes back.
///
/// The bar covers the menu bar rather than hiding it (see `BarPanel`), which leaves an
/// application's own menus — File, Edit, the lot — with no way to be reached by mouse but
/// `bar hide`. sketchybar's users answer this with the system's auto-hide: the menu bar slides
/// down over the bar on every trip to the top edge. toe tried that first and took it out — the
/// slide-in on every brush of the edge was the complaint, and `NSScreen` never learns of a hide
/// made by its own process. This is the same affordance without the system state: the gesture
/// is the one auto-hide uses, the pointer pinned against the top edge, but held for `dwell`
/// before anything happens, which is what the community's helpers around sketchybar exist to
/// add. A pointer flung to the edge on its way to a widget or a tab does not trip it.
///
/// Pure so the selftest can walk it: the caller feeds samples — where the pointer is with
/// respect to the strip, whether a menu is open, the time — and reads `isPeeking`. The times
/// are the caller's clock in seconds; nothing here looks at a wall clock.
public struct MenuBarPeek: Equatable, Sendable {

    /// How long the pointer rests against the edge before the bar steps aside. Long enough
    /// that a flick to the top does not count, short enough that reaching for a menu is not
    /// a wait: a menu bar under an auto-hide is on screen in about this long.
    public static let dwell: Double = 0.3
    /// How long the pointer is off the strip, with no menu open, before the bar comes back.
    /// The gap covers the trip from a closed menu back down into the window, and a pointer
    /// that overshoots the strip and returns.
    public static let linger: Double = 0.4
    /// How far from the top, in points, still counts as the edge. Two: the pointer stops at 0
    /// against a display's edge, and one more for a pointer that is resting rather than
    /// pressed.
    public static let edge: Double = 2

    /// Where the pointer is, as far as the peek cares.
    public enum Pointer: Equatable, Sendable {
        /// Against the top edge of the strip.
        case edge
        /// On the strip, but not at its edge — over a widget, or the menu bar during a peek.
        case strip
        /// Anywhere else: below the strip, or on another display.
        case away
    }

    public private(set) var isPeeking = false
    /// When the pointer began the condition that would end the current state — resting on
    /// the edge while the bar shows, or away from the strip while it peeks. Nil while the
    /// condition does not hold.
    private var since: Double?

    public init() {}

    /// Classifies a pointer `y` points below the top of a display, or nil for one not over
    /// the strip's width on that display at all, against a strip `height` tall.
    public static func pointer(y: Double?, height: Double) -> Pointer {
        guard let y, y < height else { return .away }
        return y <= edge ? .edge : .strip
    }

    /// One sample. `menuOpen` is whether an application's menu is dropped down — the pointer
    /// leaves the strip to use one, and the bar coming back over the menu bar while its menu
    /// is open would be the bar closing a menu the user is reading. Returns whether
    /// `isPeeking` changed, so the caller knows when to show or hide.
    @discardableResult
    public mutating func sample(_ pointer: Pointer, menuOpen: Bool, at now: Double) -> Bool {
        let pending = isPeeking ? (pointer == .away && !menuOpen) : pointer == .edge
        guard pending else {
            since = nil
            return false
        }
        let start = since ?? now
        since = start
        guard now - start >= (isPeeking ? Self.linger : Self.dwell) else { return false }
        isPeeking.toggle()
        since = nil
        return true
    }

    /// Back to the bar showing, with nothing pending — for when the bar goes away for its
    /// own reasons (`bar hide`, a fullscreen window) in the middle of a peek.
    public mutating func reset() {
        isPeeking = false
        since = nil
    }
}
