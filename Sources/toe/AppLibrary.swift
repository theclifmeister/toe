import AppKit
import ToeCore

/// Reads the application folders — what the `Apps` level lists.
///
/// The disk half of `Apps`, the way `ThemeStore` is the disk half of `Themes`: ToeCore orders
/// and draws, this walks directories. It is a scan rather than a Spotlight query because
/// Spotlight is asynchronous, can be switched off, and answers for every bundle on every
/// volume; the four folders below are where the Finder and the Dock look, and a hundred and
/// twenty entries come back in a few milliseconds.
///
/// Omarchy's `Apps` reads the desktop entries and drops the ones marked `NoDisplay`. macOS has
/// no such mark: `LSUIElement` is the nearest, and it is on Docker, Raycast and Screenshot —
/// applications people launch — as well as on the URL handlers nobody does. So nothing is
/// filtered, and nothing is opened: every bundle is one `displayName` call, which is what the
/// Finder shows and is already localised with the `.app` taken off.
enum AppLibrary {

    /// The Finder's own list, in the order it searches them. One level of sub-folders as well,
    /// because that is where `Utilities` is — `/Applications/Utilities` and
    /// `/System/Applications/Utilities` are the two that matter, and a folder an installer made
    /// (`/Applications/Adobe`) is the same shape.
    ///
    /// The cryptex is where Safari has lived since macOS 14: it ships as a separately-signed
    /// volume so it can be updated on its own, and `/Applications/Safari.app` is a symlink into
    /// it carrying the `hidden` flag — so a scan of `/Applications` that skips hidden entries,
    /// as this one does, never sees Safari. Listing the cryptex directly is how the Finder
    /// finds it, and it is the one folder here that most people have never opened.
    static let folders: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
    ]

    /// Everything found, unordered — `Apps.ordered` is the caller's next call.
    ///
    /// Safe off the main thread, which is where the Coordinator runs it: `FileManager` and
    /// `displayName(atPath:)` are, and nothing here touches a window.
    static func installed() -> [AppRef] {
        var found: [AppRef] = []
        for folder in folders {
            scan(folder, depth: 1, into: &found)
        }
        return found
    }

    private static func scan(_ folder: URL, depth: Int, into found: inout [AppRef]) {
        let fm = FileManager.default
        // `.isDirectoryKey` rather than `.isPackageKey`: a Homebrew cask can leave an alias in
        // `/Applications`, and a symlink to a bundle is not itself a package but is a thing
        // the Finder lists and `open` opens.
        guard let entries = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return }
        for url in entries {
            if url.pathExtension == "app" {
                found.append(AppRef(name: fm.displayName(atPath: url.path), path: url.path))
            } else if depth > 0,
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                scan(url, depth: depth - 1, into: &found)
            }
        }
    }

    /// Opens the bundle the way a double-click in the Finder does.
    ///
    /// `NSWorkspace` rather than `open` through `/bin/sh` — see `MenuItem.Action.launch` — and
    /// `openApplication` rather than `open(_ url:)`, which is for documents. Activation is the
    /// default configuration's, so the application comes forward the way it does from the Dock,
    /// and the tracker sees its window the way it sees any other new one. Failure is logged and
    /// not shown: the menu closed before this ran, and there is no surface left to say it on —
    /// which is what an `exec` that fails gets too.
    static func launch(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.error("apps: could not open \(path): \(error.localizedDescription)")
            }
        }
    }
}
