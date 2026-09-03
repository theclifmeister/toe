import Foundation
import ToeCore

/// Where toe fetches themes from, and the only host it ever talks to.
///
/// Named in one place so there is one answer to "what does this thing contact". toe makes no
/// other network request of any kind: no telemetry, no update check, nothing at launch. The
/// catalogue is fetched when you open `Style › Theme` and at most once a day, and a theme is
/// downloaded only when you choose it.
enum Upstream {
    /// The numeric id rather than `basecamp/omarchy`, because the repository has been renamed
    /// once already and an id does not move.
    static let repository = "994093166"
    static let branch = "master"

    static var tree: URL {
        URL(string: "https://api.github.com/repositories/\(repository)/git/trees/\(branch)?recursive=1")!
    }

    static func file(theme slug: String, _ path: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/basecamp/omarchy/\(branch)/themes/\(slug)/\(path)")!
    }

    /// Every host toe is allowed to end up talking to. Checked after redirects rather than
    /// before, because the check that matters is where the bytes actually came from.
    static let allowedHosts: Set<String> = ["api.github.com", "raw.githubusercontent.com",
                                            "codeload.github.com", "objects.githubusercontent.com"]
}

/// The list of themes Omarchy publishes, fetched and remembered.
///
/// Cached next to the session, and read from there on the way up, so the list survives a restart
/// and works offline once it has been fetched once. A refresh never blocks anything: the menu
/// opens on the cache it already has, the request runs behind it, and what it finds is there the
/// next time you look.
final class ThemeCatalogue {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/catalogue.json")

    /// A day. The list changes when Omarchy adds a theme, which is not often, and the cost of
    /// being a day behind is one theme you cannot see yet.
    static let maxAge: TimeInterval = 24 * 60 * 60
    /// The tree of a repository this size is about 400 KB. Ten is not a limit anyone will meet;
    /// it is there so a redirect to something enormous cannot be read into memory.
    private static let sizeLimit = 10 << 20

    private(set) var catalogue: Catalogue?
    private(set) var isFetching = false
    /// Set when a fetch failed, so the next look tries again rather than waiting out the day.
    private var lastFailed = false

    /// Called on the main queue when the list changes.
    var onChange: (() -> Void)?

    init() {
        catalogue = Self.load()
    }

    var themes: [RemoteTheme] { catalogue?.themes ?? [] }

    /// Fetches the list if it is missing or a day old. Cheap and safe to call on every menu open.
    func refreshIfStale() {
        guard !isFetching else { return }
        if let catalogue, !catalogue.isStale(maxAge: Self.maxAge), !lastFailed { return }
        isFetching = true
        onChange?()

        var request = URLRequest(url: Upstream.tree)
        request.timeoutInterval = 15
        // GitHub refuses an unidentified client on some paths and rate-limits by IP; saying who
        // this is costs nothing and makes the request explicable at the far end.
        request.setValue("toe (macOS window manager)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                defer { self.onChange?() }

                if let error {
                    self.lastFailed = true
                    Log.error("themes: could not fetch the list: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let host = response?.url?.host, Upstream.allowedHosts.contains(host),
                      let data, data.count <= Self.sizeLimit
                else {
                    self.lastFailed = true
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    Log.error("themes: could not fetch the list (HTTP \(code))")
                    return
                }
                do {
                    let fresh = try Catalogue.parse(data)
                    self.catalogue = fresh
                    self.lastFailed = false
                    Self.save(fresh)
                    Log.info("themes: \(fresh.themes.count) available from Omarchy")
                } catch {
                    self.lastFailed = true
                    Log.error("themes: \(error)")
                }
            }
        }.resume()
    }

    // MARK: - The cache

    private static func load() -> Catalogue? {
        guard let data = try? Data(contentsOf: url), data.count <= sizeLimit else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let catalogue = try? decoder.decode(Catalogue.self, from: data),
              catalogue.version == Catalogue.currentVersion
        else { return nil }
        return catalogue
    }

    private static func save(_ catalogue: Catalogue) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(catalogue) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
