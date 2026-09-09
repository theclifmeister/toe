import AppKit

/// Which copy of toe this is, and how it takes the machine from the other one.
///
/// There are two: the installed application, signed with the Developer ID certificate, and the
/// one `make run` builds, signed with toe-dev. macOS keys an Accessibility grant to a bundle
/// identifier and the signature stored against it, so a shared identifier means every swap
/// between them invalidates the other's grant and asks for the permission again. They carry
/// separate identifiers instead — `scripts/bundle.sh` stamps the development one — which makes
/// them two applications as far as macOS is concerned, each with a grant of its own, given once.
///
/// Two applications, but still one machine. Everything toe does is global: the Carbon hotkeys,
/// the event taps, the windows themselves, and the four system settings journalled to
/// `~/.local/state/toe`. Two copies running at once would fight over all of it, and the journals
/// are the part that does not simply sort itself out — both would write, and whichever exited
/// last would hand back a "before" state the other had already changed. So a starting copy takes
/// the machine from whichever one holds it.
enum AppIdentity {

    static let installed = "com.clifmeister.toe"
    static let development = "com.clifmeister.toe.dev"

    /// Whether this is the copy `make run` built. The one place it reaches the screen is the
    /// quick menu's `About` row: two copies that cannot be told apart are two copies you will
    /// eventually debug the wrong one of.
    static var isDevelopment: Bool { Bundle.main.bundleIdentifier == development }

    /// What this copy was stamped with, or nil for a binary run straight out of `.build`, which
    /// has no `Info.plist` to have been stamped.
    static var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Where this binary is, absolutely.
    ///
    /// The skill document names it, because nothing puts toe on a PATH — it lives inside an
    /// application bundle, and an agent that has to guess at the path is an agent that gives up.
    /// `argv[0]` is the fallback for the case `Bundle` cannot answer, which is a binary invoked
    /// through a symlink from somewhere odd; it is the path the caller actually used, which is
    /// the next best thing to the real one.
    static var binaryPath: String {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    }

    /// Asks every other copy of toe to quit, and waits for it to be gone.
    ///
    /// `SIGTERM`, not `NSRunningApplication.terminate()`: that sends a quit Apple Event, which
    /// AppKit answers by terminating without going near `Coordinator.shutDown` — so the outgoing
    /// copy would leave every hidden workspace's windows parked in the stash corner and the four
    /// journalled settings unrestored. The signal handler is toe's one teardown path and is
    /// exactly what `make run`'s `pkill` has always used.
    ///
    /// Called before anything in `start` touches those journals, because the copy on its way out
    /// is still writing them.
    static func takeOver() {
        let others = otherCopies()
        guard !others.isEmpty else { return }

        for app in others {
            Log.info("another toe is running (pid \(app.processIdentifier), "
                     + "\(app.bundleIdentifier ?? "no bundle id")) — asking it to quit")
            kill(app.processIdentifier, SIGTERM)
        }

        // Bounded like `make run`'s wait, and generous for the same reason: the outgoing copy
        // unstashes every window it had parked before it goes, and that is a synchronous
        // Accessibility write per window. Spinning the run loop rather than sleeping — this runs
        // before `NSApp.run`, and the `isTerminated` this polls is only updated by AppKit
        // servicing its notifications.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        // A copy that will not answer is worse than one killed outright: it still holds the
        // hotkeys and the event taps, and this one is about to start writing frames it disagrees
        // with. What is lost is its session snapshot and whatever it had stashed, which is why
        // this is the second thing tried and not the first — and why it says so.
        for app in others where !app.isTerminated {
            Log.error("toe (pid \(app.processIdentifier)) did not quit within 5s — killing it. "
                      + "Windows on its hidden workspaces may be left parked off-screen.")
            kill(app.processIdentifier, SIGKILL)
        }
    }

    /// Every running toe but this one.
    ///
    /// By bundle identifier, and by executable name for anything running outside a bundle —
    /// `swift run toe` has no `Info.plist` and so no identifier to match, and it manages windows
    /// just the same.
    private static func otherCopies() -> [NSRunningApplication] {
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != mine else { return false }
            if let id = app.bundleIdentifier { return id == installed || id == development }
            return app.executableURL?.lastPathComponent == "toe"
        }
    }
}
