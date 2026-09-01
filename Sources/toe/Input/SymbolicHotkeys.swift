import CoreGraphics
import Foundation

/// `CGSSetSymbolicHotKeyEnabled` is private, but it is how System Settings' own Mission Control
/// pane turns these shortcuts on and off, and it is re-exported from CoreGraphics on every macOS
/// toe supports. Resolved with dlsym so a missing symbol degrades instead of failing to launch,
/// the same way `_AXUIElementGetWindow` is.
private let setSymbolicHotKeyEnabled: (@convention(c) (Int32, Bool) -> Int32)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
        return nil
    }
    return unsafeBitCast(sym, to: (@convention(c) (Int32, Bool) -> Int32).self)
}()

private let isSymbolicHotKeyEnabled: (@convention(c) (Int32) -> Bool)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsSymbolicHotKeyEnabled") else {
        return nil
    }
    return unsafeBitCast(sym, to: (@convention(c) (Int32) -> Bool).self)
}()

/// Mission Control's keyboard shortcut, switched off for as long as toe runs.
///
/// The swipe is only one way in: `Ctrl`+`↑` opens the same view, and it puts the same off-screen
/// stash on display. `DockSwipeTap` cannot help here — a symbolic hotkey is resolved inside the
/// window server, well before any event tap sees a key.
///
/// Unlike the tap, **this state outlives the process**. The window server keeps it, so a toe that
/// exits without restoring leaves the user's `Ctrl`+`↑` dead with nothing to explain why. Every
/// change is therefore journalled to disk *before* it is made, and a journal found at startup is
/// replayed in reverse — which is what repairs a crash, a force-quit or a logout.
enum SymbolicHotkeys {

    /// Mission Control (`Ctrl`+`↑`) and App Exposé (`Ctrl`+`↓`), each with its slow-motion twin
    /// (`+Shift`) — the keyboard routes into the two views the vertical dock swipe opens, taken
    /// and given back together because they are the same two views.
    ///
    /// Deliberately not here: the Spaces keys (79/81), because `Ctrl`+`←`/`→` is the documented
    /// way out of a fullscreen app now that swiping is not; and Show Desktop (36/37), whose
    /// gesture is a thumb-and-three-finger spread rather than a dock swipe, so leaving the key
    /// alone matches leaving the gesture alone.
    static let expose: [Int32] = [32, 34, 33, 35]

    private static let journalURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/symbolic-hotkeys")

    private static var disabled: [Int32] = []

    // MARK: - Applying

    /// Turns the keys off, remembering which were on so only those are given back. Idempotent.
    static func disable(_ keys: [Int32]) {
        guard let set = setSymbolicHotKeyEnabled, let isEnabled = isSymbolicHotKeyEnabled else {
            Log.error("symbolic hotkeys: CGS symbols unavailable — Mission Control's shortcut is not disabled")
            return
        }
        let toDisable = keys.filter { !disabled.contains($0) && isEnabled($0) }
        guard !toDisable.isEmpty else { return }

        // Journalled before the change, not after: a crash between the two must leave a record
        // that says too much, never one that says too little.
        disabled += toDisable
        writeJournal()
        for key in toDisable { _ = set(key, false) }
        Log.info("symbolic hotkeys: disabled \(toDisable.map(String.init).joined(separator: ", "))")
    }

    /// Gives back exactly what `disable` took, and clears the journal. Safe to call twice.
    static func restoreAll() {
        guard !disabled.isEmpty else {
            clearJournal()
            return
        }
        if let set = setSymbolicHotKeyEnabled {
            for key in disabled { _ = set(key, true) }
            Log.info("symbolic hotkeys: restored \(disabled.map(String.init).joined(separator: ", "))")
        }
        disabled.removeAll()
        clearJournal()
    }

    /// Replays a journal left behind by a toe that did not get to restore — a crash, a `kill -9`,
    /// a logout. Call once at startup, before `disable`.
    static func repairAfterUncleanExit() {
        guard let text = try? String(contentsOf: journalURL, encoding: .utf8) else { return }
        let keys = text.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
        if let set = setSymbolicHotKeyEnabled, !keys.isEmpty {
            for key in keys { _ = set(key, true) }
            Log.info("symbolic hotkeys: repaired \(keys.map(String.init).joined(separator: ", ")) after an unclean exit")
        }
        clearJournal()
    }

    // MARK: - The journal

    private static func writeJournal() {
        let text = disabled.map(String.init).joined(separator: "\n")
        try? FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? text.write(to: journalURL, atomically: true, encoding: .utf8)
    }

    private static func clearJournal() {
        try? FileManager.default.removeItem(at: journalURL)
    }
}
