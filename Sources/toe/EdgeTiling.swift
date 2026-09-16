import CoreFoundation
import Foundation
import ToeCore

/// macOS's own drag-a-window-to-an-edge tiling, switched off for as long as toe runs.
///
/// Dragging a window to the side of the display tiles it to that half, and dragging it to the
/// menu bar fills the screen. That is macOS placing a window toe is meant to be placing, and it
/// lands *after* the mouse comes up — over the top of the frame the release settled, flush with
/// the display edge where every tile around it keeps the margin clear, while the tree is still
/// laid out around the tile the window left. It is the same problem `SymbolicHotkeys` and
/// `WallpaperClick` exist for, arriving by a third route: a window ends up somewhere toe did not
/// put it.
///
/// toe survives it either way — `Coordinator.settleTile` puts a tile back once the snap has
/// stopped animating, and `settleFloat` insets a float macOS snapped to the margin — but
/// surviving a thing is not the same as wanting it, and the recovery is visible: the window goes
/// to macOS's half and comes back about three quarters of a second later.
///
/// Two preferences rather than one, because macOS counts the edges separately.
/// `EnableTilingByEdgeDrag` is the setting System Settings › Desktop & Dock calls "Drag windows
/// to screen edges to tile", and `EnableTopTilingByEdgeDrag` the "Drag windows to menu bar to
/// fill screen" beneath it. Unset means on for both — tiling is the macOS default — so an absent
/// key is a value to put back, not a value to ignore, and each is remembered separately because
/// a user who has already turned one of them off by hand is owed exactly that back.
///
/// `EnableTilingOptionAccelerator` — hold `⌥` while dragging — is deliberately left alone. It is
/// the same tiling asked for on purpose rather than triggered by where a drag happened to end,
/// so what toe takes away is the accident, not the choice.
///
/// Like a symbolic hotkey, **this state outlives the process**, so it is handled the same way:
/// journalled to disk *before* the change, and a journal found at startup is replayed, which is
/// what repairs a crash, a force-quit or a logout.
enum EdgeTiling {

    private static let domain = "com.apple.WindowManager" as CFString

    /// The sides first and the menu bar second, the order System Settings lists them in — which
    /// is also the order the journal is written in, so a file left behind by a crash reads the
    /// way the settings pane does.
    private static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]

    /// What a preference was before toe touched it, and so what `restore` owes the user back.
    /// `absent` is not the same as `on`: writing `true` where there was no key at all would leave
    /// the user's settings holding a value they never set.
    private enum Previous: String {
        case on
        case absent
    }

    /// One `key=state` per line. `WallpaperClick` has a single value and writes it bare; two
    /// need naming, and naming them means a file that survives one of the pair being added or
    /// dropped later — a line the parser does not recognise is ignored, and a truncated or
    /// hand-edited one is dropped rather than read as a state to put back, which is the rule
    /// `WallpaperClick` applies to its one value, line by line.
    private static let journal = Journal<[String: Previous]>(
        name: "edge-tiling",
        serialise: { JournalFormat.serialise(keyed: $0, order: keys) },
        parse: { let was = JournalFormat.parseKeyed($0, keys: keys, as: Previous.self); return was.isEmpty ? nil : was })

    /// The keys `disable` actually took, and what each of them was. Empty until it takes one — a
    /// preference the user had already switched off themselves is not in here, and is never
    /// given back.
    private static var previous: [String: Previous] = [:]

    // MARK: - Applying

    /// Turns edge tiling off, remembering what was there. Idempotent, and a no-op when the user
    /// has already turned both halves of it off themselves.
    static func disable() {
        guard previous.isEmpty else { return }
        // Sequoia is where drag-to-edge tiling arrived. On anything older these keys mean nothing
        // to WindowManager, and writing them would put a value in the user's settings that
        // nothing will ever read and that only toe knows to take out again.
        guard #available(macOS 15, *) else { return }

        var taken: [String: Previous] = [:]
        for key in keys {
            let current = (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.boolValue
            guard current ?? true else { continue }   // already off: nothing to take, nothing owed
            taken[key] = current == nil ? .absent : .on
        }
        guard !taken.isEmpty else { return }

        // Journalled before the change, not after: a crash between the two must leave a record
        // that says too much, never one that says too little. And no record, no change — see
        // `Journal`: a snap toe has to settle is three quarters of a second of nuisance, a
        // tiling switched off with nothing to say so outlives toe.
        guard journal.write(taken) else {
            Log.error("edge tiling: no journal, so macOS's drag-to-edge tiling is left on")
            return
        }
        previous = taken
        for key in taken.keys { write(false, to: key) }
        synchronize()
        Log.info("edge tiling: macOS's drag-to-edge tiling switched off")
    }

    /// Gives back exactly what `disable` took, and clears the journal. Safe to call twice.
    static func restore() {
        guard !previous.isEmpty else {
            journal.clear()
            return
        }
        put(back: previous)
        previous = [:]
        journal.clear()
        Log.info("edge tiling: drag-to-edge tiling restored")
    }

    /// Replays a journal left behind by a toe that did not get to restore — a crash, a `kill -9`,
    /// a logout. Call once at startup, before `disable`.
    static func repairAfterUncleanExit() {
        journal.replay { was in
            put(back: was)
            Log.info("edge tiling: repaired drag-to-edge tiling after an unclean exit")
        }
    }

    // MARK: - The preferences

    private static func put(back previous: [String: Previous]) {
        for (key, was) in previous {
            write(was == .on ? true : nil, to: key)
        }
        synchronize()
    }

    /// nil removes the key, which is how a setting the user never set is left the way it was.
    private static func write(_ value: Bool?, to key: String) {
        let property: CFPropertyList? = value.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
        CFPreferencesSetAppValue(key as CFString, property, domain)
    }

    /// Once, after both keys rather than inside each write. WindowManager reads the preferences
    /// rather than being told about them, so a write has to be out of toe's own cache and in
    /// `cfprefsd` before the next drag asks — and it is read that late: with these written, the
    /// very next drag to an edge lands in its tile with no snap at all, no restart of anything.
    private static func synchronize() {
        CFPreferencesAppSynchronize(domain)
    }
}
