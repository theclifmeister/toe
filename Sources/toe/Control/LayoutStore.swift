import Foundation
import ToeCore

/// Reads and writes `~/.config/toe/layouts` — the named arrangements `toe layout save` keeps.
///
/// Under `.config` rather than `.local/state`, which is the opposite of where the session
/// snapshot lives, and deliberately. A session snapshot is toe's own bookkeeping: nobody names
/// it, nobody edits it, and it is worthless after a reboot. A profile is something the user
/// asked for by name, will want to keep, and may well want to hand-edit or put in a dotfiles
/// repository — that is the config directory's job, next to the themes.
///
/// The disk half of the split ToeCore keeps everywhere else: `LayoutProfile` is the shape and
/// the matching, this is the directory walking, exactly as `ThemeStore` is to `Theme`.
enum LayoutStore {

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/toe/layouts")

    /// A profile is a line or two per window. Anything past this is not one, and it is read
    /// before it is trusted — `SessionStore`'s reasoning, one directory over.
    private static let sizeLimit = 1 << 20

    /// The profiles there are, by name, sorted so a listing reads the same way twice running.
    static func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { Slug.make($0) == $0 }
            .sorted()
    }

    static func load(_ name: String) -> Result<LayoutProfile, Refusal> {
        guard let url = url(for: name) else { return .failure(Refusal(badName(name))) }
        guard let data = try? Data(contentsOf: url) else {
            let known = names()
            let suffix = known.isEmpty ? " — nothing has been saved yet"
                                       : " — there is \(known.joined(separator: ", "))"
            return .failure(Refusal("no layout called '\(name)'\(suffix)"))
        }
        guard data.count <= sizeLimit else {
            return .failure(Refusal("'\(name)' is implausibly large for a layout; refusing to read it"))
        }
        guard let profile = try? ControlCoding.decoder().decode(LayoutProfile.self, from: data) else {
            return .failure(Refusal("'\(name)' is not a layout toe can read"))
        }
        guard profile.version == LayoutProfile.currentVersion else {
            return .failure(Refusal("'\(name)' was written by a different version of toe"))
        }
        return .success(profile)
    }

    static func save(_ profile: LayoutProfile) -> Result<URL, Refusal> {
        guard let url = url(for: profile.name) else { return .failure(Refusal(badName(profile.name))) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try ControlCoding.encoder().encode(profile).write(to: url, options: .atomic)
            return .success(url)
        } catch {
            return .failure(Refusal("could not write \(url.path): \(error.localizedDescription)"))
        }
    }

    static func delete(_ name: String) -> Result<Void, Refusal> {
        guard let url = url(for: name) else { return .failure(Refusal(badName(name))) }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(Refusal("no layout called '\(name)'"))
        }
        do {
            try FileManager.default.removeItem(at: url)
            return .success(())
        } catch {
            return .failure(Refusal("could not remove \(url.path): \(error.localizedDescription)"))
        }
    }

    /// Through the slug, and refusing anything the slug changes — the same guard `removeTheme`
    /// puts between a name and a path join. This name arrives over a socket and is joined onto a
    /// directory that is about to be written to and deleted from, so a `/` or a `..` in it must
    /// not become part of the path. Rejecting rather than silently slugifying: a caller that
    /// asked for `../../x` should be told no, not handed a file called something else.
    private static func url(for name: String) -> URL? {
        guard !name.isEmpty, Slug.make(name) == name else { return nil }
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private static func badName(_ name: String) -> String {
        "'\(name)' is not a usable layout name — lower case, digits and hyphens, "
        + "so it can be a file name (try '\(Slug.make(name))')"
    }
}
