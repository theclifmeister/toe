import Foundation
import ToeCore

/// Puts the generated skill document where Claude Code looks for one, and takes it away again.
///
/// `~/.claude/skills/toe/SKILL.md` is another program's directory, so this writes exactly one
/// file into exactly one folder of its own and never touches anything beside it. Removing takes
/// the same file and then the folder *only if it is empty*, so anything a user has added next to
/// it — a reference file, a script the skill calls — survives toe changing its mind.
///
/// The document is generated, not shipped: see `SkillDocument` for why a committed copy would
/// be lying about the verb list within a release or two. That has a consequence worth knowing
/// here — the text names the binary that wrote it, so the copy `make run` builds writes a
/// document pointing at `build/ToeDev.app`, and installing from one copy leaves the other
/// reporting `stale`. That is the honest answer rather than an annoyance: the file really does
/// point at the other binary.
enum SkillStore {

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills")
        .appendingPathComponent(SkillDocument.directoryName)

    static var file: URL { directory.appendingPathComponent(SkillDocument.fileName) }

    /// What this copy of toe would write.
    static var text: String {
        SkillDocument.text(binary: AppIdentity.binaryPath, version: AppIdentity.version)
    }

    static func state() -> SkillReport {
        let onDisk = try? String(contentsOf: file, encoding: .utf8)
        return SkillReport(path: file.path,
                           installed: onDisk != nil,
                           // Compared whole rather than by a version stamp: the document is
                           // generated from the verb table, so "the same" is a question about
                           // its entire contents, and any stamp fine enough to answer it would
                           // be the contents again.
                           stale: onDisk != nil && onDisk != text)
    }

    @discardableResult
    static func install() -> Result<SkillReport, Refusal> {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            Log.info("skill: wrote \(file.path)")
            return .success(state())
        } catch {
            let message = "could not write \(file.path): \(error.localizedDescription)"
            Log.error("skill: \(message)")
            return .failure(Refusal(message))
        }
    }

    @discardableResult
    static func remove() -> Result<SkillReport, Refusal> {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return .failure(Refusal("nothing to remove — \(file.path) is not there"))
        }
        do {
            try FileManager.default.removeItem(at: file)
            // Only when it is empty, and only ours: `~/.claude/skills/toe` is toe's folder, but
            // somebody may have put something in it, and a removal that took their file with it
            // would be a surprise nobody could have anticipated from a menu row called Remove.
            if let left = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
               left.isEmpty {
                try? FileManager.default.removeItem(at: directory)
            }
            Log.info("skill: removed \(file.path)")
            return .success(state())
        } catch {
            let message = "could not remove \(file.path): \(error.localizedDescription)"
            Log.error("skill: \(message)")
            return .failure(Refusal(message))
        }
    }
}
