import CoreGraphics
import Foundation
import ToeCore

/// The corner radius of *one particular window*, straight from the window server.
///
/// macOS 26 rounds windows itself, and it does not round them all the same: Safari's windows
/// come back at 26 pt, Ghostty's at 16. A single system-wide number — which is all
/// `SystemCornerRadius` can offer — is therefore wrong for most windows, by up to 8 pt in the
/// cases measured here, and that is what makes the band overshoot one app's corner while
/// cutting the next one's.
///
/// `SLSWindowIteratorGetCornerRadii` is how JankyBorders answers the same question. It is
/// undocumented, and new in macOS 26 — nothing below that has it, and the lookup simply fails
/// there, which is the right outcome: `SystemCornerRadius` is still the best available answer
/// on those releases.
///
/// Note what this buys and what it does not. It is the *radius*, not the curve: JankyBorders
/// takes the same number and draws a circular arc with it, which is not the shape a macOS
/// corner is. toe keeps drawing through `CALayer.cornerCurve = .continuous`, so with the right
/// radius in hand the band follows both.
enum WindowCornerRadius {

    /// The window's own corner radius, or nil to fall back on `SystemCornerRadius.points`.
    ///
    /// Nil covers three cases that all want the same answer: the symbols are missing (below
    /// macOS 26), the query came back empty, or the window reported 0.
    ///
    /// **Zero is "unknown", not "square".** toe's own borderless panel reports 0 and really is
    /// square — but Electron windows report 0 while rendering rounded, and nothing in the reply
    /// tells the two apart. Falling back keeps those looking exactly as they do today; treating
    /// 0 as square would put a sharp ring around Slack's rounded corners. A window that is
    /// genuinely square is served by `radius = 0` in the config.
    static func points(for id: WindowID) -> CGFloat? {
        guard let mainConnectionID, let queryWindows, let copyWindows,
              let advance, let getCornerRadii
        else { return nil }

        // A one-element array asks about this window alone, rather than walking every window
        // on the system to find it.
        var window = id
        guard let number = CFNumberCreate(nil, .sInt32Type, &window) else { return nil }
        let ids = [number] as CFArray

        // Despite the names, all three of these come back +1. Retained, not unretained: an
        // unretained take here would over-release, and no take at all would leak one query,
        // one iterator and one array on every focus change.
        guard let query = queryWindows(mainConnectionID(), ids, 1)?.takeRetainedValue(),
              let iterator = copyWindows(query)?.takeRetainedValue(),
              advance(iterator)
        else { return nil }

        guard let radii = getCornerRadii(iterator)?.takeRetainedValue() as? [Int32],
              let first = radii.first, first > 0
        else { return nil }

        // One radius for four corners. The reply carries all four, and every window measured
        // has them equal; CALayer has a single `cornerRadius` anyway, so an asymmetric window
        // would need a hand-built path and would lose the system rasteriser that makes these
        // corners the right shape to begin with.
        return CGFloat(first)
    }

    /// Whether the window server can be asked at all, for the line toe logs at startup.
    static var isAvailable: Bool {
        mainConnectionID != nil && queryWindows != nil && copyWindows != nil
            && advance != nil && getCornerRadii != nil
    }
}

// MARK: - SkyLight

/// PRIVATE API. Resolved with dlsym on `RTLD_NEXT`, the same way `_AXUIElementGetWindow` and
/// `CGSSetSymbolicHotKeyEnabled` are, so a missing symbol degrades instead of failing to launch.
///
/// `RTLD_NEXT` rather than a `dlopen` of SkyLight's path on purpose: AppKit has already loaded
/// the framework, so the lookup resolves inside a library that is in the process anyway — which
/// is what lets library validation stay on. See `Resources/toe.entitlements`.
private func skyLight<T>(_ name: String, as type: T.Type) -> T? {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
    return unsafeBitCast(sym, to: type)
}

private let mainConnectionID: (@convention(c) () -> Int32)? =
    skyLight("SLSMainConnectionID", as: (@convention(c) () -> Int32).self)

private let queryWindows: (@convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?)? =
    skyLight("SLSWindowQueryWindows",
             as: (@convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?).self)

private let copyWindows: (@convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?)? =
    skyLight("SLSWindowQueryResultCopyWindows",
             as: (@convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?).self)

private let advance: (@convention(c) (CFTypeRef) -> Bool)? =
    skyLight("SLSWindowIteratorAdvance", as: (@convention(c) (CFTypeRef) -> Bool).self)

/// macOS 26 and later only.
private let getCornerRadii: (@convention(c) (CFTypeRef) -> Unmanaged<CFArray>?)? =
    skyLight("SLSWindowIteratorGetCornerRadii",
             as: (@convention(c) (CFTypeRef) -> Unmanaged<CFArray>?).self)
