import Foundation

/// An application that has been *found* — the name Finder shows and the bundle it is.
///
/// The same shape as `ThemeRef`, and for the same reason: the list is rebuilt every time the
/// menu opens, a row needs a name and a way to launch it, and reading a hundred and twenty
/// `Info.plist`s to draw a list is the version of this that does not ship. The name comes from
/// `FileManager.displayName(atPath:)` in the app layer, which is where localisation and the
/// stripped `.app` come from; the path is what `NSWorkspace` opens and what the icon is read
/// from, and neither needs the bundle opened first.
public struct AppRef: Equatable, Sendable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// The application list the menu draws.
///
/// Omarchy's `Apps` is a *provider* level — its rows come from the desktop entries on the
/// machine at the moment the menu is opened rather than from the menu file — and this is that
/// half of it: what to do with a list once it has been read. The reading is a directory scan in
/// the app layer (`AppLibrary`), so that this half is in the selftest.
public enum Apps {

    /// In the order the level draws them: by name, ignoring case, stable for the rest.
    ///
    /// The scan hands them over folder by folder, which would put every system application
    /// after every third-party one; a launcher you type into does not care, but a level you
    /// scroll does. Two entries with the same name — an app in `~/Applications` and again in
    /// `/Applications` — are both listed: on disk they are two things, and choosing one to hide
    /// would be guessing which the user meant to keep.
    public static func ordered(_ found: [AppRef]) -> [AppRef] {
        found.sorted { a, b in
            let (l, r) = (a.name.lowercased(), b.name.lowercased())
            return l == r ? a.path < b.path : l < r
        }
    }
}
