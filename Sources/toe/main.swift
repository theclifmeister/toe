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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// `toe --print-corner-radius` reports what macOS rounds windows to, so the border can be
// checked without granting Accessibility or launching the agent. Needs NSApp to exist.
if CommandLine.arguments.contains("--print-corner-radius") {
    print(SystemCornerRadius.points)
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
