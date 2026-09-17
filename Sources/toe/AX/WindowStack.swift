import CoreGraphics
import Foundation
import ToeCore

/// The window server's stacking order, which Accessibility does not expose at all.
///
/// Reads `kCGWindowNumber`, `kCGWindowBounds`, `kCGWindowLayer`, `kCGWindowOwnerPID`,
/// `kCGWindowAlpha` and `kCGWindowIsOnscreen`, and nothing else. `kCGWindowName` would need
/// Screen Recording, which toe asks for only when the workspace slide is switched on
/// (`ScreenSnapshot`), so the window list is read for geometry and never for content.
enum WindowStack {

    /// The levels worth considering. A window above `.floating` — a menu, the Dock, a system
    /// alert — already draws over the border correctly, and dropping the border to `.normal`
    /// would not change that, so counting one would strand the border down there for as long
    /// as it stayed on screen. This bound is the same fact as `BorderOverlay.Depth`'s
    /// `.floating`: change one and change the other.
    private static let levels = 0...Int(CGWindowLevelForKey(.floatingWindow))

    /// The ordinary windows stacked above `id`.
    ///
    /// Empty when the window is not on screen — a stale id, another Space, a window on its way
    /// out — which reads as "nothing is covering it". That is the right way to fail: the
    /// fallback is the behaviour toe has always had, not a new one.
    private static func infoForWindowsAbove(_ id: WindowID) -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenAboveWindow, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, id) as? [[String: Any]] else {
            return []
        }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

        return list.filter { info in
            // toe's own border panel is above the focused window by construction, so without
            // this the border would demote itself every single time, in every case.
            guard info[kCGWindowOwnerPID as String] as? Int != ownPID else { return false }
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  levels.contains(layer)
            else { return false }
            // Apps keep invisible helper windows around; one of those covering the band is not
            // something anyone can see.
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.01 { return false }
            return true
        }
    }

    /// Every window that exists and which of them are on the Space their display is showing —
    /// the input to `Presence.assess`. One call, and it reads `kCGWindowNumber`,
    /// `kCGWindowIsOnscreen`, `kCGWindowBounds` and `kCGWindowLayer` only. The level gates
    /// nothing but the bounds: a tile whose application has lifted it a level for a moment is
    /// still a window that exists and is on screen, but only a window at an ordinary level can
    /// say a display is showing a fullscreen Space — the Dock keeps a display-sized window on
    /// screen at all times at level 20, and it would otherwise say so of every display.
    ///
    /// `kCGWindowIsOnscreen` means "on the current Space", not "inside the display": a window
    /// toe has parked at `stashPoint` reads as on screen, a window on a fullscreen Space reads as
    /// off it, and from a fullscreen Space every desktop window reads as off — measured, and the
    /// reason `Presence` judges a display only when at least one of its tiles is on screen.
    static func presence() -> Presence.Sample? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            // No answer is not "nothing exists": an empty sample would read as every tile on
            // screen having been closed. Nil, and the caller does nothing this time.
            return nil
        }
        var existing: Set<WindowID> = []
        var onScreen: Set<WindowID> = []
        var covering: [WindowID: Box] = [:]
        for info in list {
            guard let id = info[kCGWindowNumber as String] as? WindowID else { continue }
            existing.insert(id)
            guard info[kCGWindowIsOnscreen as String] as? Bool == true else { continue }
            onScreen.insert(id)
            guard let layer = info[kCGWindowLayer as String] as? Int, levels.contains(layer),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            // The same space as `Box`, and no conversion — see `ordinaryWindowsAbove`.
            covering[id] = Box(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
        }
        return Presence.Sample(existing: existing, onScreen: onScreen, covering: covering)
    }

    /// The ids of the windows above `id`. This is how toe knows whether a float it has already
    /// sunk is still down there, so a stack that is right is left alone rather than re-raised.
    static func windowsAbove(_ id: WindowID) -> Set<WindowID> {
        Set(infoForWindowsAbove(id).compactMap { $0[kCGWindowNumber as String] as? WindowID })
    }

    /// The same windows as frames, in Accessibility coordinates.
    static func ordinaryWindowsAbove(_ id: WindowID) -> [Box] {
        infoForWindowsAbove(id).compactMap { info in
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 1, rect.height > 1
            else { return nil }

            // No conversion. `kCGWindowBounds` and `Box` are already the same space: origin at
            // the top-left of the primary display, y growing downward. `Coordinates.toCocoa`
            // sits next door and looks like it belongs here, but it would flip y about the
            // primary display's height — invisible on one display, badly wrong on two.
            return Box(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
        }
    }
}
