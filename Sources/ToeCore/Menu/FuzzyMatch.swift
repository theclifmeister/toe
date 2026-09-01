import Foundation

/// walker's filter, near enough: a case-insensitive subsequence match with a score, so typing
/// `sf` finds Safari before it finds "Transfer files".
public enum FuzzyMatch {

    public struct Result: Equatable {
        public let score: Int
        /// Which characters of the candidate matched, for bold highlighting in the view.
        public let offsets: [Int]
    }

    // Scoring weights. Small integers rather than doubles so tests can assert exact orderings.
    private static let wordStartBonus = 12
    private static let consecutiveBonus = 8
    private static let prefixBonus = 10
    private static let gapPenalty = 1
    private static let leadingGapPenalty = 2

    /// Greedy left-to-right match. Not optimal-alignment scoring, which for menu titles of a
    /// handful of words buys nothing you can see and costs a table per keystroke.
    public static func score(_ query: String, in candidate: String) -> Result? {
        guard !query.isEmpty else { return Result(score: 0, offsets: []) }

        let haystack = Array(candidate)
        let lowerHaystack = haystack.map { Character($0.lowercased()) }
        let needle = Array(query.lowercased())

        var offsets: [Int] = []
        var score = 0
        var position = 0
        var previousMatch = -1

        for target in needle {
            guard target != " " else { continue }   // spaces in a query never have to match
            var found = -1
            var index = position
            while index < lowerHaystack.count {
                if lowerHaystack[index] == target { found = index; break }
                index += 1
            }
            guard found >= 0 else { return nil }

            if found == previousMatch + 1 {
                score += previousMatch >= 0 ? consecutiveBonus : 0
            } else {
                let gap = found - max(previousMatch, 0)
                score -= (previousMatch < 0 ? leadingGapPenalty : gapPenalty) * gap
            }
            if isWordStart(haystack, found) { score += wordStartBonus }
            if found == 0 { score += prefixBonus }

            offsets.append(found)
            previousMatch = found
            position = found + 1
        }

        guard !offsets.isEmpty else { return Result(score: 0, offsets: []) }
        // Shorter candidates win ties: "Nord" should beat "Nordic something" for `nord`.
        score -= haystack.count / 8
        return Result(score: score, offsets: offsets)
    }

    private static func isWordStart(_ chars: [Character], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        if previous == " " || previous == "-" || previous == "_" || previous == "." || previous == "/" {
            return true
        }
        // camelCase, so `mw` finds "macWindow".
        return previous.isLowercase && chars[index].isUppercase
    }

    /// Filters and orders a level. Keywords can match but score below the title and contribute no
    /// offsets, so an entry found by a keyword shows no highlighting rather than misleading
    /// highlighting.
    ///
    /// Stable: entries with equal scores keep their original order, which is what makes the
    /// selftest's assertions deterministic and what keeps `Workspace 1…10` in numeric order.
    public static func rank(_ query: String, _ entries: [MenuEntry]) -> [MenuRow] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return entries.map { MenuRow(entry: $0, offsets: []) }
        }

        var scored: [(row: MenuRow, score: Int, order: Int)] = []
        for (order, entry) in entries.enumerated() {
            if let hit = score(query, in: entry.title) {
                scored.append((MenuRow(entry: entry, offsets: hit.offsets), hit.score, order))
                continue
            }
            let best = entry.keywords.compactMap { score(query, in: $0)?.score }.max()
            if let best {
                scored.append((MenuRow(entry: entry, offsets: []), best - wordStartBonus, order))
            }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .map(\.row)
    }
}
