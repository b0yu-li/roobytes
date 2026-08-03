import Foundation

/// Unique words from the current note buffer — LazyVim / blink `buffer` source, RAM-capped.
///
/// Stores at most `maxUniqueWords` first-seen spellings (no per-occurrence lists).
public struct BufferWordIndex: Sendable {
    public static let maxUniqueWords = 4096
    public static let minPrefixLength = 2
    public static let maxCandidates = 8
    /// Prefer these when present so short fluff (`sum`, `well`) doesn’t beat `successful`.
    public static let minUsefulWordLength = 6

    /// First-seen display forms in document order.
    private var ordered: [String] = []
    /// Lowercased → index in `ordered`.
    private var lowerToIndex: [String: Int] = [:]

    public init() {}

    public var count: Int { ordered.count }

    public mutating func removeAll() {
        ordered = []
        lowerToIndex = [:]
    }

    /// Full rebuild from note text. Caps at `maxUniqueWords`.
    public mutating func rebuild(from text: String) {
        removeAll()
        for word in Self.tokenize(text) {
            let lower = word.lowercased()
            if lowerToIndex[lower] != nil { continue }
            if ordered.count >= Self.maxUniqueWords { break }
            lowerToIndex[lower] = ordered.count
            ordered.append(word)
        }
    }

    /// Prefix matches longer than `prefix`, excluding the token currently under the caret.
    /// Rank: useful long words first, then longer / more remaining chars, then earlier first-seen.
    public func candidates(
        matchingPrefix prefix: String,
        excluding excluded: String? = nil
    ) -> [String] {
        guard prefix.count >= Self.minPrefixLength else { return [] }
        let p = prefix.lowercased()
        let excl = excluded.map { $0.lowercased() }

        var hits: [(word: String, idx: Int)] = []
        for (i, word) in ordered.enumerated() {
            let lower = word.lowercased()
            if let excl, lower == excl { continue }
            guard lower.hasPrefix(p), lower.count > p.count else { continue }
            hits.append((word, i))
        }
        guard !hits.isEmpty else { return [] }

        // When longer “hard” words exist, drop short completions that aren’t worth Tab.
        let useful = hits.filter { $0.word.count >= Self.minUsefulWordLength }
        let pool = useful.isEmpty ? hits : useful

        let ranked = pool.sorted { lhs, rhs in
            let lRem = lhs.word.count - p.count
            let rRem = rhs.word.count - p.count
            if lhs.word.count != rhs.word.count {
                return lhs.word.count > rhs.word.count
            }
            if lRem != rRem { return lRem > rRem }
            if lhs.idx != rhs.idx { return lhs.idx < rhs.idx }
            return lhs.word < rhs.word
        }
        return Array(ranked.prefix(Self.maxCandidates).map(\.word))
    }

    /// How the completion will read after accept: keep typed prefix casing, append candidate tail.
    public static func displayForm(candidate: String, prefix: String) -> String {
        guard let suffix = ghostSuffix(candidate: candidate, prefix: prefix) else {
            return candidate
        }
        return prefix + suffix
    }

    /// Ghost suffix for a selected candidate relative to the typed prefix.
    public static func ghostSuffix(candidate: String, prefix: String) -> String? {
        guard candidate.count > prefix.count else { return nil }
        let cLower = candidate.lowercased()
        let pLower = prefix.lowercased()
        guard cLower.hasPrefix(pLower) else { return nil }
        let drop = prefix.count
        return String(candidate.dropFirst(drop))
    }

    /// Word token under / ending at UTF-16 column in a single line.
    /// - Returns: `(prefix, startUTF16)` where prefix is `[startUTF16, utf16Column)`.
    public static func prefixAtCaret(line: String, utf16Column: Int) -> (prefix: String, startUTF16: Int)? {
        let ns = line as NSString
        let col = min(max(0, utf16Column), ns.length)
        var start = col
        while start > 0 {
            let c = ns.character(at: start - 1)
            if isWordUTF16(c) {
                start -= 1
            } else {
                break
            }
        }
        guard start < col else { return nil }
        let prefix = ns.substring(with: NSRange(location: start, length: col - start))
        return (prefix, start)
    }

    /// Full word spanning the caret (for exclusion), if any.
    public static func fullWordAtCaret(line: String, utf16Column: Int) -> String? {
        guard let (prefix, start) = prefixAtCaret(line: line, utf16Column: utf16Column) else {
            return nil
        }
        let ns = line as NSString
        var end = utf16Column
        while end < ns.length {
            let c = ns.character(at: end)
            if isWordUTF16(c) {
                end += 1
            } else {
                break
            }
        }
        if end > utf16Column {
            return ns.substring(with: NSRange(location: start, length: end - start))
        }
        return prefix
    }

    public static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text.unicodeScalars {
            if isWordScalar(ch) {
                current.unicodeScalars.append(ch)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    public static func isWordCharacter(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
            return ch.unicodeScalars.allSatisfy(isWordScalar)
        }
        return isWordScalar(scalar)
    }

    private static func isWordScalar(_ s: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(s) || s == "_" || s == "-"
    }

    private static func isWordUTF16(_ unit: unichar) -> Bool {
        if unit == 0x5F || unit == 0x2D { return true }
        if unit >= 0x30, unit <= 0x39 { return true }
        if unit >= 0x41, unit <= 0x5A { return true }
        if unit >= 0x61, unit <= 0x7A { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.letters.contains(scalar)
    }
}
