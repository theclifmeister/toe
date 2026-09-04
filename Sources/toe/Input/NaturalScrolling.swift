import Foundation

/// System Settings › Trackpad › *Natural scrolling*, the one preference the sideways dock swipe
/// has to honour: macOS reverses its own Spaces swipe with it, and so `WorkspaceTarget.swipe`.
enum NaturalScrolling {
    /// The key is `defaults read -g com.apple.swipescrolldirection`, in the global domain, which
    /// `UserDefaults.standard` searches after toe's own. Absent until the setting has been touched,
    /// and the untouched default is on. Read per swipe rather than cached: cheap, once a gesture,
    /// and it is the way a change in System Settings lands without a restart.
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }
}
