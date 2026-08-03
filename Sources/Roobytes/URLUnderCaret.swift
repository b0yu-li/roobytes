import Foundation

/// Resolve an `http`/`https` URL under a markdown caret (bare URL or `[label](url)`).
public enum URLUnderCaret {
    /// Column is UTF-16 (matches `MarkdownBridge.MarkdownCaret.column`).
    public static func url(in line: String, column: Int) -> URL? {
        let ns = line as NSString
        let len = ns.length
        guard len > 0 else { return nil }
        let col = max(0, min(column, len))

        if let fromLink = markdownLinkURL(in: ns, column: col) {
            return fromLink
        }
        return bareURL(in: ns, column: col)
    }

    /// All bare `http(s)://…` UTF-16 ranges in `line` (trailing punctuation stripped).
    public static func httpURLRanges(in line: String) -> [NSRange] {
        let ns = line as NSString
        let len = ns.length
        var ranges: [NSRange] = []
        var i = 0
        while i < len {
            if let match = bareHTTPRange(startingAt: i, in: ns) {
                ranges.append(match)
                i = NSMaxRange(match)
                continue
            }
            i += 1
        }
        return ranges
    }

    /// Markdown link spans: label + URL ranges for `[label](http…)`.
    public static func markdownLinkHighlightRanges(in line: String) -> [(label: NSRange, url: NSRange)] {
        let ns = line as NSString
        let len = ns.length
        var out: [(label: NSRange, url: NSRange)] = []
        var i = 0
        while i < len {
            guard ns.character(at: i) == openBracket else {
                i += 1
                continue
            }
            guard let labelEnd = indexOf(closeBracket, in: ns, from: i + 1) else {
                i += 1
                continue
            }
            guard labelEnd + 1 < len, ns.character(at: labelEnd + 1) == openParen else {
                i += 1
                continue
            }
            let urlStart = labelEnd + 2
            guard let urlEnd = indexOf(closeParen, in: ns, from: urlStart) else {
                i += 1
                continue
            }
            let raw = ns.substring(with: NSRange(location: urlStart, length: urlEnd - urlStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard httpURL(from: raw) != nil else {
                i = urlEnd + 1
                continue
            }
            let labelRange = NSRange(location: i + 1, length: max(0, labelEnd - (i + 1)))
            let urlRange = NSRange(location: urlStart, length: urlEnd - urlStart)
            out.append((labelRange, urlRange))
            i = urlEnd + 1
        }
        return out
    }

    // MARK: - Markdown links `[label](url)`

    private static func markdownLinkURL(in ns: NSString, column: Int) -> URL? {
        let len = ns.length
        var i = 0
        while i < len {
            guard ns.character(at: i) == openBracket else {
                i += 1
                continue
            }
            guard let labelEnd = indexOf(closeBracket, in: ns, from: i + 1) else {
                i += 1
                continue
            }
            guard labelEnd + 1 < len, ns.character(at: labelEnd + 1) == openParen else {
                i += 1
                continue
            }
            let urlStart = labelEnd + 2
            guard let urlEnd = indexOf(closeParen, in: ns, from: urlStart) else {
                i += 1
                continue
            }
            let spanStart = i
            let spanEnd = urlEnd
            if column >= spanStart, column <= spanEnd {
                let raw = ns.substring(with: NSRange(location: urlStart, length: urlEnd - urlStart))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = httpURL(from: raw) {
                    return url
                }
            }
            i = urlEnd + 1
        }
        return nil
    }

    // MARK: - Bare URLs

    private static func bareURL(in ns: NSString, column: Int) -> URL? {
        let len = ns.length
        let probe = min(column, len - 1)
        guard isURLChar(ns.character(at: probe)) || (column > 0 && isURLChar(ns.character(at: column - 1))) else {
            return nil
        }
        var start = probe
        if !isURLChar(ns.character(at: start)), column > 0, isURLChar(ns.character(at: column - 1)) {
            start = column - 1
        }
        while start > 0, isURLChar(ns.character(at: start - 1)) {
            start -= 1
        }
        guard let range = bareHTTPRange(startingAt: start, in: ns) else { return nil }
        let raw = ns.substring(with: range)
        return httpURL(from: raw)
    }

    /// If `start` begins an `http(s)://` run, return its trimmed UTF-16 range.
    private static func bareHTTPRange(startingAt start: Int, in ns: NSString) -> NSRange? {
        let len = ns.length
        guard start < len else { return nil }
        let https = "https://" as NSString
        let http = "http://" as NSString
        let schemeLen: Int
        if ns.length - start >= https.length,
           ns.substring(with: NSRange(location: start, length: https.length)) == (https as String)
        {
            schemeLen = https.length
        } else if ns.length - start >= http.length,
                  ns.substring(with: NSRange(location: start, length: http.length)) == (http as String)
        {
            schemeLen = http.length
        } else {
            return nil
        }
        var end = start + schemeLen - 1
        while end + 1 < len, isURLChar(ns.character(at: end + 1)) {
            end += 1
        }
        var raw = ns.substring(with: NSRange(location: start, length: end - start + 1))
        var trimmedLen = (raw as NSString).length
        while trimmedLen > schemeLen {
            let last = (raw as NSString).character(at: trimmedLen - 1)
            let c = Character(UnicodeScalar(last)!)
            if trailingTrim.contains(c) {
                trimmedLen -= 1
                raw = (raw as NSString).substring(to: trimmedLen)
            } else {
                break
            }
        }
        guard httpURL(from: raw) != nil else { return nil }
        return NSRange(location: start, length: trimmedLen)
    }

    private static func httpURL(from raw: String) -> URL? {
        guard raw.hasPrefix("http://") || raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    private static func isURLChar(_ utf16: unichar) -> Bool {
        if utf16 > 0x7F { return false }
        let c = Character(UnicodeScalar(utf16)!)
        if c.isWhitespace { return false }
        if delimiters.contains(c) { return false }
        return true
    }

    private static func indexOf(_ target: unichar, in ns: NSString, from: Int) -> Int? {
        var i = from
        let len = ns.length
        while i < len {
            if ns.character(at: i) == target { return i }
            i += 1
        }
        return nil
    }

    private static let openBracket: unichar = 0x5B // [
    private static let closeBracket: unichar = 0x5D // ]
    private static let openParen: unichar = 0x28 // (
    private static let closeParen: unichar = 0x29 // )
    private static let delimiters: Set<Character> = ["<", ">", "\"", "'", " ", "\t", "\n", "\r"]
    private static let trailingTrim: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "]", ">", "}", "\"", "'"]
}
