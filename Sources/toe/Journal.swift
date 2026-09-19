import Foundation
import ToeCore

/// A note of what a macOS setting was before toe changed it, kept in `~/.local/state/toe`.
///
/// Five of toe's changes outlive the process — Mission Control's shortcut, the wallpaper click,
/// drag-to-edge tiling, the Dock's auto-hide and the menu bar's belong to the window server,
/// `cfprefsd` or the Dock, not to toe — and the desktop picture is a sixth that is remembered
/// the same way. Each
/// is journalled *before* the change is made and replayed in reverse at startup, which is what
/// repairs a crash, a `kill -9` or a logout. The rule every caller works by: a crash between
/// the journal and the change must leave a record that says too much, never one that says too
/// little.
///
/// Which is why `write` answers. A record that did not reach the disk is a record that says
/// nothing, and a caller that goes on to make its change anyway has the exact failure the
/// journal exists to prevent, with nothing in the log to explain it — so the callers refuse the
/// change instead, and the reason is logged here. `Wallpaper` is the one that goes ahead, and
/// says why.
///
/// The six files differ only in their lines, and the lines are `JournalFormat`'s so the
/// selftest can read them; what is here is the file.
struct Journal<Record> {

    /// The file's name under the state directory.
    let name: String
    let serialise: (Record) -> String
    /// nil is a file with nothing in it to put back — empty, or every line malformed — and is
    /// treated exactly as no file at all, bar being cleared.
    let parse: (String) -> Record?

    var url: URL { StateDirectory.url.appendingPathComponent(name) }

    /// Writes the record, and answers whether it is on the disk. `false` has already been
    /// logged; the caller's job is to not make the change.
    func write(_ record: Record) -> Bool {
        guard StateDirectory.ensure() else { return false }
        do {
            try serialise(record).write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Log.error("journal: could not write \(name): \(error.localizedDescription)")
            return false
        }
    }

    /// What a previous toe left behind, if anything.
    func read() -> Record? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// The repair: hands whatever a toe that did not get to restore left behind to `putBack`,
    /// then clears the file. Call once at startup, before the change is made again.
    func replay(_ putBack: (Record) -> Void) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        if let record = parse(text) { putBack(record) }
        clear()
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
