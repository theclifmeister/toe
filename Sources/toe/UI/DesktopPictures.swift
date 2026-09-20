import AppKit
import ImageIO
import ToeCore

/// The desktop picture behind each display, read from its file — the backdrop the cards
/// slide over.
///
/// The cards slide needs to hide the real windows under it, because the switch is made while
/// the cards are moving and a workspace's windows arriving in the gaps between them would give
/// the game away. A photograph of the wallpaper would do it and costs Screen Recording, which
/// is the permission the cards exist to avoid. But the wallpaper is a *file*, and `NSWorkspace`
/// says which — the same read-back `Wallpaper` already leans on — so this decodes that file
/// and draws it where the window server would. Not pixel-exact: a dynamic desktop is decoded
/// at its first image, and the fill is aspect-fill whatever System Settings was told, which is
/// right for nearly everyone and a third of a second wrong for the rest.
///
/// Decoded ahead of the swipe, never on it. A 6K wallpaper takes 50–100 ms to decode, which is
/// the whole slide's head start, so a miss answers nil — the caller draws the theme colour
/// instead, for that one swipe — and starts the decode for the next. Decoded through
/// `CGImageSourceCreateThumbnailAtIndex` at half the display's pixels, for `wallpaperScale`'s
/// reason exactly: it is a backdrop under moving cards, `contentsGravity` stretches it back up
/// for free, and half the pixels is a quarter of the memory — about 7 MB per display.
final class DesktopPictures {

    private var images: [URL: CGImage] = [:]
    private var decoding: Set<URL> = []

    /// The picture on `screen` if it is decoded, else nil and a decode under way.
    func image(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let image = images[url] { return image }
        decode(url, for: screen)
        return nil
    }

    /// Starts decoding every display's picture that is not already in hand.
    func prepare() {
        for screen in NSScreen.screens { _ = image(for: screen) }
    }

    private func decode(_ url: URL, for screen: NSScreen) {
        guard !decoding.contains(url) else { return }
        decoding.insert(url)
        let pixels = max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor / 2
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.thumbnail(of: url, maxPixels: Int(pixels))
            DispatchQueue.main.async {
                guard let self else { return }
                self.decoding.remove(url)
                if let image {
                    // One picture per URL, and the URLs that are no longer anyone's desktop go
                    // with the next `prepare`; a desktop changed ten times is not ten pictures.
                    self.images = self.images.filter { held in
                        NSScreen.screens.contains { NSWorkspace.shared.desktopImageURL(for: $0) == held.key }
                    }
                    self.images[url] = image
                    Log.info("slide: desktop picture decoded — \(image.width)×\(image.height),"
                             + " \(image.width * image.height * 4 / 1_048_576) MB")
                } else {
                    Log.info("slide: desktop picture at \(url.path) could not be decoded; the cards slide over the theme colour")
                }
            }
        }
    }

    private static func thumbnail(of url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
