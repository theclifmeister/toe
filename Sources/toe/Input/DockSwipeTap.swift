import CoreGraphics
import Foundation

/// Swallows the Dock's swipe gestures before the window server acts on them.
///
/// toe keeps its own ten workspaces, and a hidden one's windows are parked off-screen rather
/// than on a macOS Space — see `Stash`. A four-finger swipe up opens Mission Control, which puts
/// that stash on display; a sideways swipe changes the Space out from under toe, leaving its
/// model describing windows that are no longer on screen. Both are better prevented than
/// recovered from.
///
/// The two event types in the mask and the fields the callback reads are private and
/// version-sensitive. `CGEvent.tapCreate` itself is public API, so this needs no entitlement, no
/// `dlsym` and no private symbol — but everything here is written to fail open: an event that
/// does not positively identify itself as a dock swipe is passed through untouched. The blast
/// radius of a wrong guess is bounded by the mask, which admits two gesture event types and
/// nothing else — no keystroke, click or scroll can reach this tap even in principle.
final class DockSwipeTap {

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowed = 0
    /// Read once here rather than per event: the hot path does no dictionary lookups.
    private let verbose = ProcessInfo.processInfo.environment["TOE_VERBOSE"] != nil

    var isRunning: Bool { tap != nil }

    deinit { stop() }

    // MARK: - Private constants

    /// `kCGSEventGesture` (29) and `kCGSEventDockControl` (30). `CGEventMaskBit` only covers the
    /// public types, so the mask is built by hand.
    private static let gestureType: UInt32 = 29
    private static let dockControlType: UInt32 = 30
    private static let mask: CGEventMask = (1 << 29) | (1 << 30)

    /// `kIOHIDEventTypeDockSwipe`. Every phase of a swipe — began, changed, ended, cancelled —
    /// answers this, which is what lets the whole gesture be swallowed as a unit without any
    /// per-gesture state: the Dock is never left half-way into an animation.
    private static let dockSwipeHIDType: Int64 = 23

    /// `CGEventField` is a `CF_ENUM(uint32_t)`, so its `init?(rawValue:)` answers nil for every
    /// index Apple has not declared — which is all of these. The enum's layout is its raw value,
    /// so a bit cast is the way in. Resolved once, at type initialisation, never per event.
    private static let hidTypeField = field(110)     // kCGEventGestureHIDType
    private static let swipeMaskField = field(115)   // up 1, down 2, left 4, right 8 — diagnostics
    private static let motionField = field(123)      // 0 none, 1 horizontal, 2 vertical — diagnostics
    private static let phaseField = field(132)       // 1 began, 2 changed, 4 ended, 8 cancelled
    private static let subtypeField = field(55)      // kCGSEventTypeField — diagnostics

    private static func field(_ raw: UInt32) -> CGEventField {
        unsafeBitCast(raw, to: CGEventField.self)
    }

    // MARK: - Lifecycle

    /// Returns false when the tap could not be created, which in practice means the Accessibility
    /// grant is missing: a filtering tap requires it, and `tapCreate` neither prompts nor retries.
    /// Call this only once `AXIsProcessTrusted()` is true.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,       // no root needed
                                           place: .headInsertEventTap,    // ahead of the Dock
                                           options: .defaultTap,          // filtering, not listen-only
                                           eventsOfInterest: Self.mask,
                                           callback: dockSwipeTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.error("dock swipe tap: could not be created — swipes are not being swallowed")
            return false
        }

        // `.commonModes`, not `.defaultMode`: the run loop switches to event-tracking mode while a
        // menu is open or a window is being dragged, and a filtering tap whose callback is not
        // being serviced stalls the input stream until the system times it out.
        let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        source = loopSource
        Log.info("dock swipe tap: active")
        return true
    }

    /// Torn down explicitly rather than left to process death: a filtering tap still registered
    /// against a callback that has gone away is what spins WindowServer.
    func stop() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        source = nil
        swallowed = 0
        Log.info("dock swipe tap: stopped")
    }

    // MARK: - The hot path

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system switches a tap off if its callback is slow, or if the user takes the input
        // stream over. Re-arm and pass the notification on, or the tap is dead for the session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            Log.error("dock swipe tap: re-armed after "
                      + (type == .tapDisabledByTimeout ? "timeout" : "user input"))
            return Unmanaged.passUnretained(event)
        }

        if verbose { dump(type: type, event: event) }

        // Positive identification, and nothing else. Compared on the raw value rather than
        // switched: 29 and 30 are not declared cases of `CGEventType`, and matching an undeclared
        // case is not something to rely on. Anything unrecognised falls through untouched, so a
        // renumbered field degrades to "swipes stop being swallowed", never to "the wrong thing is".
        let raw = type.rawValue
        guard raw == Self.gestureType || raw == Self.dockControlType,
              event.getIntegerValueField(Self.hidTypeField) == Self.dockSwipeHIDType
        else { return Unmanaged.passUnretained(event) }

        if swallowed == 0 { Log.info("dock swipe tap: swallowing dock swipes") }
        swallowed &+= 1
        return nil                      // the event never reaches the Dock
    }

    /// `TOE_VERBOSE=1` only. The bring-up tool for the day a macOS release renumbers a field:
    /// swipe, watch the numbers, compare them with the constants above.
    private func dump(type: CGEventType, event: CGEvent) {
        Log.info("gesture event: type=\(type.rawValue)"
                 + " subtype=\(event.getIntegerValueField(Self.subtypeField))"
                 + " hid=\(event.getIntegerValueField(Self.hidTypeField))"
                 + " swipe=\(event.getIntegerValueField(Self.swipeMaskField))"
                 + " motion=\(event.getIntegerValueField(Self.motionField))"
                 + " phase=\(event.getIntegerValueField(Self.phaseField))")
    }
}

/// A `CGEventTapCallBack` is a C function pointer and captures nothing, so `self` travels through
/// the tap's refcon. Unretained rather than retained: there is no `CFMachPort` context callback to
/// balance a retain, so a missed `stop()` would leak for the life of the process. Safety comes
/// from ownership instead — `Coordinator` holds the only `DockSwipeTap` for the whole process, and
/// `deinit` invalidates the port before the object can be freed.
private func dockSwipeTapCallback(proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent,
                                  refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<DockSwipeTap>.fromOpaque(refcon)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}
