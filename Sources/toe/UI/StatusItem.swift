import AppKit

/// The menu bar item. toe is an `LSUIElement`, so this is its only visible surface.
final class StatusItem: NSObject {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var onReload: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onQuit: (() -> Void)?

    private var warnings: [String] = []
    private var accessibilityGranted = false
    private var workspace = 1

    override init() {
        super.init()
        item.button?.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        rebuild()
    }

    func update(workspace: Int, warnings: [String], accessibilityGranted: Bool) {
        self.workspace = workspace
        self.warnings = warnings
        self.accessibilityGranted = accessibilityGranted
        rebuild()
    }

    private func rebuild() {
        let badge = accessibilityGranted ? "\(workspace)" : "!"
        item.button?.title = "toe \(badge)"
        item.button?.toolTip = accessibilityGranted
            ? "Workspace \(workspace)"
            : "toe needs Accessibility permission"

        let menu = NSMenu()

        if !accessibilityGranted {
            let entry = NSMenuItem(title: "Grant Accessibility permission…",
                                   action: #selector(openAccessibility), keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
            menu.addItem(.separator())
        }

        if warnings.isEmpty {
            let ok = NSMenuItem(title: "Config loaded", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            let header = NSMenuItem(title: "\(warnings.count) config problem(s)", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for warning in warnings {
                submenu.addItem(NSMenuItem(title: warning, action: nil, keyEquivalent: ""))
            }
            menu.setSubmenu(submenu, for: header)
            menu.addItem(header)
        }

        menu.addItem(.separator())
        for (title, key, action) in [
            ("Reload config", "r", #selector(reload)),
            ("Open config…", "o", #selector(openConfig)),
        ] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit toe", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func reload() { onReload?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func openAccessibility() { onOpenAccessibility?() }
    @objc private func quit() { onQuit?() }
}
