import Foundation

/// One file that can be fetched.
public struct RemoteFile: Codable, Equatable, Sendable {
    public let name: String
    public let bytes: Int

    public init(name: String, bytes: Int) {
        self.name = name
        self.bytes = bytes
    }
}

/// A theme that exists upstream but not on this machine.
public struct RemoteTheme: Codable, Equatable, Sendable {
    public let slug: String
    public let name: String
    public let backgrounds: [RemoteFile]

    public init(slug: String, name: String, backgrounds: [RemoteFile]) {
        self.slug = slug
        self.name = name
        self.backgrounds = backgrounds
    }

    /// What downloading it costs, palette included — near enough, since a palette is a rounding
    /// error beside a photograph. This is the number the menu row shows, and the reason it shows
    /// it is that the range runs from a third of a megabyte to nine.
    public var bytes: Int { backgrounds.reduce(0) { $0 + $1.bytes } }
}

/// Every theme Omarchy publishes, as of the last time toe asked.
public struct Catalogue: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var fetchedAt: Date
    public var themes: [RemoteTheme]

    public init(version: Int = Catalogue.currentVersion, fetchedAt: Date, themes: [RemoteTheme]) {
        self.version = version
        self.fetchedAt = fetchedAt
        self.themes = themes
    }

    public func isStale(now: Date = Date(), maxAge: TimeInterval) -> Bool {
        // A clock that has gone backwards — a restored machine, a corrected NTP step — reads as
        // stale rather than as fresh for however long the skew lasts.
        let age = now.timeIntervalSince(fetchedAt)
        return age < 0 || age > maxAge
    }
}

public enum CatalogueError: Error, CustomStringConvertible, Equatable {
    case notJSON
    case truncated
    case empty

    public var description: String {
        switch self {
        case .notJSON:   return "the theme list did not come back as JSON"
        case .truncated: return "the theme list came back incomplete"
        case .empty:     return "the theme list came back with no themes in it"
        }
    }
}

public extension Catalogue {

    /// Reads GitHub's recursive tree listing.
    ///
    /// One request describes the whole repository — every path, every blob size — so the menu can
    /// say what a theme costs to download without fetching anything first. That is the reason
    /// this shape was chosen over the contents API, which would be one request per theme.
    ///
    /// Pure, and given a real 400 KB response in the selftest, because everything that can go
    /// wrong here is a shape problem: a theme with no palette, a filename that is not a filename,
    /// a listing that came back truncated.
    static func parse(_ json: Data, fetchedAt: Date = Date()) throws -> Catalogue {
        struct Tree: Decodable {
            struct Entry: Decodable {
                let path: String
                let type: String
                let size: Int?
            }
            let tree: [Entry]
            let truncated: Bool?
        }

        guard let tree = try? JSONDecoder().decode(Tree.self, from: json) else {
            throw CatalogueError.notJSON
        }
        // GitHub truncates a tree that is too large to serve. Half a catalogue is worse than
        // none: it would look complete, and the themes missing from it would look nonexistent.
        if tree.truncated == true { throw CatalogueError.truncated }

        var palettes: Set<String> = []
        var backgrounds: [String: [RemoteFile]] = [:]

        for entry in tree.tree where entry.type == "blob" {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
                                  .map(String.init)
            guard parts.count >= 3, parts[0] == "themes" else { continue }
            // Through the slug, not taken as read: this is a name from the network that ends up
            // as a directory under ~/.config/toe/themes, and a path component is the one thing it
            // is allowed to be. A directory whose name is not already a slug is not a theme.
            let slug = parts[1]
            guard Slug.make(slug) == slug else { continue }

            if parts.count == 3, parts[2] == "colors.toml" {
                palettes.insert(slug)
            } else if parts.count == 4, parts[2] == "backgrounds",
                      isSafeFileName(parts[3]),
                      !Backgrounds.isUpstreamBranding(parts[3]),
                      Backgrounds.list([parts[3]]).count == 1 {
                backgrounds[slug, default: []].append(
                    RemoteFile(name: parts[3], bytes: entry.size ?? 0))
            }
        }

        // A theme without a palette is not one toe can use — Omarchy has a few that describe
        // themselves only through per-app config files it renders templates from, and toe has no
        // analogue for any of those.
        let themes = palettes.sorted().map { slug in
            RemoteTheme(slug: slug, name: Slug.title(slug),
                        backgrounds: (backgrounds[slug] ?? []).sorted { $0.name < $1.name })
        }
        guard !themes.isEmpty else { throw CatalogueError.empty }
        return Catalogue(fetchedAt: fetchedAt, themes: themes)
    }

    /// Whether a name off the network may be written to disk.
    ///
    /// Deliberately a whitelist of shapes rather than a search for bad ones: this name is about to
    /// be joined onto a directory path, and "does not contain `..`" is the kind of rule that is
    /// one encoding trick away from being wrong. A separator, a dot-leading name, an empty one and
    /// anything overlong are all simply not names toe will write.
    static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        guard !name.hasPrefix(".") else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { return false }
        guard name != ".", name != ".." else { return false }
        return true
    }
}

/// A byte count as a menu row shows it.
public enum ByteSize {
    public static func describe(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_048_576
        if mb >= 0.1 { return String(format: "%.1f MB", mb) }
        let kb = max(1, Int((Double(bytes) / 1024).rounded()))
        return "\(kb) KB"
    }
}
