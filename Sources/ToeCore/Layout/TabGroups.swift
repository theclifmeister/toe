import Foundation

/// Which windows are behind a native tab, and which window is in front of each — the
/// bookkeeping for #165, decided here so the selftest can reach it.
///
/// Native window tabs — Terminal, Ghostty, Safari, anything on `NSWindow` tabbing — are real
/// windows. Every tab is an `AXWindow` with `AXStandardWindow` and a settable frame, so
/// `isManageable` accepts each one and each one would get a tile; but the tabs in a group
/// share one frame, so two tiles for two tabs is one window dragged between two places.
/// And the tab that is not selected reads to the window server exactly as a window on
/// another Space does — it exists, and it is not on screen — so `Presence` would suspend it
/// and resume it on every switch, reflowing the tree each time. The rule here is that a tab
/// group is one tile, and the window in front of the group is the one that holds it.
///
/// The app layer tells this which windows have just gone behind a tab: at the moment
/// `kAXMainWindowChanged` fires for the incoming tab, the outgoing one is already absent
/// from the application's `AXWindows` list while the window server still has it (measured
/// on Ghostty, #165). Windows on another Space and minimized windows stay in that list; a
/// tab that has gone behind is the one thing that leaves it. Nothing here reads a tab bar or
/// matches a title — a title is the one thing about a terminal window that changes every
/// second.
public struct TabGroups: Equatable {

    /// Each window that is behind a tab, keyed to the window in front of it — the one that
    /// holds the tile the group shares. A window in front is never a key.
    public private(set) var behind: [WindowID: WindowID] = [:]

    public init() {}

    /// The windows behind a tab, on no workspace at all until they come forward.
    public var hidden: Set<WindowID> { Set(behind.keys) }

    /// The window in front of `id`'s group, when `id` is behind a tab.
    public func front(of id: WindowID) -> WindowID? { behind[id] }

    /// `front` has come forward and is not placed — new, or back from behind a tab — with
    /// `hidden` the windows of the same application that are now behind a tab.
    ///
    /// - Parameter placed: whether a window holds a tile or a float.
    /// - Returns: the window `front` takes over from, or nil when it is a window of its own.
    ///   `front` succeeds the placed window that has just gone behind. When the application
    ///   has two tab groups and both have just hidden a tab there is no telling which group
    ///   `front` belongs to, so the one it was last behind wins, and failing that nobody does:
    ///   `front` is a new window and the tiles it did not take are `Presence`'s to suspend,
    ///   as they were before any of this existed.
    public mutating func cameForward(_ front: WindowID, hidden: Set<WindowID>,
                                     placed: (WindowID) -> Bool) -> WindowID? {
        let wasBehind = behind.removeValue(forKey: front)
        let candidates = hidden.subtracting([front]).filter(placed)
        let predecessor: WindowID?
        if let wasBehind, candidates.contains(wasBehind) {
            predecessor = wasBehind
        } else if candidates.count == 1 {
            predecessor = candidates.first
        } else {
            predecessor = nil
        }
        guard let predecessor else { return nil }
        // Everything that stood behind the predecessor stands behind `front` now, and so does
        // the predecessor. A group's members are only ever known through whoever is in front.
        for (id, f) in behind where f == predecessor { behind[id] = front }
        behind[predecessor] = front
        return predecessor
    }

    /// `id` has gone — closed, or reaped. If windows were behind it, one of them inherits its
    /// place and the rest stand behind that one.
    ///
    /// - Returns: the heir, or nil when nothing was behind `id`. Which tab AppKit will select
    ///   next is its business; when that one comes forward and is not the heir,
    ///   `cameForward` finds the heir hidden and placed and hands the tile on. The lowest id
    ///   is chosen so that the answer is the same whatever order the dictionary happens to be
    ///   in — the choice is provisional either way.
    public mutating func windowGone(_ id: WindowID) -> WindowID? {
        behind.removeValue(forKey: id)
        let members = behind.filter { $0.value == id }.keys.sorted()
        guard let heir = members.first else { return nil }
        for member in members { behind[member] = heir }
        behind.removeValue(forKey: heir)
        return heir
    }
}
