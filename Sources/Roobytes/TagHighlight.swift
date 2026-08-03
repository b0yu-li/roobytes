import Foundation

/// `#tag` / `#nested/tag` spans in a line of text.
public enum TagHighlight {
    /// UTF-16 ranges of `#tag` runs (includes the leading `#`).
    public static func ranges(in line: String) -> [NSRange] {
        let ns = line as NSString
        let len = ns.length
        var out: [NSRange] = []
        var i = 0
        while i < len {
            guard ns.character(at: i) == hash else {
                i += 1
                continue
            }
            // Word boundary before `#` (start, whitespace, or punctuation — not alnum/_).
            if i > 0 {
                let prev = ns.character(at: i - 1)
                if isTagBodyChar(prev) || prev == hash { // `##` heading ticks / `foo#bar`
                    i += 1
                    continue
                }
            }
            guard i + 1 < len, isTagStartChar(ns.character(at: i + 1)) else {
                i += 1
                continue
            }
            var end = i + 1
            while end + 1 < len, isTagBodyChar(ns.character(at: end + 1)) {
                end += 1
            }
            // Trailing `/` is not part of a tag.
            while end > i, ns.character(at: end) == slash {
                end -= 1
            }
            if end > i {
                let range = NSRange(location: i, length: end - i + 1)
                if hasNonNumericBody(ns, range) {
                    out.append(range)
                }
                i = end + 1
            } else {
                i += 1
            }
        }
        return out
    }

    private static let hash: unichar = 0x23 // #
    private static let slash: unichar = 0x2F // /

    /// `#1` / `#2026` are ordinals, not tags — a tag body needs one non-digit.
    private static func hasNonNumericBody(_ ns: NSString, _ range: NSRange) -> Bool {
        for offset in 1 ..< range.length {
            let c = ns.character(at: range.location + offset)
            if c < 0x30 || c > 0x39 { return true }
        }
        return false
    }

    private static func isTagStartChar(_ c: unichar) -> Bool {
        (c >= 0x41 && c <= 0x5A) // A-Z
            || (c >= 0x61 && c <= 0x7A) // a-z
            || (c >= 0x30 && c <= 0x39) // 0-9
            || c == 0x5F // _
    }

    private static func isTagBodyChar(_ c: unichar) -> Bool {
        isTagStartChar(c) || c == 0x2D /* - */ || c == slash
    }
}
