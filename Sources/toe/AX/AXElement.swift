import AppKit
import ApplicationServices
import ToeCore

/// `_AXUIElementGetWindow` is private but stable, and is how every macOS tiler (AeroSpace,
/// yabai) turns an AXUIElement into a CGWindowID. Resolved with dlsym so a missing symbol
/// degrades instead of failing to launch.
private let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(sym, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
}()

extension AXUIElement {

    func value(_ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &out) == .success else { return nil }
        return out
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { value(attribute) as? Bool }

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
        guard let raw = value(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    var size: CGSize? {
        guard let raw = value(kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(raw as! AXValue, .cgSize, &s) else { return nil }
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
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
