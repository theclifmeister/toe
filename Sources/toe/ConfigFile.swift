import Darwin
import Foundation

/// Writes the config file back.
///
/// toe reads your config; it writes it in exactly one place, for exactly one key — the theme the
/// quick menu just picked. Everything about this is arranged so that a menu click cannot cost you
/// a file you wrote by hand.
enum ConfigFile {

    /// Replaces the file's contents, atomically, following a symlink rather than replacing it.
    ///
    /// The symlink is the whole reason this is not `Data.write(to:options:.atomic)`. Keeping
    /// `~/.config/toe/toe.toml` as a link into a dotfiles repository is deliberately supported —
    /// `Coordinator.permissionWarning` uses `stat` and not `lstat` for precisely that reason — and
    /// an atomic write renames a temporary file over the *path*, which would quietly replace the
    /// link with a regular file and orphan the copy in the repository. So the link is resolved
    /// first and the rename happens over the real file, inside the real file's own directory,
    /// which is also what keeps the rename on one filesystem.
    ///
    /// The rename does replace the inode, so a config kept as a *hard* link loses the link. A
    /// symlink is what the README documents, and there is no way to be atomic and keep an inode
    /// at the same time.
    ///
    /// Returns false and logs on any failure; the caller then leaves the file alone.
    @discardableResult
    static func write(_ text: String, to url: URL) -> Bool {
        let target = url.resolvingSymlinksInPath()

        // Only ever a regular file. Cheap, and it is the check that keeps a link left somewhere
        // odd from turning a menu click into an overwrite of something that is not a config.
        var info = stat()
        guard lstat(target.path, &info) == 0 else {
            Log.error("config write: \(target.path): \(String(cString: strerror(errno)))")
            return false
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            Log.error("config write: \(target.path) is not a regular file, leaving it alone")
            return false
        }

        // The mode it already has, not one of ours. A config checked out of a dotfiles repository
        // is often 0644, and silently chmodding a file inside somebody's git repository would
        // show up as a diff they did not make. `permissionWarning` is what tells them when a mode
        // is actually dangerous; that division of labour stays.
        let mode = info.st_mode & 0o777

        guard let data = text.data(using: .utf8) else { return false }
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).\(getpid()).tmp")

        // O_EXCL and the mode in the one call, so the file can never exist for an instant with
        // permissions it should not have — `writeDefaultConfigIfMissing` spells out the same
        // reasoning for the file it creates on first run.
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else {
            Log.error("config write: \(temporary.path): \(String(cString: strerror(errno)))")
            return false
        }

        func abandon(_ what: String) -> Bool {
            Log.error("config write: \(what): \(String(cString: strerror(errno)))")
            close(fd)
            unlink(temporary.path)
            return false
        }

        var written = 0
        let ok: Bool = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while written < buffer.count {
                let n = Darwin.write(fd, base + written, buffer.count - written)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if n == 0 { return false }
                written += n
            }
            return true
        }
        guard ok else { return abandon("writing \(temporary.lastPathComponent)") }
        guard fsync(fd) == 0 else { return abandon("flushing \(temporary.lastPathComponent)") }
        close(fd)

        guard rename(temporary.path, target.path) == 0 else {
            let reason = String(cString: strerror(errno))
            unlink(temporary.path)
            Log.error("config write: renaming over \(target.path): \(reason)")
            return false
        }
        return true
    }
}
