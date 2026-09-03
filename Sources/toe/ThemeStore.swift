import Foundation
import ToeCore

/// Reads `~/.config/toe/themes` — the themes you have added, and the pictures the one in effect
/// carries.
///
/// The disk half of the split ToeCore keeps everywhere else: `Theme` and `Palette` are the shapes
/// and the parsing, this is the directory walking, exactly as `Session` is to `SessionStore`.
///
/// A theme is a folder and nothing has to be registered: `<name>/colors.toml` in Omarchy's own
/// format, optionally `<name>/backgrounds/`. That is deliberately the same shape as an Omarchy
/// theme directory, so one can be copied across whole — and it is the shape `ThemeDownloader`
/// writes into, so a theme toe fetched and a theme you copied in are the same thing afterwards,
/// with nothing to tell them apart and nothing that treats them differently.
enum ThemeStore {

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/toe/themes")

    /// Twenty-two hex strings is a few hundred bytes. Anything past this is not a palette, and
    /// it is read before it is trusted — `SessionStore.sizeLimit`'s reasoning, one file over.
    private static let sizeLimit = 64 << 10

    /// What is there, by name only.
    ///
    /// Opens nothing. This is called every time the quick menu opens — which is what makes a
    /// folder you created a second ago appear without a reload — and someone who has copied an
    /// Omarchy theme collection across has ninety of them. Reading and parsing ninety
    /// `colors.toml` files to draw a list is the version of this that does not ship; only the
    /// theme actually in effect is ever read, by `theme(named:)` below.
    static func installed() -> [ThemeRef] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []

        return names.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return nil }
            // Through the slug rather than taken as read: this name came off a filesystem, and
            // everything downstream — the config line it is written into, the path it is joined
            // back onto — expects a slug. A directory whose name is not one is not a theme.
            let slug = Slug.make(url.lastPathComponent)
            guard slug == url.lastPathComponent else { return nil }
            return ThemeRef(slug: slug, name: Slug.title(slug))
        }
    }

    /// The one theme that is actually in effect, read now.
    ///
    /// A broken `colors.toml` is discovered when you *choose* that theme rather than when you
    /// merely have it, which is the better direction: you hear about the theme you picked, not
    /// about the eighteen you did not.
    static func theme(named slug: String) -> Result<Theme, Error> {
        let file = directory.appendingPathComponent(slug).appendingPathComponent("colors.toml")
        // Read, not mapped. `SessionStore` maps `session.json` because it can run to a megabyte;
        // a palette is twenty-two hex strings. And mapping this one is actively wrong: the file
        // is watched, `loadConfig` reads it with the watch already armed, and the mapping trips
        // NOTE_ATTRIB on the vnode — so the read re-fires the watch that caused it and toe reloads
        // its config six times a second for as long as a theme is set. `toe.toml` escapes the same
        // trap only by being read with a plain `String(contentsOf:)`.
        if let data = try? Data(contentsOf: file) {
            guard data.count <= sizeLimit else {
                return .failure(ThemeStoreError.tooLarge(slug))
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(ThemeStoreError.notText(slug))
            }
            do {
                return .success(Theme(slug: slug, name: Slug.title(slug),
                                      palette: try Palette.parse(text)))
            } catch {
                return .failure(error)
            }
        }
        return .failure(ThemeStoreError.noSuchTheme(slug))
    }

    /// `<name>/backgrounds`, in cycle order.
    ///
    /// Whatever is in the folder, whether it arrived by download or because you put it there.
    static func backgrounds(named slug: String) -> [String] {
        guard !slug.isEmpty else { return [] }
        let folder = directory.appendingPathComponent(slug).appendingPathComponent("backgrounds")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Backgrounds.list(names)
    }

    static func background(named file: String, in slug: String) -> URL {
        directory.appendingPathComponent(slug)
            .appendingPathComponent("backgrounds")
            .appendingPathComponent(file)
    }
}

enum ThemeStoreError: Error, CustomStringConvertible {
    case noSuchTheme(String)
    case tooLarge(String)
    case notText(String)

    var description: String {
        switch self {
        case .noSuchTheme(let slug): return "there is no theme called '\(slug)'"
        case .tooLarge(let slug):    return "\(slug)/colors.toml is too large to be a palette"
        case .notText(let slug):     return "\(slug)/colors.toml is not UTF-8 text"
        }
    }
}
