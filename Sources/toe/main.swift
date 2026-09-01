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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
