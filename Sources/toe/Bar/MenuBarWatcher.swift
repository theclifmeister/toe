import AppKit
import ToeCore

/// Where the menu bar the bar covers has gone, read without a permission: the active
/// application's presentation options for a game or a slideshow that has put it away, and
/// macOS's *Automatically hide and show the menu bar* for the user who has. See
/// `MenuBarHiding` and `BarReveal` for what the bar does with the answers.
///
/// Both are listened to rather than polled: `currentSystemPresentationOptions` is KVO
/// compliant and changes when the active application sets its options or a different
/// application becomes active (measured for T8, against another process), and System
/// Settings posts `AppleInterfaceMenuBarHidingChangedNotification` when the auto-hide
/// setting changes — the notification yabai's `menu_bar_hidden_changed` is built on.
final class MenuBarWatcher {

    var onChange: (() -> Void)?
    private var presentation: NSKeyValueObservation?
    private var hiding: NSObjectProtocol?

    func start() {
        guard presentation == nil else { return }
        presentation = NSApp.observe(\.currentSystemPresentationOptions) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onChange?() }
        }
        hiding = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"),
            object: nil, queue: .main) { [weak self] _ in self?.onChange?() }
    }

    /// macOS is keeping the menu bar hidden on the desktop until the pointer reaches it —
    /// *Always* or *On Desktop Only* in System Settings, both of which set `_HIHideMenuBar` in
    /// the global domain. Read from the global domain explicitly: an early cut of the bar set
    /// the same key in toe's own domain, and a leftover there must not read as the user's
    /// choice.
    var autoHides: Bool {
        CFPreferencesCopyValue("_HIHideMenuBar" as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool ?? false
    }

    /// The displays the active application has put the menu bar away on: empty when its
    /// presentation options leave the menu bar alone — the ordinary case, answered without
    /// asking the window server anything — else the display under its frontmost window, or
    /// every display when it shows none toe can place.
    func hiddenDisplays() -> Set<CGDirectDisplayID> {
        guard MenuBarHiding.hidesMenuBar(presentationOptions: NSApp.currentSystemPresentationOptions.rawValue)
        else { return [] }
        let screens = NSScreen.screens
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return Set(screens.map(\.displayID)) }
        // Front to back, as the window list orders it. Bounds and owner are readable without
        // Screen Recording — only titles are behind it — and already in Accessibility
        // coordinates. A menu the game has open is not where the game is.
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = list.compactMap { info -> Box? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int != menuLevel,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return Box(x: bounds.minX, y: bounds.minY, w: bounds.width, h: bounds.height)
        }
        guard let index = MenuBarHiding.display(of: windows, among: screens.map { Coordinates.toAX($0.frame) })
        else { return Set(screens.map(\.displayID)) }
        return [screens[index].displayID]
    }
}
