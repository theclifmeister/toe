import AppKit
import ServiceManagement
import ToeCore

/// The system rows' side effects. Each one is either a plain subprocess or an Apple event, and
/// between the Accessibility grant toe already holds and the `NSAppleEventsUsageDescription` already
/// in Info.plist, none of them needs a new entitlement.
enum SystemActions {

    static func perform(_ action: SystemAction) {
        switch action {
        case .lock:
            // There is no public lock API. `SACLockScreenImmediate` via `dlopen` on
            // login.framework would work, but a project whose README makes a point of *not*
            // reaching for private SkyLight calls should not reach for a private symbol here
            // either — and `CGSession -suspend` is fast user switching rather than locking, with
            // its `User.menu` host no longer shipping on recent macOS. ⌃⌘Q is Lock Screen: the same
            // thing the user's own fingers would do, through the grant toe already has.
            systemEvents("keystroke \"q\" using {command down, control down}")
        case .sleepDisplay:
            // Named honestly: this locks only if "Require password immediately after sleep" is set,
            // which is why it is not called Lock.
            shell("/usr/bin/pmset", ["displaysleepnow"])
        case .sleep:
            // pmset rather than an Apple event, so it works before any Automation prompt has been
            // answered — it needs no permission from the console user at all.
            shell("/usr/bin/pmset", ["sleepnow"])
        case .logOut:
            systemEvents("log out")
        case .restart:
            systemEvents("restart")
        case .shutDown:
            systemEvents("shut down")
        }
    }

    /// Relaunch. `unstashEverything` has to have run first — the comment on
    /// `Coordinator.installSignalHandlers` spells out why: windows left parked in the stash corner
    /// are adopted there by the next launch, which then records the corner as the frame to float
    /// them back to.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, error in
            if let error { Log.error("relaunch failed: \(error.localizedDescription)") }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func systemEvents(_ command: String) {
        shell("/usr/bin/osascript",
              ["-e", "tell application \"System Events\" to \(command)"])
    }

    private static func shell(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            Log.error("\(path) failed: \(error.localizedDescription)")
        }
    }
}

/// Start-at-login, via `SMAppService` rather than by writing the Makefile's LaunchAgent plist:
/// path-independent, no `launchctl` subprocess, no second source of truth, and it shows up in
/// System Settings › General › Login Items where people look for it.
enum StartAtLogin {

    /// What `make start-at-login` writes. If it is there, `SMAppService` must not also be
    /// registered — two toes would launch and fight over every window.
    static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.clifmeister.toe.plist")
    }

    static var state: StartAtLoginState {
        if FileManager.default.fileExists(atPath: legacyPlistURL.path) {
            return .legacyLaunchAgent
        }
        // SMAppService needs a bundle. Running the bare binary out of .build has none.
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .notRegistered, .notFound: return .off
        case .requiresApproval: return .on      // registered; the user has yet to allow it
        @unknown default: return .unavailable
        }
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Log.info("registered for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                Log.info("unregistered from launch at login")
            }
        } catch {
            Log.error("start at login: \(error.localizedDescription)")
        }
    }

    /// Unload the LaunchAgent and delete it, so the in-app toggle becomes the single mechanism.
    static func removeLegacyLaunchAgent() {
        let url = legacyPlistURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", url.path]
        try? process.run()
        process.waitUntilExit()
        do {
            try FileManager.default.removeItem(at: url)
            Log.info("removed the legacy LaunchAgent at \(url.path)")
        } catch {
            Log.error("could not remove \(url.path): \(error.localizedDescription)")
        }
    }
}
