import CoreGraphics
import Foundation
import ToeCore

/// The window server's stacking order, which Accessibility does not expose at all.
///
/// Reads `kCGWindowBounds`, `kCGWindowLayer`, `kCGWindowOwnerPID` and `kCGWindowAlpha`, and
/// nothing else. `kCGWindowName` would need Screen Recording; Accessibility is the one
/// permission toe asks for, so the window list is read for geometry and never for content.
enum WindowStack {

    /// The levels worth considering. A window above `.floating` — a menu, the Dock, a system
    /// alert — already draws over the border correctly, and dropping the border to `.normal`
    /// would not change that, so counting one would strand the border down there for as long
    /// as it stayed on screen. This bound is the same fact as `BorderOverlay.Depth`'s
    /// `.floating`: change one and change the other.
    private static let levels = 0...Int(CGWindowLevelForKey(.floatingWindow))

    /// Ordinary windows stacked above `id`, in Accessibility coordinates.
    ///
    /// Empty when the window is not on screen — a stale id, another Space, a window on its way
    /// out — which reads as "nothing is covering it". That is the right way to fail: the
    /// fallback is the behaviour toe has always had, not a new one.
    static func ordinaryWindowsAbove(_ id: WindowID) -> [Box] {
        let options: CGWindowListOption = [.optionOnScreenAboveWindow, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, id) as? [[String: Any]] else {
            return []
        }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

        return list.compactMap { info in
            // toe's own border panel is above the focused window by construction, so without
            // this the border would demote itself every single time, in every case.
            guard info[kCGWindowOwnerPID as String] as? Int != ownPID else { return nil }
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  levels.contains(layer)
            else { return nil }
            // Apps keep invisible helper windows around; one of those covering the band is not
            // something anyone can see.
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.01 { return nil }
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
