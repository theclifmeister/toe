import AppKit
import CoreFoundation
import ToeCore

/// macOS's "Automatically hide and show the menu bar", switched on for as long as toe's bar is.
///
/// The bar goes where the menu bar is, and the two cannot share the strip: `NSScreen.visibleFrame`
/// stops short of a showing menu bar, so the tiles would start under the bar *and* under the
/// menu bar, and the bar itself would be drawn behind the menu bar's own level. Hiding the menu
/// bar hands the strip over. It still slides in when the pointer reaches the top edge, over the
/// bar, which is how an application's menus are reached — the arrangement every sketchybar
/// setup lives with.
///
/// The preference is `_HIHideMenuBar` in the global domain — the key System Settings › Control
/// Center › "Automatically hide and show the menu bar: Always" writes — and the window server
/// re-reads it on `AppleInterfaceMenuBarHidingChangedNotification`. Measured for #171: the write
/// plus the notification is enough. The menu bar slides away within a second, a fresh process
/// reads the new `visibleFrame`, and running applications keep their windows and need no
/// relaunch. Unset means showing — a visible menu bar is the macOS default — so an absent key
/// is a value to put back, not a value to ignore, exactly as `WallpaperClick` treats its own.
///
/// Like a symbolic hotkey, **this state outlives the process**, so it is handled the same way:
/// journalled to disk *before* the change, and a journal found at startup is replayed, which is
/// what repairs a crash, a force-quit or a logout. `make reset-perms` does not undo this — the
/// journal replay at the next launch does, and so does switching the bar off.
enum MenuBarAutoHide {

    private static let key = "_HIHideMenuBar" as CFString
    private static let changed = Notification.Name("AppleInterfaceMenuBarHidingChangedNotification")

    /// What the preference was before toe touched it, and so what `restore` owes the user back.
    /// `absent` is not the same as `off`: writing `false` where there was no key at all would
    /// leave the user's settings holding a value they never set. There is no `on`, because
    /// `enable` returns early when the menu bar already hides itself — there is then nothing to
    /// take and nothing to give back.
    private enum Previous: String {
        case off
        case absent
    }

    /// The one value, written bare.
    private static let journal = Journal<Previous>(
        name: "menubar-autohide",
        serialise: JournalFormat.serialise(word:),
        parse: { JournalFormat.parseWord($0) })

    private static var previous: Previous?

    /// Whether the menu bar is set to hide right now — by toe or by the user — read from the
    /// preference itself rather than from `NSScreen`, which is the point: `NSScreen.visibleFrame`
    /// goes on reserving the menu bar's strip after this process has hidden it (measured for
    /// #171: the screen-parameters change that an external flip produces never arrives for a
    /// flip made from inside the process, and the frame stays stale for the rest of the run),
    /// so the layout asks the preference and puts the strip back itself. See
    /// `Coordinator.refreshMonitors`.
    static var isHidden: Bool {
        (CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? NSNumber)?.boolValue ?? false
    }

    // MARK: - Applying

    /// Hides the menu bar, remembering what was there. Idempotent, and a no-op when the user
    /// hides it themselves already.
    static func enable() {
        guard previous == nil else { return }
        let current = (CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? NSNumber)?.boolValue
        guard !(current ?? false) else { return }
        // `CFPreferencesCopyAppValue` answers from the in-process cache, which the write below
        // updates, so `isHidden` is right from the next line on.

        // Journalled before the change, not after: a crash between the two must leave a record
        // that says too much, never one that says too little. And no record, no change — see
        // `Journal`: a menu bar still showing costs the bar its strip, a menu bar hiding itself
        // with nothing to say so outlives toe.
        let was: Previous = current == nil ? .absent : .off
        guard journal.write(was) else {
            Log.error("menu bar: no journal, so it is left showing")
            return
        }
        previous = was
        write(true)
        // No relayout is asked for here, and none would come: `NSScreen` does not learn of a
        // hide made by its own process — see `isHidden` — which is why `refreshMonitors` reads
        // the preference rather than waiting for `screensChanged`.
        Log.info("menu bar: set to hide")
    }

    /// Gives back exactly what `enable` took, and clears the journal. Safe to call twice.
    static func restore() {
        guard let previous else {
            journal.clear()
            return
        }
        put(back: previous)
        Self.previous = nil
        journal.clear()
        Log.info("menu bar: restored")
    }

    /// Replays a journal left behind by a toe that did not get to restore — a crash, a `kill -9`,
    /// a logout. Call once at startup, before `enable`.
    static func repairAfterUncleanExit() {
        journal.replay { was in
            put(back: was)
            Log.info("menu bar: repaired after an unclean exit")
        }
    }

    // MARK: - The preference

    private static func put(back previous: Previous) {
        switch previous {
        case .off: write(false)
        case .absent: write(nil)
        }
    }

    /// nil removes the key, which is how a setting the user never set is left the way it was.
    private static func write(_ value: Bool?) {
        let property: CFPropertyList? = value.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
        CFPreferencesSetAppValue(key, property, kCFPreferencesAnyApplication)
        // Out of toe's own cache and into `cfprefsd` before the window server is told to look.
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        // The window server, the Dock and every running application listen for this one; it is
        // what System Settings posts, and without it the key is a value nobody has read yet.
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
