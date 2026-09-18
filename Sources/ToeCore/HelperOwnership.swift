import Foundation

/// Which ordinary application an accessory process's windows belong to — the decision behind
/// #158, made here so the selftest can hold it to "Steam Helper and nothing else".
///
/// `WindowTracker` observes `.regular` applications: the ones with a Dock tile and a menu bar,
/// which is what a window the user would want tiled belongs to. Steam is the exception that
/// found this. `steam_osx` (`com.valvesoftware.steam`, `.regular`) owns no window anyone can
/// see; every window the user looks at belongs to *Steam Helper*
/// (`com.valvesoftware.steam.helper`), a child process with `activationPolicy == .accessory`,
/// so toe never created an observer for it and Steam was never tiled, bordered or focused.
///
/// The rule is deliberately narrow, because the alternative — observing every accessory — is
/// wrong: Raycast's settings, 1Password's quick access and the like are standard windows toe
/// should keep leaving alone. An accessory is somebody's helper when both hold:
///
///  * its bundle identifier is a running ordinary application's identifier plus a dotted
///    suffix — `com.valvesoftware.steam` + `.helper`. The suffix is required, and the longest
///    running match wins, so that `com.a.b.helper` belongs to `com.a.b` when both `com.a`
///    and `com.a.b` are running;
///  * an application spawned it, which is to say its parent process is not launchd. Raycast's
///    WebKit helpers are `.accessory` and named under `com.apple.WebKit.*`, but they are
///    XPC-launched — ppid 1 — and the rule leaves them where they are. (Chromium's renderers
///    are `.prohibited` and never reach this.)
///
/// The name check comes first and the parent check second, as an autoclosure: the parent is a
/// `sysctl`, and it is only worth making once the name has matched.
public enum HelperOwnership {

    /// The bundle identifier of the running ordinary application whose helper this is, or nil
    /// when it is an accessory in its own right.
    ///
    /// - Parameters:
    ///   - bundleID: the accessory's own bundle identifier; nil is nobody's helper.
    ///   - regular: the bundle identifiers of every running `.regular` application.
    ///   - spawnedByLaunchd: whether the accessory's parent process is launchd (pid 1) —
    ///     consulted only for a name that matches.
    public static func owner(of bundleID: String?, regular: Set<String>,
                             spawnedByLaunchd: @autoclosure () -> Bool) -> String? {
        guard let bundleID else { return nil }
        let candidates = regular.filter { owner in
            !owner.isEmpty && bundleID.count > owner.count + 1 && bundleID.hasPrefix(owner + ".")
        }
        guard let owner = candidates.max(by: { $0.count < $1.count }) else { return nil }
        return spawnedByLaunchd() ? nil : owner
    }
}
