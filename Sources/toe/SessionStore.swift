import ColorSync
import CoreGraphics
import Darwin
import Foundation
import ToeCore

/// Reads and writes `~/.local/state/toe/session.json` — the layout toe puts back when it
/// starts. Next to the symbolic-hotkey journal, and for the same reason: state that has to
/// outlive the process belongs on disk, not in a preference.
///
/// The snapshot names windows by `CGWindowID`, which the window server keeps stable for the
/// life of the window, so a restart with the applications still running restores exactly. A
/// reboot renumbers everything, and a stale file would then scatter windows into workspaces
/// belonging to whatever now holds those numbers — `bootToken` is what stops that, and it is
/// a fact rather than an expiry guess: the ids are valid for precisely as long as the boot
/// they were issued in.
enum SessionStore {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/session.json")

    /// A snapshot is a few hundred bytes per window. Anything past this is not something toe
    /// wrote, and it is read before it is trusted.
    private static let sizeLimit = 1 << 20   // 1 MiB — thousands of windows' worth

    // MARK: - Reading

    static func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard data.count <= sizeLimit else {
            Log.error("session: \(url.lastPathComponent) is implausibly large, ignoring it")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else {
            Log.error("session: could not read \(url.lastPathComponent), starting fresh")
            return nil
        }

        guard snapshot.version == SessionSnapshot.currentVersion else {
            Log.info("session: written by a different version of toe, starting fresh")
            return nil
        }
        guard snapshot.boot == bootToken else {
            // Expected after every reboot, and not a problem — say so at info, not error.
            Log.info("session: from a previous boot, starting fresh")
            return nil
        }
        return snapshot
    }

    // MARK: - Writing

    static func save(_ snapshot: SessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // Atomically: toe is very often written to on the way out, and a half-written file
        // read back at the next launch is exactly the state this is meant to avoid.
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("session: could not write \(url.lastPathComponent): \(error)")
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Identity

    /// Identifies the boot the window ids were issued in. `kern.boottime` is set once by the
    /// kernel and never moves, so it is stable within a boot and different across one.
    static let bootToken: String = {
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0 else {
            // Unreachable in practice. A token nothing can match means the snapshot is never
            // restored, which is the safe direction to fail in.
            return "unknown-\(UUID().uuidString)"
        }
        return "\(value.tv_sec).\(value.tv_usec)"
    }()

    /// A name for a display that survives a replug. `CGDirectDisplayID` does not: it is
    /// handed out per connection, so the same monitor can come back as a different number and
    /// its workspaces would be homed onto the wrong screen.
    static func monitorKey(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string
    }
}
