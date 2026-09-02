import Foundation
import ToeCore
import ServiceManagement

/// Whether toe starts at login, as launchd sees it.
///
/// `SMAppService` rather than a LaunchAgent plist of toe's own: it registers the bundle it is
/// running from, needs no file written into `~/Library/LaunchAgents`, and shows up in System
/// Settings › General › Login Items, where the user can revoke it without going near toe.
///
/// The state is always read, never remembered. A "Run on startup" row that shows a preference
/// toe wrote down is a row that will eventually disagree with what actually happens at login,
/// and the whole value of the row is that it does not.
enum LoginItem {

    static func state() -> LoginItemState {
        if let reason = unavailableReason { return .unavailable(reason) }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .on
        case .requiresApproval:
            // Registered, but the user has switched it off in System Settings. The row goes away
            // rather than offering a switch macOS will not honour; this is the one refusal with
            // somewhere to send them, so it says where.
            Log.info("login item: toe is denied in System Settings › General › Login Items")
            return .unavailable("approve in Settings")
        default:
            return .off
        }
    }

    /// Flips it, and answers with what it now is. A refusal is a state rather than an error:
    /// there is nowhere in a menu row to put a thrown error, and the reason belongs on the row.
    @discardableResult
    static func toggle() -> LoginItemState {
        guard unavailableReason == nil else { return state() }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                Log.info("login item: unregistered")
            } else {
                try service.register()
                Log.info("login item: registered")
            }
        } catch {
            Log.error("login item: \(error.localizedDescription)")
            // The one refusal with somewhere else to go: macOS has the switch, and this is the
            // same move `openAccessibilitySettings` makes for the other permission toe needs.
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        return state()
    }

    /// nil when registering will work. Named rather than left to fail quietly: of the three
    /// possible outcomes, a toggle that reads "on" while nothing starts at login is the worst.
    ///
    /// The reason never reaches the screen: `MenuModel` leaves the row out entirely rather than
    /// showing a switch that cannot be thrown. So every branch here logs, and the log is where
    /// someone wondering why the row is missing will find both the reason and the command that
    /// brings it back.
    private static var unavailableReason: String? {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app" else {
            Log.info("login item: toe is not running from an app bundle, so there is nothing "
                     + "launchd could be pointed at")
            return "not an app bundle"
        }
        // `SMAppService` registers the path it is running from, keyed to the code signature
        // there. From build/Toe.app that registration is real — and then the next `make bundle`
        // does `rm -rf` on the bundle and rebuilds it, leaving launchd pointed at a path that no
        // longer exists under a signature that has changed. Refusing with the command that fixes
        // it is better than a registration that half works.
        let path = Bundle.main.bundleURL.path
        let installed = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        guard installed.contains(where: { path.hasPrefix($0) }) else {
            Log.info("login item: toe is running from \(path) — `make install` puts it where "
                     + "SMAppService can register it")
            return "needs /Applications"
        }
        // `make start-at-login` writes this, and two mechanisms starting toe is one too many.
        // Detected rather than fought with, so the row can never read "off" while launchd is
        // starting toe anyway.
        if let identifier = Bundle.main.bundleIdentifier {
            let agent = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(identifier).plist")
            if FileManager.default.fileExists(atPath: agent.path) {
                Log.info("login item: \(agent.path) already starts toe — `make stop-at-login` "
                         + "removes it")
                return "started by launchd"
            }
        }
        return nil
    }
}
