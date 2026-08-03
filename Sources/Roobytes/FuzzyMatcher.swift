import Foundation

/// Case-insensitive subsequence fuzzy matcher with contiguous / boundary bonuses.
public enum FuzzyMatcher {
    /// Higher is better. Returns `nil` when `query` does not match as a subsequence of `target`.
    public static func score(query: String, target: String) -> Double? {
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        if q.isEmpty { return 0 }
        guard !t.isEmpty else { return nil }

        var ti = 0
        var score: Double = 0
        var consecutive = 0
        var matchedIndices: [Int] = []

        for qc in q {
            var found = false
            while ti < t.count {
                let idx = ti
                ti += 1
                if t[idx] == qc {
                    found = true
                    matchedIndices.append(idx)
                    // Contiguous run bonus.
                    if let prev = matchedIndices.dropLast().last, idx == prev + 1 {
                        consecutive += 1
                        score += 8 + Double(consecutive) * 4
                    } else {
                        consecutive = 0
                        score += 2
                    }
                    // Word / path boundary bonus (start, after `/`, `-`, `_`, space).
                    if idx == 0 || isBoundary(t[idx - 1]) {
                        score += 12
                    }
                    break
                }
            }
            if !found { return nil }
        }

        // Prefer shorter targets and earlier matches.
        score += 24 / Double(t.count + 1)
        if let first = matchedIndices.first {
            score += 10 / Double(first + 1)
        }
        return score
    }

    private static func isBoundary(_ c: Character) -> Bool {
        c == "/" || c == "-" || c == "_" || c == " " || c == "."
    }
}
