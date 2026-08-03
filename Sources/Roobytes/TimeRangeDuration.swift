import Foundation

/// Auto-duration for `HH:MM - HH:MM (` → insert `N'` + `)`.
public enum TimeRangeDuration {
    /// Given paragraph text ending in `(`, return the minutes suffix to insert (e.g. `"93')"`), or nil.
    public static func insertion(afterTypingOpenParenIn prefixIncludingParen: String) -> String? {
        guard prefixIncludingParen.hasSuffix("(") else { return nil }
        let before = String(prefixIncludingParen.dropLast())
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*$"#
        ) else { return nil }
        let ns = before as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: before, options: [], range: full),
              match.numberOfRanges == 5
        else { return nil }

        func int(at i: Int) -> Int? {
            Int(ns.substring(with: match.range(at: i)))
        }
        guard let h1 = int(at: 1), let m1 = int(at: 2),
              let h2 = int(at: 3), let m2 = int(at: 4),
              (0...23).contains(h1), (0...59).contains(m1),
              (0...23).contains(h2), (0...59).contains(m2)
        else { return nil }

        var minutes = (h2 * 60 + m2) - (h1 * 60 + m1)
        if minutes < 0 {
            minutes += 24 * 60 // overnight wrap
        }
        return "\(minutes)')"
    }
}
