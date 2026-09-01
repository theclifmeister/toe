import AppKit
import ToeCore

/// Turns a `MenuIcon` — which is only ever a *name* in ToeCore — into something drawable.
///
/// SF Symbols rather than the Nerd Font glyphs Omarchy's menu uses, for the same reason
/// `StatusItem` draws its workspace square instead of setting a glyph: toe should not need a font
/// installed, and a missing glyph is tofu rather than a graceful fallback. The Omarchy glyph each
/// symbol stands in for is recorded in `MenuIcon.Section.symbolName`.
enum MenuIconRenderer {

    static let side: CGFloat = 16

    static func image(for icon: MenuIcon?) -> NSImage? {
        guard let icon else { return nil }
        switch icon {
        case .section(let section):
            return symbol(section.symbolName)
        case .symbol(let name):
            return symbol(name)
        case .runningApp(let pid):
            return appIcon(pid: pid)
        case .workspace(let index, let filled):
            return workspace(index: index, filled: filled)
        case .gradient(let start, let end):
            return swatch(start: start, end: end)
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let configured = image.withSymbolConfiguration(
            .init(pointSize: 13, weight: .regular)) ?? image
        configured.isTemplate = true
        return configured
    }

    private static func appIcon(pid: Int32) -> NSImage? {
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon,
              let sized = icon.copy() as? NSImage
        else { return nil }
        sized.size = NSSize(width: side, height: side)
        return sized
    }

    /// The digit, or the rounded square `StatusItem` puts on the workspace you are on — so the
    /// menu and the menu bar agree about what a workspace looks like.
    private static func workspace(index: Int, filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            if filled {
                let square = NSRect(x: (rect.width - 8) / 2, y: (rect.height - 8) / 2,
                                    width: 8, height: 8)
                NSColor.labelColor.setFill()
                NSBezierPath(roundedRect: square, xRadius: 2.5, yRadius: 2.5).fill()
            } else {
                // Workspace 10 shows as `0`, as it does on the bar.
                let label = index == WorkspaceManager.workspaceCount ? "0" : String(index)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let text = NSAttributedString(string: label, attributes: attributes)
                let size = text.size()
                text.draw(at: NSPoint(x: (rect.width - size.width) / 2,
                                      y: (rect.height - size.height) / 2))
            }
            return true
        }
        image.cacheMode = .never    // so a light/dark switch cannot leave a stale square behind
        return image
    }

    /// A theme swatch, drawn with the same gradient at the same angle as the focus border it is
    /// about to become.
    private static func swatch(start: String, end: String) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2),
                                    xRadius: 3, yRadius: 3)
            let colours = [NSColor(cgColor: GradientBand.cgColor(start)) ?? .systemBlue,
                           NSColor(cgColor: GradientBand.cgColor(end)) ?? .systemBlue]
            NSGradient(colors: colours)?.draw(in: path, angle: 45)
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
        image.cacheMode = .never
        return image
    }
}
