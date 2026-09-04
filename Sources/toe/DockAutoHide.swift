import Foundation

/// macOS's "Automatically hide and show the Dock", switched on for as long as toe runs.
///
/// A visible Dock is a strip of screen the tiles never get: `NSScreen.visibleFrame` stops short
/// of it, so on a default install the layout gives up ~70 points of one edge to something a
/// tiling user reaches for with `SUPER`+`SPACE` instead. Auto-hiding hands that strip back, and
/// the Dock is still one mouse-to-the-edge away.
///
/// **Why not the preference.** `com.apple.dock`'s `autohide` key is the one System Settings ›
/// Desktop & Dock writes, but unlike `WallpaperClick`'s — which WindowManager re-reads on every
/// click — the Dock reads its own only at launch and on notification. Writing it needs a
/// `killall -HUP Dock` to take effect, which restarts the Dock: badges, running-app dots and
/// animation state all blink out. `CoreDockSetAutoHideEnabled` does the whole job instead — the
/// Dock animates away immediately, the preference is updated underneath, and System Settings
/// shows the new value. It is also what `NSApplication.setPresentationOptions(.autoHideDock)`
/// cannot do: presentation options hold only while the application is *active*, and toe is an
/// `.accessory` that is never frontmost.
///
/// **Why `dlsym` rather than a declaration.** `CoreDock*` is exported by HIServices but is in no
/// public header, so naming it in Swift means declaring it ourselves — and a declaration is a
/// link-time dependency: the day Apple drops the symbol, toe stops launching at all rather than
/// stopping doing this one thing. Looked up at runtime, a missing symbol is a feature that
/// quietly does nothing.
///
/// Like a symbolic hotkey, **this state outlives the process**, so it is handled the same way:
/// journalled to disk *before* the change, and a journal found at startup is replayed, which is
/// what repairs a crash, a force-quit or a logout.
///
/// **Two ways in, meaning two different things.** `enable`/`restore` are the config key being
/// *maintained*: toe hands the strip back if you were not already hiding the Dock yourself, and
/// gives back exactly what it took. `command` is the menu's switch being *thrown*: you are asking
/// for the Dock to be a way, now, so it is told either way and toe stops owing you anything back.
enum DockAutoHide {

    /// `Boolean` in C is an `unsigned char`, not a `_Bool`. The two are passed and returned
    /// identically for 0 and 1, but going through `UInt8` says which one is being called and
    /// leaves no question about what a value outside that pair would mean.
    private typealias GetAutoHide = @convention(c) () -> UInt8
    private typealias SetAutoHide = @convention(c) (UInt8) -> Void

    /// HIServices is not linked into toe, and `dlopen(nil, …)` only sees images already loaded —
    /// so the framework is opened by name. Left open deliberately: a `dlclose` would invalidate
    /// the pointers below, which are held for the life of the process.
    private static let hiServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/"
            + "HIServices.framework/HIServices", RTLD_LAZY)

    private static let getAutoHide: GetAutoHide? = symbol("CoreDockGetAutoHideEnabled")
    private static let setAutoHide: SetAutoHide? = symbol("CoreDockSetAutoHideEnabled")

    private static func symbol<T>(_ name: String) -> T? {
        guard let hiServices, let address = dlsym(hiServices, name) else {
            Log.error("dock: \(name) is missing — the Dock is left the way you have it")
            return nil
        }
        return unsafeBitCast(address, to: T.self)
    }

    private static let journalURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/dock-autohide")

    /// What the setting was before toe touched it, and so what `restore` owes the user back.
    /// One case, because `enable` returns early when auto-hiding is already on: there is then
    /// nothing to take and nothing to give back, so `off` is the only value ever journalled.
    /// It stays an enum for the parsing — a truncated or hand-edited journal is ignored rather
    /// than read as a state to put back.
    private enum Previous: String {
        case off
    }

    private static var previous: Previous?

    // MARK: - Applying

    /// Turns auto-hiding on, remembering what was there. Idempotent, and a no-op when the user
    /// hides the Dock themselves already.
    ///
    /// The read below is only safe because of *when* this is called. `CoreDockSetAutoHideEnabled`
    /// messages the Dock rather than writing a value, and `CoreDockGetAutoHideEnabled` lags that
    /// round trip by a few hundred milliseconds — so a read taken straight after a write reports
    /// the old state. `applyMiscSettings` calls this at startup and on a config reload, and
    /// `previous` short-circuits every call after the first. The one reload that *does* follow a
    /// write is the menu's own switch, and the write there is `command`'s, which happens after
    /// this has run: the next reload is another keystroke away, which is a long time beside a few
    /// hundred milliseconds. Nothing here may re-read to find out what it just did — `previous` is
    /// the answer.
    static func enable() {
        guard previous == nil, let getAutoHide, let setAutoHide else { return }
        guard getAutoHide() == 0 else { return }

        // Journalled before the change, not after: a crash between the two must leave a record
        // that says too much, never one that says too little.
        previous = .off
        writeJournal(.off)
        setAutoHide(1)
        // Nothing to relayout here. Auto-hiding changes `visibleFrame`, which macOS reports as a
        // screen-parameters change, and `WindowTracker` already turns that into `screensChanged`.
        Log.info("dock: auto-hide switched on")
    }

    /// Gives back exactly what `enable` took, and clears the journal. Safe to call twice.
    static func restore() {
        guard previous != nil else {
            clearJournal()
            return
        }
        setAutoHide?(0)
        previous = nil
        clearJournal()
        Log.info("dock: auto-hide restored")
    }

    /// The menu's switch, thrown: makes the Dock match, whatever the two above decided.
    ///
    /// Called after the config file has been written and reloaded, so `enable` or `restore` has
    /// already run and has already done the right thing in every case where toe is the one
    /// holding the setting. What is left is the case they deliberately leave alone — a Dock you
    /// auto-hide yourself, which `restore` will not switch off because `enable` never switched it
    /// on. Maintaining the config key, that silence is correct; it is not toe's preference to
    /// take. A row you just pressed is not that: it is you asking, about your own Dock, so the
    /// Dock is told.
    ///
    /// Nothing is journalled, and a journal that was there is dropped: throwing the switch by
    /// hand hands the setting *to you*, so from here toe owes nothing back. Without that, a Dock
    /// you asked to hide from the menu would be given back to you showing at quit — `enable`
    /// having journalled `off` a moment earlier, on the strength of a state you had already
    /// changed your mind about — and a switch that undoes itself when toe exits is the thing the
    /// journal exists to prevent, pointed the wrong way.
    static func command(_ on: Bool) {
        guard let setAutoHide else { return }
        setAutoHide(on ? 1 : 0)
        previous = nil
        clearJournal()
        Log.info("dock: auto-hide \(on ? "on" : "off"), from the menu")
    }

    /// Replays a journal left behind by a toe that did not get to restore — a crash, a `kill -9`,
    /// a logout. Call once at startup, before `enable`.
    static func repairAfterUncleanExit() {
        guard let text = try? String(contentsOf: journalURL, encoding: .utf8) else { return }
        if Previous(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            setAutoHide?(0)
            Log.info("dock: repaired auto-hide after an unclean exit")
        }
        clearJournal()
    }

    // MARK: - The journal

    private static func writeJournal(_ previous: Previous) {
        try? FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? previous.rawValue.write(to: journalURL, atomically: true, encoding: .utf8)
    }

    private static func clearJournal() {
        try? FileManager.default.removeItem(at: journalURL)
    }
}
