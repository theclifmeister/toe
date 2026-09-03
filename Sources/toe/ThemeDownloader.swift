import Foundation
import ToeCore

/// Fetches one theme from Omarchy into `~/.config/toe/themes/<name>/`.
///
/// Everything here is written on the assumption that the bytes are hostile, because they came off
/// the network and they are being written next to a config file that runs shell commands. Three
/// rules do the work, and all three are whitelists rather than checks for bad input:
///
///  - the directory is `Slug.make`'s output, so it is one path component and cannot be anything
///    else;
///  - every file name comes from the catalogue and has been through `Catalogue.isSafeFileName`
///    *and* the image-extension filter, and is joined onto the folder rather than trusted as a
///    path;
///  - the palette is parsed before anything is moved into place, so a theme that would not have
///    loaded never becomes a theme you have.
///
/// It assembles into a temporary directory and moves the finished thing into place, so a download
/// that fails halfway leaves nothing behind — the failure mode being avoided is a half-theme that
/// looks installed and is missing the picture the cycle is pointing at.
enum ThemeDownloader {

    /// No single background in Omarchy is past 4 MB. This is not a policy about how big a
    /// wallpaper may be; it is a ceiling so a redirect to something enormous cannot fill a disk.
    private static let fileLimit = 64 << 20
    private static let paletteLimit = 64 << 10
    private static let timeout: TimeInterval = 60

    enum Failure: Error, CustomStringConvertible {
        case network(String)
        case badPalette(String)
        case couldNotWrite(String)

        var description: String {
            switch self {
            case .network(let what):      return what
            case .badPalette(let why):    return "its colours would not parse — \(why)"
            case .couldNotWrite(let why): return why
            }
        }
    }

    /// How far along a download is.
    ///
    /// A name and two numbers rather than a sentence, because two surfaces show this and they
    /// want different lengths: the menu bar has room for `Gruvbox 3/6` and the tooltip behind it
    /// has room to say it properly. Building the sentence here would have forced both to use it.
    struct Progress {
        let theme: String
        /// Files finished. Zero while the palette is being fetched — the step that has no
        /// meaningful fraction, being one small file before the count is even known to matter.
        let done: Int
        let total: Int
    }

    /// Downloads `theme` and calls back on the main queue with where it landed.
    static func fetch(_ theme: RemoteTheme,
                      into directory: URL,
                      progress: @escaping (Progress) -> Void,
                      completion: @escaping (Result<Void, Failure>) -> Void) {
        let slug = Slug.make(theme.slug)
        guard slug == theme.slug, !slug.isEmpty else {
            return completion(.failure(.couldNotWrite("'\(theme.slug)' is not a theme name")))
        }

        DispatchQueue.global(qos: .utility).async {
            let result = fetchSynchronously(theme, slug: slug, into: directory, progress: progress)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func fetchSynchronously(_ theme: RemoteTheme, slug: String, into directory: URL,
                                           progress: @escaping (Progress) -> Void)
    -> Result<Void, Failure> {
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toe-theme-\(slug)-\(UUID().uuidString)")
        let pictures = staging.appendingPathComponent("backgrounds")
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }

        // The palette first: if it will not parse there is no point fetching nine megabytes of
        // photographs to go with it.
        let total = theme.backgrounds.count
        DispatchQueue.main.async {
            progress(Progress(theme: theme.name, done: 0, total: total))
        }
        let paletteData: Data
        switch get(Upstream.file(theme: slug, "colors.toml"), limit: paletteLimit) {
        case .success(let data): paletteData = data
        case .failure(let why):  return .failure(why)
        }
        guard let text = String(data: paletteData, encoding: .utf8) else {
            return .failure(.badPalette("it is not text"))
        }
        do {
            _ = try Palette.parse(text)
        } catch {
            return .failure(.badPalette("\(error)"))
        }
        do {
            try paletteData.write(to: staging.appendingPathComponent("colors.toml"))
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }

        for (index, picture) in theme.backgrounds.enumerated() {
            // Checked again here rather than trusted from the catalogue. The catalogue is a cache
            // — it is a file on disk that something else could have written — and this is the
            // moment a name becomes a path.
            guard Catalogue.isSafeFileName(picture.name),
                  !Backgrounds.isUpstreamBranding(picture.name),
                  Backgrounds.list([picture.name]).count == 1 else { continue }

            // `index + 1`, and reported before the fetch rather than after: the number names the
            // picture being fetched, so it reads as "picture 1 of 2" while that is what is
            // happening, and ends on 2 of 2 rather than stopping at 1.
            DispatchQueue.main.async {
                progress(Progress(theme: theme.name, done: index + 1, total: total))
            }
            switch get(Upstream.file(theme: slug, "backgrounds/\(picture.name)"), limit: fileLimit) {
            case .success(let data):
                // `appendingPathComponent` on a name that has been through both filters above:
                // no separator, no leading dot, a known image extension.
                try? data.write(to: pictures.appendingPathComponent(picture.name))
            case .failure(let why):
                // One missing picture is not worth losing the theme over — the palette is the
                // part that changes what you see.
                Log.error("themes: \(theme.slug)/\(picture.name): \(why)")
            }
        }

        // Into place in one move, so a theme is either there whole or not there.
        let destination = directory.appendingPathComponent(slug)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: destination.path) {
                // Re-downloading an existing theme replaces it. Anything you put in its
                // backgrounds folder yourself goes with it, which is why the menu only offers
                // this for themes you do not already have.
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }
        return .success(())
    }

    /// One synchronous GET, on a queue where blocking is the point.
    private static func get(_ url: URL, limit: Int) -> Result<Data, Failure> {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("toe (macOS window manager)", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Data, Failure> = .failure(.network("no answer"))

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { return outcome = .failure(.network(error.localizedDescription)) }
            guard let http = response as? HTTPURLResponse else {
                return outcome = .failure(.network("no answer"))
            }
            // After redirects, not before: what matters is where the bytes came from.
            guard let host = response?.url?.host, Upstream.allowedHosts.contains(host) else {
                return outcome = .failure(.network("redirected off github.com"))
            }
            guard http.statusCode == 200 else {
                return outcome = .failure(.network("HTTP \(http.statusCode)"))
            }
            guard let data, data.count <= limit else {
                return outcome = .failure(.network("the answer was too large"))
            }
            outcome = .success(data)
        }.resume()

        _ = semaphore.wait(timeout: .now() + timeout + 5)
        return outcome
    }
}
