import CoreFoundation
import Foundation
import ToeCore

/// macOS's "click the wallpaper to show desktop", switched off for as long as toe runs.
///
/// A click on any bare patch of wallpaper sweeps every window off the sides of the screen and
/// leaves them there until the next click. That is the same problem `DockSwipeTap` and
/// `SymbolicHotkeys` exist for, arriving by a third route: toe's tiles go somewhere toe did not
/// put them, and a hidden workspace's off-screen stash — see `Stash` — slides into view alongside
/// them. With `[general] gaps_out` set, the wallpaper shows through around the tiles, so the click
/// is one missed window edge away at any time.
///
/// There is nothing to swallow here. The reveal is decided inside WindowManager from a click that
/// belongs to the wallpaper, not to any window, and it is a setting rather than a gesture:
/// `EnableStandardClickToShowDesktop` in `com.apple.WindowManager`, which is the same preference
/// System Settings › Desktop & Dock › "Click wallpaper to show desktop" writes. Unset means on —
/// revealing the desktop is the macOS default — so an absent key is a value to put back, not a
/// value to ignore.
///
/// Like a symbolic hotkey, **this state outlives the process**, so it is handled the same way:
/// journalled to disk *before* the change, and a journal found at startup is replayed, which is
/// what repairs a crash, a force-quit or a logout.
enum WallpaperClick {

    private static let domain = "com.apple.WindowManager" as CFString
    private static let key = "EnableStandardClickToShowDesktop" as CFString

    /// What the preference was before toe touched it, and so what `restore` owes the user back.
    /// `absent` is not the same as `on`: writing `true` where there was no key at all would leave
    /// the user's settings holding a value they never set.
    private enum Previous: String {
        case on
        case absent
    }

    /// The one value, written bare.
    private static let journal = Journal<Previous>(
        name: "wallpaper-click",
        serialise: JournalFormat.serialise(word:),
        parse: { JournalFormat.parseWord($0) })

    private static var previous: Previous?

    // MARK: - Applying

    /// Turns the reveal off, remembering what was there. Idempotent, and a no-op when the user has
    /// already turned it off themselves — there is then nothing to take and nothing to give back.
    static func disable() {
        guard previous == nil else { return }
        let current = (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.boolValue
        guard current ?? true else { return }

        // Journalled before the change, not after: a crash between the two must leave a record
        // that says too much, never one that says too little. And no record, no change — see
        // `Journal`: a reveal that still works is a nuisance, a reveal switched off with nothing
        // to say so outlives toe.
        let was: Previous = current == nil ? .absent : .on
        guard journal.write(was) else {
            Log.error("wallpaper click: no journal, so reveal-desktop is left on")
            return
        }
        previous = was
        write(false)
        Log.info("wallpaper click: reveal-desktop switched off")
    }

    /// Gives back exactly what `disable` took, and clears the journal. Safe to call twice.
    static func restore() {
        guard let previous else {
            journal.clear()
            return
        }
        put(back: previous)
        Self.previous = nil
        journal.clear()
        Log.info("wallpaper click: reveal-desktop restored")
    }

    /// Replays a journal left behind by a toe that did not get to restore — a crash, a `kill -9`,
    /// a logout. Call once at startup, before `disable`.
    static func repairAfterUncleanExit() {
        journal.replay { was in
            put(back: was)
            Log.info("wallpaper click: repaired reveal-desktop after an unclean exit")
        }
    }

    // MARK: - The preference

    private static func put(back previous: Previous) {
        switch previous {
        case .on: write(true)
        case .absent: write(nil)
        }
    }

    /// nil removes the key, which is how a setting the user never set is left the way it was.
    private static func write(_ value: Bool?) {
        let property: CFPropertyList? = value.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
        CFPreferencesSetAppValue(key, property, domain)
        // WindowManager reads the preference rather than being told, so the write has to be out of
        // toe's own cache and in `cfprefsd` before the next click asks.
        CFPreferencesAppSynchronize(domain)
    }
}
