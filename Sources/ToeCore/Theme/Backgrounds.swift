import Foundation

/// The pictures a theme carries, and the order they are walked in.
///
/// Both halves live here together on purpose: the order the `Background` menu lists them in and
/// the order `nextbackground` steps through are the same list, and the day those two drift apart
/// is the day the menu says one thing and the key does another.
public enum Backgrounds {

    /// What macOS will actually put on a desktop. `webp` is on the list because Omarchy's own
    /// backgrounds are mostly webp now and ImageIO has read them since Big Sur.
    public static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp",
    ]

    /// The image files in a backgrounds directory, in cycle order.
    ///
    /// Sorted with a plain `sorted()` — codepoint order, the same choice `Config.parse` makes for
    /// `[binds]`, and for the same reason: `localizedStandardCompare` would give two people with
    /// the same folder a different cycle. Omarchy sorts with `sort -z`, which is also bytewise.
    ///
    /// The filter earns its place on `.DS_Store` alone, which turns up in every folder anyone has
    /// opened in Finder and would otherwise become a wallpaper that will not load. Dotfiles go
    /// with it, along with the `README` and `LICENSE` an Omarchy theme folder may bring.
    public static func list(_ names: [String]) -> [String] {
        names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            let ext = (name as NSString).pathExtension.lowercased()
            return extensions.contains(ext)
        }
        .sorted()
    }

    /// Upstream's own branding, which is in every theme's `backgrounds/` and is not a wallpaper
    /// anybody wants on a toe desktop: `omarchy.png` in some themes, `omarchy.webp` in others, and
    /// in both cases the OMARCHY wordmark on a flat ground.
    ///
    /// Filtered where a theme is *fetched* rather than where a folder is listed, deliberately. Not
    /// fetching it is toe declining to put another project's wordmark on your screen; refusing to
    /// list it would be toe overruling a file you had put there yourself, which is not its call.
    /// So a downloaded theme never has one, and a folder you assembled by hand is shown whole.
    public static func isUpstreamBranding(_ name: String) -> Bool {
        (name as NSString).deletingPathExtension.lowercased() == "omarchy"
    }

    /// `omarchy-theme-bg-next`, exactly: find where you are, step one on, wrap at the end.
    ///
    /// A name that is not in the list gives the first — which is what happens when the theme has
    /// changed under you, or the file has been deleted since it was chosen, and is better than
    /// refusing to cycle because the memo is stale.
    ///
    /// Omarchy's empty case paints solid black; toe has no way to do that through
    /// `setDesktopImageURL` without inventing an image, and no need to, because the `Background`
    /// level is left out of the menu entirely when there is nothing in it.
    public static func next(after current: String?, in files: [String]) -> String? {
        guard !files.isEmpty else { return nil }
        guard let current, let index = files.firstIndex(of: current) else { return files[0] }
        return files[(index + 1) % files.count]
    }
}
