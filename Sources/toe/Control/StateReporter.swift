import AppKit
import ToeCore

/// The two lookups `StateReporter.report` cannot make for itself, and the bridge from the
/// tracker's windows to the shape it reads.
///
/// The assembly lives in ToeCore, under the selftest; what stays here is exactly the part that
/// needs AppKit — asking a process what it calls itself and a display what it is called — so a
/// change to what `toe query` reports is a change to a function with assertions on it.
extension StateReporter {

    /// `NSRunningApplication.localizedName`, which is what the Dock and Cmd-Tab show. The
    /// fallbacks for a nameless process are the reporter's, not this lookup's.
    static func appName(of pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// Display names keyed by display id, read once per report rather than once per monitor:
    /// `NSScreen.screens` rebuilds its array on every access.
    static func screenNames() -> [UInt32: String] {
        Dictionary(NSScreen.screens.map { ($0.displayID, $0.localizedName) },
                   uniquingKeysWith: { first, _ in first })
    }
}

extension ManagedWindow {
    /// The four facts the report reads, with the `AXUIElement` and the stash bookkeeping left
    /// behind.
    var tracked: TrackedWindow {
        TrackedWindow(id: id, pid: pid, bundleID: bundleID, title: title)
    }
}
