import Foundation

/// The bar following the menu bar it covers: gone where the menu bar has gone, back where it
/// comes back. Two ways the menu bar goes, and they are kept apart because they last for
/// different lengths of time and cost the tiles differently.
///
/// - **An application puts it away** — a game, a borderless "fullscreen" that is not a Space of
///   its own, a slideshow. It does that with `NSApplication.presentationOptions`, and the
///   options in force are the active application's, which every process can read and observe
///   as `currentSystemPresentationOptions` with no permission at all (measured for T8: another
///   process's `[.hideDock, .hideMenuBar]` arrives as 10 by KVO within the frame,
///   `[.autoHideDock, .autoHideMenuBar]` as 5, and both go back to 0 when it leaves). This is
///   `MenuBarHiding`. Native fullscreen is *not* this — a window on a fullscreen Space reads 0
///   from outside — and keeps its own route through `AX.frontmostFullscreenFrame`.
/// - **The user has macOS hide it** — *Automatically hide and show the menu bar*. That is a
///   setting rather than a moment, so the bar becomes what the menu bar is under it: off the
///   screen until the pointer reaches the top edge, and the tiles get the strip. This is
///   `BarReveal`.
public enum MenuBarHiding {

    /// `NSApplication.PresentationOptions` bits that take the menu bar off the screen:
    /// `.autoHideMenuBar` (1 << 2), `.hideMenuBar` (1 << 3) and `.fullScreen` (1 << 10), which
    /// AppKit only allows alongside one of the other two. Spelled as raw bits because ToeCore
    /// has no AppKit.
    public static let menuBarBits: UInt = (1 << 2) | (1 << 3) | (1 << 10)

    /// Whether the active application's presentation options have put the menu bar away.
    public static func hidesMenuBar(presentationOptions: UInt) -> Bool {
        presentationOptions & menuBarBits != 0
    }

    /// The smallest window, on either side, taken for the one the application is showing.
    /// A game's window is the display; a tool palette or a 1-point helper window the same
    /// application keeps in front is not where it is being played.
    public static let minimumSide: Double = 100

    /// Which of `displays` the hiding is about: the one holding most of the application's
    /// frontmost window of a real size, from `windows` front to back — or nil when there is no
    /// such window, which the caller reads as every display.
    ///
    /// Scoped to a display for the reason the border and the fullscreen rule are: under
    /// *Displays have separate Spaces* a game on one display is no reason for the bar on the
    /// other to go. "Most of" rather than "overlaps", because a window dragged half across
    /// the boundary is on one display as far as anyone looking at it is concerned.
    public static func display(of windows: [Box], among displays: [Box]) -> Int? {
        guard let window = windows.first(where: { $0.w >= minimumSide && $0.h >= minimumSide })
        else { return nil }
        var best: (index: Int, area: Double)?
        for (index, display) in displays.enumerated() {
            let overlap = window.intersection(display)
            let area = overlap.w * overlap.h
            if area > 0, area > best?.area ?? 0 { best = (index, area) }
        }
        return best?.index
    }
}

/// The bar under macOS's own *Automatically hide and show the menu bar*: off the screen until
/// the pointer reaches the top edge of the display, then over the menu bar as ever until it
/// has been gone from the strip for `MenuBarPeek.linger` with nothing holding it.
///
/// The reveal is at once, where the peek waits a dwell: the peek is the bar stepping *out of*
/// the way, and a flick past the edge should not do that, but a reveal is what the edge is for
/// under auto-hide — the menu bar comes in just as fast. "Held" is whatever the bar is still
/// in use for while the pointer is off it: a panel hanging from it, or a peek, whose own end
/// says when the menu bar is done with.
///
/// Pure, like `MenuBarPeek`, and fed the same samples by the same 50 ms timer — which runs
/// only while the bar is revealed or the pointer is on the edge, so nothing ticks the rest of
/// the time.
public struct BarReveal: Equatable, Sendable {

    public private(set) var isRevealed = false
    /// When the pointer left the strip with nothing holding the bar; nil while it has not.
    private var since: Double?

    public init() {}

    /// One sample. Returns whether `isRevealed` changed.
    @discardableResult
    public mutating func sample(_ pointer: MenuBarPeek.Pointer, held: Bool, at now: Double) -> Bool {
        guard isRevealed else {
            guard pointer != .away else { return false }
            isRevealed = true
            since = nil
            return true
        }
        guard pointer == .away, !held else {
            since = nil
            return false
        }
        let start = since ?? now
        since = start
        guard now - start >= MenuBarPeek.linger else { return false }
        isRevealed = false
        since = nil
        return true
    }

    /// Back to hidden, with nothing pending.
    public mutating func reset() {
        isRevealed = false
        since = nil
    }
}
