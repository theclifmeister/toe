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
///
/// The file is not always there. With one of macOS's own desktops — which is every Mac before
/// a toe theme is installed — `NSWorkspace` answers a path under
/// `~/Library/Application Support/com.apple.mobileAssetDesktop/` that WallpaperAgent fetches on
/// demand and may never have written, and a theme whose backgrounds are still downloading
/// names a file that is not on disk yet. macOS ships a thumbnail of every desktop it offers,
/// though — `/System/Library/Desktop Pictures/.thumbnails/<name>.heic`, 214 × 130, and the
/// aerials keep theirs under `com.apple.wallpaper/aerials/thumbnails/` — so when the picture
/// itself will not decode, the thumbnail with the same name is the backdrop: soft, but the
/// right colours in the right places, and under cards that then dissolve into the sharp real
/// thing that reads as a focus pull rather than a mistake. A miss is retried on the next
/// swipe, because the file that was not there may be by then, and is logged once.
final class DesktopPictures {

    private var images: [URL: CGImage] = [:]
    private var decoding: Set<URL> = []
    private var reported: Set<URL> = []

    /// Where macOS keeps a small picture of each desktop it ships, and of each aerial it has
    /// fetched, under the desktop's own file name.
    private static let thumbnailFolders: [URL] = [
        URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails",
                                    isDirectory: true),
    ]

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
            let decoded = Self.decode(url, maxPixels: Int(pixels))
            DispatchQueue.main.async {
                guard let self else { return }
                self.decoding.remove(url)
                guard let decoded else {
                    if self.reported.insert(url).inserted {
                        Log.info("slide: desktop picture at \(url.path) could not be decoded and has no"
                                 + " thumbnail; the cards slide over the theme colour until it can")
                    }
                    return
                }
                // One picture per URL, and the URLs that are no longer anyone's desktop go
                // with the next `prepare`; a desktop changed ten times is not ten pictures.
                self.images = self.images.filter { held in
                    NSScreen.screens.contains { NSWorkspace.shared.desktopImageURL(for: $0) == held.key }
                }
                self.images[url] = decoded.image
                Log.info("slide: desktop picture decoded — \(decoded.image.width)×\(decoded.image.height),"
                         + " \(decoded.image.width * decoded.image.height * 4 / 1_048_576) MB"
                         + (decoded.fromThumbnail ? " — macOS's thumbnail of it; the picture itself is not on disk" : ""))
            }
        }
    }

    /// The picture at `url`, or failing that macOS's thumbnail of the desktop with that name.
    private static func decode(_ url: URL, maxPixels: Int) -> (image: CGImage, fromThumbnail: Bool)? {
        if let image = thumbnail(of: url, maxPixels: maxPixels) { return (image, false) }
        let stem = url.deletingPathExtension().lastPathComponent
        for folder in thumbnailFolders {
            for ext in ["heic", "png", "jpg"] {
                let candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
                if let image = thumbnail(of: candidate, maxPixels: maxPixels) { return (image, true) }
            }
        }
        return nil
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
