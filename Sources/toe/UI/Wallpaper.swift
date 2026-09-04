import AppKit
import CoreGraphics
import Foundation
import ToeCore

/// The desktop picture, set from the current theme's `backgrounds/`.
///
/// **Why this is journalled but not restored on quit.** `SymbolicHotkeys` and `WallpaperClick`
/// both hand their setting back in `shutDown()`, because toe *borrows* those: you never asked for
/// `Ctrl`+`↑` to stop working, toe switched it off to do its job, and it owes it back. A desktop
/// picture is the other kind — you walked into `Style › Background` and chose it. Putting it back
/// on the way out would undo a decision, and `make run` restarts toe by `pkill` on every single
/// dev cycle, so it would flicker back on every build.
///
/// So it is journalled the way CLAUDE.md asks — written down *before* the first change, and
/// replayable after a `kill -9` — and given back when you clear the theme, which is the moment
/// the choice is actually withdrawn. What outlives the process is remembered; what is given back
/// is given back when it is un-chosen, not when toe stops running.
final class Wallpaper {

    private static let journalURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/wallpaper")

    /// What was on each display before toe first touched it, by the same display UUID
    /// `SessionStore.monitorKey` derives — a `CGDirectDisplayID` is handed out per connection and
    /// would name the wrong screen after a replug.
    private var previous: [String: String] = [:]

    /// What toe last set, so a new display or a Space that has not seen it yet can be caught up.
    private var current: URL?

    // MARK: - Setting

    func set(_ url: URL) {
        journalIfNeeded()
        current = url
        apply(url)
    }

    /// A display appeared, or the Space changed under us.
    ///
    /// With *Displays have separate Spaces* on — the macOS default — `setDesktopImageURL(for:)`
    /// applies to the current Space on that screen and not to the others, so switching Spaces
    /// otherwise brings the old picture back. This is the same underlying fact as toe's
    /// workspaces not being macOS Spaces.
    func reapply() {
        guard current != nil else { return }
        // Before the write, not after — a display that has just appeared has a wallpaper of its
        // own, and this is the only moment it can still be seen.
        journalIfNeeded()
        guard let current else { return }
        apply(current)
    }

    private func apply(_ url: URL) {
        for screen in NSScreen.screens {
            // The read-back is what makes calling this from `screensChanged` and
            // `activeSpaceChanged` free: setting a desktop picture is a synchronous trip into
            // another process and costs tens of milliseconds, and both of those fire often.
            guard NSWorkspace.shared.desktopImageURL(for: screen) != url else { continue }
            do {
                // No options, so whatever fill mode the user chose in System Settings survives.
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                Log.error("wallpaper: \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Giving it back

    /// Puts back what was there before toe first changed it. Called when the theme is cleared.
    func restore() {
        let saved = previous.isEmpty ? Self.readJournal() : previous
        // Whatever is or is not restorable, toe is no longer choosing a picture: `current` has to
        // be dropped either way, or the next Space switch would have `reapply` push the very
        // picture that was just un-chosen onto a Space that never had it.
        defer {
            previous.removeAll()
            current = nil
            Self.clearJournal()
        }
        guard !saved.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let key = Self.key(for: screen), let path = saved[key] else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    /// Stop catching displays and Spaces up, without putting anything back.
    ///
    /// For the theme that changed to one carrying no pictures of its own: the new theme has
    /// nothing to say about the wallpaper, so toe stops having an opinion too. Without this,
    /// `reapply` would go on spreading the *previous* theme's picture onto every Space visited
    /// next — a picture from a theme you have already left.
    func forget() {
        current = nil
    }

    /// A `kill -9` between the journal and the change must leave a record that says too much
    /// rather than one that says too little, so the journal is only read here — never cleared —
    /// and what it holds is simply what was there before toe started meddling. Loading it at
    /// startup means a theme picked in one run is still reversible in the next.
    func repairAfterUncleanExit() {
        guard previous.isEmpty else { return }
        previous = Self.readJournal()
    }

    /// Notes what is on any display toe has not written down yet.
    ///
    /// Per display rather than once per process, and that is the whole point: a monitor plugged
    /// in after a theme was set is one `reapply` will happily write to, and a once-only gate
    /// would mean its own wallpaper was overwritten with nothing recorded to give back. A key
    /// already present is never overwritten — the first thing toe saw on a display is the thing
    /// it owes, not whatever toe itself put there afterwards.
    private func journalIfNeeded() {
        var added = false
        for screen in NSScreen.screens {
            guard let key = Self.key(for: screen), previous[key] == nil,
                  let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            // Never record toe's own picture as the thing to give back.
            guard url != current else { continue }
            previous[key] = url.path
            added = true
        }
        guard added else { return }
        Self.writeJournal(previous)                    // before the change, never after
    }

    // MARK: - The journal file

    private static func key(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return SessionStore.monitorKey(CGDirectDisplayID(number.uint32Value))
    }

    private static func writeJournal(_ entries: [String: String]) {
        try? FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // One display per line, tab-separated — a path can hold anything but a tab and a newline,
        // and this file is read by the same code that wrote it.
        let text = entries.sorted { $0.key < $1.key }
            .map { "\($0.key)\t\($0.value)" }
            .joined(separator: "\n")
        try? text.write(to: journalURL, atomically: true, encoding: .utf8)
    }

    private static func readJournal() -> [String: String] {
        guard let text = try? String(contentsOf: journalURL, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            out[parts[0]] = parts[1]
        }
        return out
    }

    private static func clearJournal() {
        try? FileManager.default.removeItem(at: journalURL)
    }
}

/// Which picture is current, remembered next to `session.json`.
///
/// Not a journal — see `Wallpaper`: this is a choice to remember, not a setting to give back. The
/// file *name* only, never a path, so it re-resolves against whichever theme is current and a name
/// that is no longer there simply reads as "nothing current", which `Backgrounds.next` turns into
/// starting from the first.
enum BackgroundStore {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/background")

    static func load() -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func save(_ name: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? name.write(to: url, atomically: true, encoding: .utf8)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
