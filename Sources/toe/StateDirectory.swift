import Darwin
import Foundation

/// `~/.local/state/toe` — the one directory everything that outlives the process is kept in:
/// the journals, the session snapshot, the theme catalogue, the control socket.
///
/// One creator rather than one per file, for two reasons. The mode: the socket in here is an
/// entry point into a process that writes window frames over Accessibility, so the directory
/// is `0700` — and `createDirectory(withIntermediateDirectories:)` on a directory that already
/// exists neither fails nor touches its mode, so a request for `0700` made *after* a journal or
/// `session.json` first made the directory under the umask is a no-op. Every install that ran a
/// toe before 0.22 has a `755` state directory for exactly that reason, which is why `ensure`
/// sets the mode on an existing directory as well as a new one.
///
/// The failure: every writer used to be `try? createDirectory; try? write`, and the journals
/// then made their global change whether or not the record had landed. A `~/.local/state` owned
/// by root after a `sudo` made it, a full disk, a home on a read-only volume — each left
/// `Ctrl`+`↑` dead after a `kill -9` with nothing on disk or in the log to say why. The answer
/// to a directory that cannot be made is here, once, and it is logged.
enum StateDirectory {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe")

    /// Whether the failure has been said already. It is said once per process rather than on
    /// every write, because `SessionStore.save` runs on every layout change and a directory
    /// that could not be made a moment ago has not usually been made since.
    private static var reported = false

    /// Makes the directory, `0700`, and answers whether it is there to be written into. A
    /// caller that gets `false` has nothing to do with the file it was about to write: the
    /// reason is already in the log, and repeating it per file would drown it.
    static func ensure() -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            if !reported {
                reported = true
                Log.error("state: could not make \(url.path): \(error.localizedDescription) — "
                          + "nothing that outlives the process is being written")
            }
            return false
        }
        // For the directory that was already there — see above. Not a reason to refuse the
        // write: a filesystem that will not take a mode still takes the file, and a directory
        // toe does not own fails at the write, which reports itself. It is a reason to say so.
        if chmod(url.path, 0o700) != 0, !reported {
            reported = true
            Log.error("state: could not make \(url.path) private: \(String(cString: strerror(errno)))")
        }
        return true
    }
}
