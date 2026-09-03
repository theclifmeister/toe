import Foundation

/// How far along the theme currently being fetched is, as the menu row drawing it needs it.
///
/// Lives here rather than in `ThemeDownloader` because this is the part with arithmetic in it —
/// `BorderGeometry`'s reason for existing, applied again. The downloader reports what has
/// arrived; turning that into a bar and a label is a decision, and a decision belongs where
/// `make test` can reach it.
///
/// **Bytes, not files.** The first version of this counted finished files — a theme with seven
/// pictures moved the bar in sevenths — and it was wrong in the way that mattered: the pictures
/// run from ten kilobytes to four megabytes, so the bar jumped through the small ones and then
/// sat still for as long as the largest took, which reads as a download that has stopped. The
/// catalogue knows every picture's size, so the bar is spent bytes over total bytes and moves at
/// something like the rate the download is actually going.
public struct ThemeDownload: Equatable, Sendable {

    /// Which theme, so the row that fills is the row you picked and not whichever one shares its
    /// position in a list that has since been rebuilt.
    public let slug: String
    /// The picture being fetched, counting from one — so `fetching` and `total` read as "picture
    /// 3 of 5", which is what the row's label says. Zero while the palette is being fetched,
    /// before any picture is in flight.
    public let fetching: Int
    /// Pictures the catalogue said this theme has.
    public let total: Int
    /// Bytes accounted for: every picture already finished with, plus what has arrived of the one
    /// in flight. "Finished with" rather than "successfully fetched" — a picture toe skipped or
    /// failed on counts too, because the bar measures progress through the work rather than
    /// bytes on the disk, and a bar that could never reach its end because one picture 404'd
    /// would be the original complaint again in a rarer costume.
    public let bytesDone: Int
    /// What the catalogue said the pictures add up to. The palette is not in here: it is under a
    /// kilobyte against megabytes of photographs, and giving it a share of the bar it could not
    /// visibly fill only moved the arithmetic further from what the eye sees.
    public let bytesTotal: Int

    public init(slug: String, fetching: Int, total: Int, bytesDone: Int, bytesTotal: Int) {
        self.slug = slug
        self.fetching = max(0, fetching)
        self.total = max(0, total)
        self.bytesDone = max(0, bytesDone)
        self.bytesTotal = max(0, bytesTotal)
    }

    /// 0…1, clamped.
    ///
    /// Clamped because both numbers come off the network: the catalogue's idea of a picture's
    /// size is a cached claim about somebody else's repository, and the count of bytes received
    /// is the transfer's own. They disagree by a little often and by a lot occasionally, and
    /// neither a bar running out of the panel nor one running backwards is worth being faithful
    /// to a bad number over.
    ///
    /// A theme with no pictures reads zero throughout. Its download is one small file and is over
    /// before the row could draw anything, so there is nothing a fraction could usefully say.
    public var fraction: Double {
        guard bytesTotal > 0 else { return 0 }
        return min(1, max(0, Double(bytesDone) / Double(bytesTotal)))
    }

    /// `3/5`, or nil while there is nothing to count — the palette step, and a theme that has no
    /// pictures at all. A row that said `0/0` would be a row asking to be read twice.
    ///
    /// The number names the picture *being fetched* rather than the last one finished, which is
    /// why it ends on `5/5` and not `4/5`: the label says what is happening and the bar says how
    /// much of it is done, so the two deliberately do not agree until the end.
    public var label: String? {
        guard total > 0, fetching > 0 else { return nil }
        return "\(fetching)/\(total)"
    }
}
