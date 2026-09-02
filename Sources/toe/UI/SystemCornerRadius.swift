import AppKit
import ObjectiveC

/// The corner radius macOS rounds a window to, system-wide. No public API reports it, and on
/// macOS 26 no private one does either, so this is part measurement, part lookup.
///
/// This is the *fallback*, not the answer. macOS 26 gives every window its own radius, and
/// `WindowCornerRadius` asks the window server for the one that belongs to the window being
/// outlined; this value is what the border falls back on when that query has nothing to say —
/// below macOS 26, where the per-window symbols do not exist, and for windows that report 0.
///
/// On macOS 26 the window server rounds every window itself, and AppKit's own accessors have
/// not followed: `NSWindow._cornerRadius`, `_effectiveCornerRadius`, `NSThemeFrame._cornerRadius`
/// and `_getCachedWindowCornerRadius` all still answer 16, while windows actually render at 24.
/// Fitting a rendered CALayer silhouette against a screenshot of a real window puts the value at
/// 24.0 pt (rms 0.24 px; 16 pt is off by 2.99 px), so 26 and later use the measured constant.
///
/// Earlier releases drew the rounding in AppKit, where the private accessor did match, so those
/// keep asking. That path is guarded at every step and falls back rather than crashing.
enum SystemCornerRadius {

    /// macOS 26 and later. Measured, not reported — see the note above.
    static let tahoe: CGFloat = 24

    /// macOS 11...15, if the private accessor is gone.
    static let legacy: CGFloat = 10

    /// Resolved once, lazily. First access must be on the main thread — `BorderOverlay.init()`
    /// forces it there.
    static let points: CGFloat = resolve()

    /// Where the value came from, for the log line.
    private(set) static var source = "unknown"

    private static func resolve() -> CGFloat {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            source = "measured constant for macOS 26+"
            return tahoe
        }
        if let probed = probe() {
            source = "NSThemeFrame"
            return probed
        }
        source = "fallback"
        return legacy
    }

    /// Reads the radius off a throwaway window that is created and closed without ever being
    /// shown. PRIVATE API, and undocumented: every step is guarded, and a miss returns nil.
    private static func probe() -> CGFloat? {
        // A borderless window gets a different frame view with no rounding, so the style mask
        // has to be a normal titled one. `defer: false` forces the backing store — and with it
        // the theme frame — to exist right away.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        // The content view is created on demand; its superview is the NSThemeFrame.
        guard let frame = window.contentView?.superview, let cls = object_getClass(frame) else {
            return nil
        }

        for name in ["roundedCornerRadius", "_cornerRadius"] {
            let selector = NSSelectorFromString(name)
            // `responds(to:)` alone is not enough: it also answers yes for a forwarded selector
            // that has no method to look up.
            guard frame.responds(to: selector),
                  let method = class_getInstanceMethod(cls, selector)
            else { continue }

            // Not `perform(_:)` — that reads the return value as an object pointer, but a
            // CGFloat comes back in a floating-point register, so the result would be garbage.
            typealias Getter = @convention(c) (AnyObject, Selector) -> CGFloat
            let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            let value = getter(frame, selector)

            // Anything outside this band is a selector collision, not a radius.
            if value.isFinite, value > 0, value <= 60 { return value }
        }
        return nil
    }
}
