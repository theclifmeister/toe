import Foundation

/// The quick menu's type-to-filter, which is walker's.
///
/// A subsequence match rather than a substring one: `ecfg` finds "Edit configuration", because
/// what you remember about a menu item is its shape, not its spelling. Everything that does not
/// match at all is dropped — a launcher that keeps showing you rows you have just ruled out is
/// not filtering, it is sorting.
///
/// The scores below are arbitrary in the way every ranking is arbitrary; what matters is that
/// they are fixed here, where the selftest can pin them, rather than emerging from the order two
/// comparisons happen to run in.
public enum FuzzyFilter {

    public struct Match: Equatable, Sendable {
        public let index: Int
        public let score: Int
    }

    private static let prefixBonus = 100
    private static let boundaryBonus = 50
    private static let adjacentBonus = 10
    private static let skipPenalty = 1
    /// Charged against each field after the first, so a row whose *name* matches comes above one
    /// where the same letters turned up in its description. Enough to separate two equally good
    /// matches, not enough to bury a description match under a poor title one.
    private static let secondaryFieldPenalty = 25

    /// The candidates that match, best first. Stable: equal scores keep the order they came in,
    /// so an unfiltered menu is the menu, in the order it was written.
    public static func rank(_ query: String, in candidates: [String]) -> [Match] {
        rank(query, in: candidates.map { [$0] })
    }

    /// The same, with more than one string to match against per row — on the keybindings page the
    /// name is `SUPER + W` and what it does is the second field, and typing `close` has to find
    /// it. Fields are given most important first; the first one also breaks ties on length.
    public static func rank(_ query: String, in candidates: [[String]]) -> [Match] {
        let needle = fold(query)
        guard !needle.isEmpty else {
            return candidates.indices.map { Match(index: $0, score: 0) }
        }

        var matches: [(match: Match, length: Int)] = []
        for (index, fields) in candidates.enumerated() {
            // The best any one field can do, rather than the sum: a row does not become a better
            // answer for repeating itself.
            var best: Int?
            for (rank, field) in fields.enumerated() {
                guard !field.isEmpty, let score = score(needle, in: fold(field)) else { continue }
                let adjusted = score - rank * secondaryFieldPenalty
                if best == nil || adjusted > best! { best = adjusted }
            }
            guard let score = best else { continue }
            matches.append((Match(index: index, score: score), fields.first?.count ?? 0))
        }

        // Sorted on the score, then the shorter candidate — with two equal matches the tighter
        // one is the one you meant — then the original position, which is what makes this stable.
        matches.sort {
            if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.match.index < $1.match.index
        }
        return matches.map(\.match)
    }

    /// Case and accents folded away, so `é` matches `e` and `SETUP` matches `setup`.
    private static func fold(_ text: String) -> [Character] {
        Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    /// nil when the needle is not a subsequence of the haystack at all.
    private static func score(_ needle: [Character], in haystack: [Character]) -> Int? {
        var score = 0
        var h = 0
        var lastMatch: Int?

        for character in needle {
            var found: Int?
            while h < haystack.count {
                if haystack[h] == character { found = h; h += 1; break }
                h += 1
            }
            guard let at = found else { return nil }

            if at == 0 {
                score += prefixBonus
            } else if isBoundary(haystack[at - 1]) {
                score += boundaryBonus
            }
            if let previous = lastMatch, at == previous + 1 {
                score += adjacentBonus
            } else if let previous = lastMatch {
                score -= (at - previous - 1) * skipPenalty
            } else {
                score -= at * skipPenalty
            }
            lastMatch = at
        }
        return score
    }

    private static func isBoundary(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "_" || character == "/" || character == "."
    }
}
