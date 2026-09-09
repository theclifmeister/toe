import AppKit
import ToeCore

/// toe runs as an agent: no Dock icon, no main window, just a menu bar item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = Coordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}

// `toe --print-default-config` keeps toe.example.toml in sync with the shipped default.
if CommandLine.arguments.contains("--print-default-config") {
    print(Config.defaultTOML)
    exit(0)
}

// `toe --version` reports what the bundle was stamped with, which is how the release workflow
// checks that the tag made it into the app. Run outside a bundle there is nothing to report.
if CommandLine.arguments.contains("--version") {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    print(version ?? "unknown")
    exit(0)
}

// The command line. `toe query state`, `toe dispatch "workspace 3"` and the rest talk to the copy
// already running, over the socket in ~/.local/state/toe — see `ControlSocket` for why a socket
// and not a Mach service.
//
// Before `NSApplication.shared`, deliberately and not merely for speed: touching it connects to
// the window server and makes this process an application as far as macOS is concerned, which is
// not what a shell command should be. A verb here is a few milliseconds, one file descriptor and
// no Accessibility at all.
//
// Anything that is not one of these verbs falls through and starts the window manager, exactly as
// it always has — including the flags above and the `-psn_…` argument some launches of
// `open Toe.app` carry. A first word that is neither a flag nor a verb stops with a usage error
// rather than starting a second window manager on top of the running one.
//
// `isInteractive` is what tells a bare `toe` typed at a prompt from the launchd and `open
// Toe.app` invocations that carry no arguments either — see `ControlCLI.parse`. Either descriptor
// being a terminal is enough, because a pipe or a redirect takes the other one away and the thing
// being asked is who typed this, not where its output goes.
let invocation = ControlCLI.parse(Array(CommandLine.arguments.dropFirst()),
                                  isInteractive: isatty(STDIN_FILENO) == 1 || isatty(STDOUT_FILENO) == 1)
if case .agent = invocation.kind {} else {
    exit(ControlClient.run(invocation))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// `toe --print-corner-radius` reports what macOS rounds windows to, so the border can be
// checked without granting Accessibility or launching the agent. Needs NSApp to exist.
//
// The fallback first, then what the window server says about each window on screen — which is
// the interesting half, since that is the number the border actually draws with, and the two
// disagree for most windows.
if CommandLine.arguments.contains("--print-corner-radius") {
    print("fallback: \(SystemCornerRadius.points) pt (\(SystemCornerRadius.source))")
    guard WindowCornerRadius.isAvailable else {
        print("per-window query unavailable; every window uses the fallback")
        exit(0)
    }
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    // `%@` ignores a width specifier for a Swift string, so the columns are padded by hand.
    func row(_ id: String, _ radius: String, _ owner: String) {
        print(id.padding(toLength: 8, withPad: " ", startingAt: 0)
            + radius.padding(toLength: 14, withPad: " ", startingAt: 0) + owner)
    }
    row("wid", "radius", "owner")
    for info in windows {
        guard let id = info[kCGWindowNumber as String] as? WindowID else { continue }
        let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
        let radius = WindowCornerRadius.points(for: id)
            .map { "\($0) pt" } ?? "- (fallback)"
        row("\(id)", radius, owner)
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
