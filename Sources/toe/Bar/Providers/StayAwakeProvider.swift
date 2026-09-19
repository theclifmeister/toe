import Foundation
import IOKit.pwr_mgt
import notify
import ToeCore

/// Whether something is holding the machine awake — Omarchy's StayAwake indicator, read from
/// IOKit's power assertions rather than the shell's idle inhibitor.
///
/// Active when toe's own assertion is held, or when a `caffeinate` is: the two ways a person
/// asks for this on a Mac. Not when *anything* holds a `PreventUserIdle*` assertion — a video
/// in Safari and a call in FaceTime hold one too, and an indicator that lit up for every video
/// would be saying "something is playing", which is not what the coffee cup means upstream.
///
/// The event is Darwin notify's `kIOPMAssertionsAnyChangedNotifyString`, which fires on every
/// assertion created, released or timed out anywhere in the system. No polling.
///
/// The click toggles toe's own assertion — `IOPMAssertionCreateWithName`, the call `caffeinate
/// -d` makes — and only that: a `caffeinate` somebody typed is theirs to end.
final class StayAwakeProvider: BarProvider {

    private(set) var active = false
    var onChange: (() -> Void)?

    private var token: Int32 = -1
    private var assertion: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    private static let types: Set<String> = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
        kIOPMAssertionTypePreventUserIdleSystemSleep as String,
        // The older spellings `caffeinate -i` and `-d` still register under.
        "NoIdleSleepAssertion", "NoDisplaySleepAssertion",
    ]

    func start() {
        guard token < 0 else { return }
        // `kIOPMAssertionsAnyChangedNotifyString` in IOPMLib.h, which Swift does not import as
        // a string macro.
        let name = "com.apple.system.powermanagement.assertions.anychange"
        let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
            self?.read()
        }
        if status != NOTIFY_STATUS_OK { Log.error("stay awake: could not watch power assertions (\(status))") }
        read()
    }

    func stop() {
        if token >= 0 { notify_cancel(token) }
        token = -1
        release()
        active = false
    }

    /// The indicator pressed: hold the display awake, or let it go.
    func toggle() {
        if assertion != kIOPMNullAssertionID {
            release()
        } else {
            var id = IOPMAssertionID(kIOPMNullAssertionID)
            let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "toe: stay awake" as CFString, &id)
            guard status == kIOReturnSuccess else {
                Log.error("stay awake: could not hold the display awake (\(status))")
                return
            }
            assertion = id
            Log.info("stay awake: on")
        }
        read()
    }

    private func release() {
        guard assertion != kIOPMNullAssertionID else { return }
        IOPMAssertionRelease(assertion)
        assertion = IOPMAssertionID(kIOPMNullAssertionID)
        Log.info("stay awake: off")
    }

    // MARK: - Reading

    private func read() {
        let before = active
        active = assertion != kIOPMNullAssertionID || Self.caffeinateIsRunning()
        if active != before { onChange?() }
    }

    /// Whether a `caffeinate` holds an idle assertion. `IOPMCopyAssertionsByProcess` is keyed by
    /// pid, and the process behind a pid is asked of libproc — `caffeinate` is a command-line
    /// tool with no `NSRunningApplication` to its name.
    private static func caffeinateIsRunning() -> Bool {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let byProcess = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return false }
        for (pid, assertions) in byProcess {
            guard assertions.contains(where: { types.contains($0[kIOPMAssertionTypeKey as String] as? String ?? "") })
            else { continue }
            // `PROC_PIDPATHINFO_MAXSIZE`, 4 × MAXPATHLEN, which Swift does not import.
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid.int32Value, &buffer, UInt32(buffer.count)) > 0 else { continue }
            if String(cString: buffer).hasSuffix("/caffeinate") { return true }
        }
        return false
    }
}
