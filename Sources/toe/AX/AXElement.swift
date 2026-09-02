import AppKit
import ApplicationServices
import ToeCore

/// `_AXUIElementGetWindow` is private but stable, and is the only way to turn an AXUIElement
/// into a CGWindowID. Resolved with dlsym so a missing symbol degrades instead of failing
/// to launch.
private let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(sym, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
}()

/// How long toe will wait for an application to answer a single Accessibility call.
///
/// Every AX call toe makes is synchronous and on the main thread, and they are not rare:
/// `isManageable` alone makes six cross-process round trips per candidate window, on every
/// window creation and focus change, and `WindowMover.setFrame` five more per tile. The macOS
/// default timeout is measured in seconds, so one unresponsive application — an Electron app
/// mid-startup, a process stopped in a debugger — would stall hotkeys, the menu bar strip and
/// the layout for every other app along with it. Hence the cap.
///
/// A quarter of a second is far more than a healthy app needs to answer, and short enough that
/// a hung one costs a frame rather than a freeze.
private let axMessagingTimeout: Float = 0.25

enum AX {

    /// The application element for `pid`, with toe's messaging timeout applied. Always use
    /// this rather than `AXUIElementCreateApplication`: the timeout is a property of the
    /// element, and setting it on an application element covers every message to that app.
    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        return element
    }

    /// Applies the timeout to every element that does not carry one of its own. The window
    /// elements the observer callbacks hand to toe are what this is for: they arrive from the
    /// AX API rather than from an application element toe created, so nothing else caps them.
    static func setGlobalMessagingTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeout)
    }

    /// Whether the window in front right now is a native-fullscreen one.
    ///
    /// Asked of the frontmost application rather than of anything toe tracks, because the
    /// window that matters here is usually one toe manages nothing for: `isManageable` turns
    /// fullscreen windows away, so a Safari gone fullscreen is invisible to the tracker while
    /// being exactly the window the border must not draw over.
    ///
    /// A fullscreen window owns its own Space, and the border panel is `.canJoinAllSpaces`
    /// with `.fullScreenAuxiliary` — deliberately, so it survives the Space it sits on being
    /// switched away and back — which is also what lets it paint the previous Space's outline
    /// straight across a fullscreen one. This is the question that stops it.
    static var frontmostWindowIsFullscreen: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let element = application(app.processIdentifier)
        guard let focused = element.elementValue(kAXFocusedWindowAttribute) else { return false }
        return focused.isFullscreen
    }
}

extension AXUIElement {

    func value(_ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &out) == .success else { return nil }
        return out
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { value(attribute) as? Bool }

    /// An attribute value, checked against the CoreFoundation type it is supposed to hold.
    ///
    /// Every one of these values crosses a process boundary from an application toe does not
    /// control, and nothing obliges that application to answer `kAXFocusedWindowAttribute`
    /// with a window, or `kAXPositionAttribute` with a point. `as?` cannot do the checking:
    /// AX types are CoreFoundation types, Swift's conditional cast to one is unchecked, and
    /// the compiler rejects it outright as always succeeding. `CFGetTypeID` is the real test,
    /// so the two casts below are reached only once the type is established — which is what
    /// keeps a misbehaving application from taking toe down with it.
    private func checked(_ attribute: String, is typeID: CFTypeID) -> CFTypeRef? {
        guard let raw = value(attribute), CFGetTypeID(raw) == typeID else { return nil }
        return raw
    }

    /// An attribute that is supposed to hold another element.
    func elementValue(_ attribute: String) -> AXUIElement? {
        guard let raw = checked(attribute, is: AXUIElementGetTypeID()) else { return nil }
        // swiftlint:disable:next force_cast
        return (raw as! AXUIElement)
    }

    /// An attribute that is supposed to hold a packed `AXValue` — a point, a size, a range.
    func axValue(_ attribute: String) -> AXValue? {
        guard let raw = checked(attribute, is: AXValueGetTypeID()) else { return nil }
        // swiftlint:disable:next force_cast
        return (raw as! AXValue)
    }

    @discardableResult
    func set(_ attribute: String, _ newValue: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, newValue) == .success
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    var children: [AXUIElement] { value(kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    var windows: [AXUIElement] { value(kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }

    /// The CGWindowID, or nil when the private symbol is unavailable.
    var windowID: CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: CGWindowID = 0
        guard axGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    var position: CGPoint? {
        // AXValueGetValue answers false for an AXValue packing something other than a point,
        // so the pair of checks covers both a wrong CFType and a wrong payload inside it.
        guard let raw = axValue(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(raw, .cgPoint, &point) else { return nil }
        return point
    }

    var size: CGSize? {
        guard let raw = axValue(kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue(raw, .cgSize, &s) else { return nil }
        return s
    }

    /// The window's current frame in Accessibility coordinates.
    var frame: Box? {
        guard let p = position, let s = size else { return nil }
        return Box(x: p.x, y: p.y, w: s.width, h: s.height)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return }
        set(kAXPositionAttribute, v)
    }

    func setSize(_ size: CGSize) {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return }
        set(kAXSizeAttribute, v)
    }

    var isMinimized: Bool { bool(kAXMinimizedAttribute) ?? false }
    var isFullscreen: Bool { bool("AXFullScreen") ?? false }
}

/// AX (top-left origin, y down) ↔ Cocoa (bottom-left origin, y up).
enum Coordinates {
    /// The screen whose origin is (0, 0). All AX coordinates are relative to its top-left.
    static var primaryFrame: CGRect {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame
            ?? NSScreen.main?.frame
            ?? .zero
    }

    static func toCocoa(_ box: Box) -> NSRect {
        NSRect(x: box.x, y: primaryFrame.maxY - box.y - box.h, width: box.w, height: box.h)
    }

    static func toAX(_ rect: NSRect) -> Box {
        Box(x: rect.minX, y: primaryFrame.maxY - rect.maxY, w: rect.width, h: rect.height)
    }

    static func toAX(_ point: NSPoint) -> Point {
        Point(x: point.x, y: primaryFrame.maxY - point.y)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
