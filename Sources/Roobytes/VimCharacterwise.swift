import Foundation

/// Linewise vs characterwise yank register (vim `""` style, Roobytes-thin).
public enum VimYankKind: Equatable, Sendable {
    case linewise
    case characterwise
}

/// Pure characterwise Visual range math on markdown lines (UTF-16 columns).
public enum VimCharacterwise {
    public static func ordered(
        _ a: MarkdownBridge.MarkdownCaret,
        _ b: MarkdownBridge.MarkdownCaret
    ) -> (MarkdownBridge.MarkdownCaret, MarkdownBridge.MarkdownCaret) {
        if a.line < b.line { return (a, b) }
        if a.line > b.line { return (b, a) }
        if a.column <= b.column { return (a, b) }
        return (b, a)
    }

    /// Inclusive endpoints → markdown text (`\n` between lines, like vim characterwise yank).
    public static func slice(
        from start: MarkdownBridge.MarkdownCaret,
        through end: MarkdownBridge.MarkdownCaret,
        in lines: [String]
    ) -> String {
        guard !lines.isEmpty else { return "" }
        let (lo, hi) = ordered(start, end)
        let startLine = max(0, min(lo.line, lines.count - 1))
        let endLine = max(0, min(hi.line, lines.count - 1))

        if startLine == endLine {
            let ns = lines[startLine] as NSString
            let startCol = max(0, min(lo.column, ns.length))
            let endExclusive = max(startCol, min(hi.column + 1, ns.length))
            return ns.substring(with: NSRange(location: startCol, length: endExclusive - startCol))
        }

        var parts: [String] = []
        let first = lines[startLine] as NSString
        let startCol = max(0, min(lo.column, first.length))
        parts.append(first.substring(from: startCol))

        if endLine > startLine + 1 {
            parts.append(contentsOf: lines[(startLine + 1)..<endLine])
        }

        let last = lines[endLine] as NSString
        let endExclusive = max(0, min(hi.column + 1, last.length))
        parts.append(last.substring(to: endExclusive))
        return parts.joined(separator: "\n")
    }

    /// Delete inclusive characterwise range. Returns updated lines and caret at the deletion start.
    public static func deleting(
        from start: MarkdownBridge.MarkdownCaret,
        through end: MarkdownBridge.MarkdownCaret,
        in lines: [String]
    ) -> (lines: [String], caret: MarkdownBridge.MarkdownCaret) {
        guard !lines.isEmpty else {
            return ([""], MarkdownBridge.MarkdownCaret(line: 0, column: 0))
        }
        let (lo, hi) = ordered(start, end)
        let startLine = max(0, min(lo.line, lines.count - 1))
        let endLine = max(0, min(hi.line, lines.count - 1))
        var next = lines

        if startLine == endLine {
            let ns = next[startLine] as NSString
            let startCol = max(0, min(lo.column, ns.length))
            let endExclusive = max(startCol, min(hi.column + 1, ns.length))
            let prefix = ns.substring(to: startCol)
            let suffix = ns.substring(from: endExclusive)
            next[startLine] = prefix + suffix
            return (next, MarkdownBridge.MarkdownCaret(line: startLine, column: startCol))
        }

        let first = next[startLine] as NSString
        let last = next[endLine] as NSString
        let startCol = max(0, min(lo.column, first.length))
        let endExclusive = max(0, min(hi.column + 1, last.length))
        let merged = first.substring(to: startCol) + last.substring(from: endExclusive)
        next.replaceSubrange(startLine...endLine, with: [merged])
        if next.isEmpty { next = [""] }
        return (next, MarkdownBridge.MarkdownCaret(line: startLine, column: startCol))
    }

    /// Insert characterwise text at `caret`. Returns lines and caret on the first inserted character
    /// (vim leaves the cursor at the start of a characterwise put).
    public static func inserting(
        _ text: String,
        at caret: MarkdownBridge.MarkdownCaret,
        in lines: [String]
    ) -> (lines: [String], caret: MarkdownBridge.MarkdownCaret) {
        var next = lines.isEmpty ? [""] : lines
        let lineIdx = max(0, min(caret.line, next.count - 1))
        let ns = next[lineIdx] as NSString
        let col = max(0, min(caret.column, ns.length))
        let prefix = ns.substring(to: col)
        let suffix = ns.substring(from: col)
        let pieces = text.components(separatedBy: "\n")

        if pieces.count == 1 {
            next[lineIdx] = prefix + pieces[0] + suffix
            return (next, MarkdownBridge.MarkdownCaret(line: lineIdx, column: col))
        }

        next[lineIdx] = prefix + pieces[0]
        let middle = Array(pieces[1..<(pieces.count - 1)])
        if !middle.isEmpty {
            next.insert(contentsOf: middle, at: lineIdx + 1)
        }
        let lastLineIdx = lineIdx + pieces.count - 1
        next.insert(pieces[pieces.count - 1] + suffix, at: lastLineIdx)
        return (next, MarkdownBridge.MarkdownCaret(line: lineIdx, column: col))
    }

    /// Line indices fully removed by a multi-line characterwise delete (`startLine + 1 ..< endLine + 1`).
    public static func deletedLineRange(
        from start: MarkdownBridge.MarkdownCaret,
        through end: MarkdownBridge.MarkdownCaret
    ) -> Range<Int>? {
        let (lo, hi) = ordered(start, end)
        guard hi.line > lo.line else { return nil }
        return (lo.line + 1)..<(hi.line + 1)
    }
}
