import AppKit

// MARK: - Caret mapping (markdown line/column ↔ attributed location)

extension MarkdownBridge {
    public struct SourceLineParagraphIndex: Equatable {
        var startsBySourceLine: [Int: Int]

        public init(startsBySourceLine: [Int: Int]) {
            self.startsBySourceLine = startsBySourceLine
        }
    }

    public struct MarkdownCaret: Equatable {
        public var line: Int
        public var column: Int

        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
    }

    /// Map attributed caret → markdown (line, column). Prefer 1:1 when on `activeSourceLine`.
    public static func markdownCaret(
        attributedLocation: Int,
        attributed: NSAttributedString,
        markdown: String,
        activeSourceLine: Int?,
        markdownLines: [String]? = nil
    ) -> MarkdownCaret {
        let attrNS = attributed.string as NSString
        if attrNS.length == 0 { return MarkdownCaret(line: 0, column: 0) }
        let loc = max(0, min(attributedLocation, attrNS.length))
        let probe = min(loc, max(0, attrNS.length - 1))
        var paraStart = 0
        var paraEnd = 0
        var contentsEnd = 0
        attrNS.getParagraphStart(&paraStart, end: &paraEnd, contentsEnd: &contentsEnd, for: NSRange(location: probe, length: 0))

        let computedLine = paraStart == 0
            ? 0
            : attrNS.substring(to: paraStart).components(separatedBy: "\n").count - 1
        let sourceLine = (attributed.attribute(.mdSourceLine, at: probe, effectiveRange: nil) as? Int) ?? computedLine
        let visibleCol = max(0, loc - paraStart)
        let mdLines = markdownLines ?? markdown.components(separatedBy: "\n")
        let mdLine = sourceLine < mdLines.count ? mdLines[sourceLine] : ""
        let visibleRaw = attrNS.substring(with: NSRange(location: paraStart, length: max(0, contentsEnd - paraStart)))
        let visible = stripFoldCue(visibleRaw)
        let colInVisible = min(visibleCol, (visible as NSString).length)

        if sourceLine == activeSourceLine || visible == mdLine {
            return MarkdownCaret(line: sourceLine, column: min(colInVisible, (mdLine as NSString).length))
        }
        let col = mapVisibleOffsetToMarkdownColumn(visible: visible, visibleOffset: colInVisible, markdownLine: mdLine)
        return MarkdownCaret(line: sourceLine, column: col)
    }

    /// Map markdown (line, column) → attributed UTF-16 location.
    public static func attributedLocation(
        for caret: MarkdownCaret,
        attributed: NSAttributedString,
        markdown: String,
        activeSourceLine: Int?,
        markdownLines: [String]? = nil,
        sourceLineParagraphIndex: SourceLineParagraphIndex? = nil
    ) -> Int {
        let attrNS = attributed.string as NSString
        if attrNS.length == 0 { return 0 }
        let mdLines = markdownLines ?? markdown.components(separatedBy: "\n")

        var paraStart = findParagraphStart(
            forSourceLine: caret.line,
            in: attributed,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        if paraStart == nil {
            for line in stride(from: caret.line, through: 0, by: -1) {
                if let s = findParagraphStart(
                    forSourceLine: line,
                    in: attributed,
                    sourceLineParagraphIndex: sourceLineParagraphIndex
                ) {
                    paraStart = s
                    break
                }
            }
        }
        guard let start = paraStart else { return 0 }

        var end = 0
        var contentsEnd = 0
        var resolvedStart = start
        if resolvedStart < attrNS.length {
            attrNS.getParagraphStart(&resolvedStart, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: resolvedStart, length: 0))
        } else {
            return attrNS.length
        }

        let visibleRaw = attrNS.substring(with: NSRange(location: resolvedStart, length: max(0, contentsEnd - resolvedStart)))
        let visible = stripFoldCue(visibleRaw)
        let mdLine = caret.line < mdLines.count ? mdLines[caret.line] : ""
        let sourceLine = (attributed.attribute(.mdSourceLine, at: min(resolvedStart, max(0, attrNS.length - 1)), effectiveRange: nil) as? Int) ?? caret.line
        let visibleCol: Int
        if sourceLine == activeSourceLine || visible == mdLine {
            visibleCol = min(caret.column, (visible as NSString).length)
        } else {
            visibleCol = mapMarkdownColumnToVisibleOffset(markdownLine: mdLine, column: caret.column, visible: visible)
        }
        return min(resolvedStart + visibleCol, attrNS.length)
    }

    public static func buildSourceLineParagraphIndex(
        in attributed: NSAttributedString
    ) -> SourceLineParagraphIndex {
        let attrNS = attributed.string as NSString
        guard attrNS.length > 0 else {
            return SourceLineParagraphIndex(startsBySourceLine: [:])
        }
        var startsBySourceLine: [Int: Int] = [:]
        var loc = 0
        while loc < attrNS.length {
            var paraStart = 0
            var end = 0
            var contentsEnd = 0
            attrNS.getParagraphStart(&paraStart, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
            if paraStart < attrNS.length,
               let src = attributed.attribute(.mdSourceLine, at: paraStart, effectiveRange: nil) as? Int,
               startsBySourceLine[src] == nil
            {
                startsBySourceLine[src] = paraStart
            }
            if end <= loc { break }
            loc = end
        }
        return SourceLineParagraphIndex(startsBySourceLine: startsBySourceLine)
    }

    static func findParagraphStart(
        forSourceLine line: Int,
        in attributed: NSAttributedString,
        sourceLineParagraphIndex: SourceLineParagraphIndex? = nil
    ) -> Int? {
        if let start = sourceLineParagraphIndex?.startsBySourceLine[line] {
            return start
        }
        let attrNS = attributed.string as NSString
        guard attrNS.length > 0 else { return nil }
        var loc = 0
        while loc < attrNS.length {
            var paraStart = 0
            var end = 0
            var contentsEnd = 0
            attrNS.getParagraphStart(&paraStart, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
            let contentLen = max(0, contentsEnd - paraStart)
            if contentLen > 0 {
                if let src = attributed.attribute(.mdSourceLine, at: paraStart, effectiveRange: nil) as? Int, src == line {
                    return paraStart
                }
            } else if paraStart < attrNS.length {
                if let src = attributed.attribute(.mdSourceLine, at: paraStart, effectiveRange: nil) as? Int, src == line {
                    return paraStart
                }
            }
            if end <= loc { break }
            loc = end
        }
        return nil
    }

    /// View paragraph text for a markdown source line (`mdSourceLine`), or `nil` if hidden/absent.
    public static func visibleParagraphText(forSourceLine line: Int, in attributed: NSAttributedString) -> String? {
        visibleParagraphText(
            forSourceLine: line,
            in: attributed,
            sourceLineParagraphIndex: nil
        )
    }

    public static func visibleParagraphText(
        forSourceLine line: Int,
        in attributed: NSAttributedString,
        sourceLineParagraphIndex: SourceLineParagraphIndex?
    ) -> String? {
        guard let start = findParagraphStart(
            forSourceLine: line,
            in: attributed,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        ) else { return nil }
        let ns = attributed.string as NSString
        var paraStart = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(&paraStart, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
        let raw = ns.substring(with: NSRange(location: paraStart, length: max(0, contentsEnd - paraStart)))
        return stripFoldCue(raw)
    }

    /// UTF-16 start of the view paragraph for `line`, or `nil` if that source line is not in the view.
    public static func visibleParagraphStart(forSourceLine line: Int, in attributed: NSAttributedString) -> Int? {
        visibleParagraphStart(
            forSourceLine: line,
            in: attributed,
            sourceLineParagraphIndex: nil
        )
    }

    public static func visibleParagraphStart(
        forSourceLine line: Int,
        in attributed: NSAttributedString,
        sourceLineParagraphIndex: SourceLineParagraphIndex?
    ) -> Int? {
        findParagraphStart(
            forSourceLine: line,
            in: attributed,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
    }

    // MARK: - Block-level column mapping

    private static func mapVisibleOffsetToMarkdownColumn(visible: String, visibleOffset: Int, markdownLine: String) -> Int {
        let md = markdownLine as NSString
        let vis = visible as NSString
        let off = max(0, min(visibleOffset, vis.length))
        if vis.length == 0 { return 0 }

        let (_, rest) = splitIndent(markdownLine)
        let indentLen = md.length - (rest as NSString).length
        let restNS = rest as NSString

        if visible.hasPrefix("\u{FFFC}") || visible.hasPrefix("☐") || visible.hasPrefix("☑") || visible.hasPrefix("☒") || visible.hasPrefix("▣") {
            if off == 0 {
                return indentLen
            }
            let bodyOff = max(0, off - 1)
            if let bracket = rest.firstIndex(of: "]") {
                var markerEnd = rest.distance(from: rest.startIndex, to: bracket) + 1
                let after = rest.index(after: bracket)
                if after < rest.endIndex, rest[after] == " " { markerEnd += 1 }
                let mdBody = restNS.substring(from: markerEnd)
                let bodyCol = markdownColumn(forVisibleOffset: bodyOff, inInlineMarkdown: mdBody)
                return min(indentLen + markerEnd + bodyCol, md.length)
            }
            let bodyCol = markdownColumn(forVisibleOffset: bodyOff, inInlineMarkdown: rest)
            return min(indentLen + bodyCol, md.length)
        }
        if visible.hasPrefix("•") {
            let pad = bulletMarkerUTF16Length
            let stripped = max(0, off - pad)
            let mdBody = restNS.length >= 2 ? restNS.substring(from: 2) : ""
            let bodyCol = markdownColumn(forVisibleOffset: stripped, inInlineMarkdown: mdBody)
            return min(indentLen + 2 + bodyCol, md.length)
        }
        for prefix in ["#### ", "### ", "## ", "# ", "> ", ">"] where rest.hasPrefix(prefix) {
            let prefixLen = (prefix as NSString).length
            let mdBody = restNS.substring(from: prefixLen)
            let bodyCol = markdownColumn(forVisibleOffset: off, inInlineMarkdown: mdBody)
            return min(indentLen + prefixLen + bodyCol, md.length)
        }
        let bodyCol = markdownColumn(forVisibleOffset: off, inInlineMarkdown: rest)
        return min(indentLen + bodyCol, md.length)
    }

    private static func mapMarkdownColumnToVisibleOffset(markdownLine: String, column: Int, visible: String) -> Int {
        let mdCol = max(0, min(column, (markdownLine as NSString).length))
        let vis = visible as NSString
        let (_, rest) = splitIndent(markdownLine)
        let indentLen = (markdownLine as NSString).length - (rest as NSString).length
        let restNS = rest as NSString

        if visible.hasPrefix("\u{FFFC}") || visible.hasPrefix("☐") || visible.hasPrefix("☑") || visible.hasPrefix("☒") || visible.hasPrefix("▣") {
            if let bracket = rest.firstIndex(of: "]") {
                var markerEnd = rest.distance(from: rest.startIndex, to: bracket) + 1
                let after = rest.index(after: bracket)
                if after < rest.endIndex, rest[after] == " " { markerEnd += 1 }
                if mdCol <= indentLen + markerEnd {
                    return mdCol <= indentLen ? 0 : min(1, vis.length)
                }
                let bodyMd = max(0, mdCol - indentLen - markerEnd)
                let mdBody = restNS.substring(from: markerEnd)
                let bodyVis = visibleOffset(forMarkdownColumn: bodyMd, inInlineMarkdown: mdBody)
                return min(1 + bodyVis, vis.length)
            }
            return min(max(mdCol > indentLen ? 1 : 0, 0), vis.length)
        }
        if visible.hasPrefix("•") {
            if mdCol <= indentLen + 2 {
                return min(max(mdCol > indentLen ? 1 : 0, 0), vis.length)
            }
            let bodyMd = max(0, mdCol - indentLen - 2)
            let mdBody = restNS.length >= 2 ? restNS.substring(from: 2) : ""
            let bodyVis = visibleOffset(forMarkdownColumn: bodyMd, inInlineMarkdown: mdBody)
            return min(bulletMarkerUTF16Length + bodyVis, vis.length)
        }
        for prefix in ["#### ", "### ", "## ", "# ", "> ", ">"] where rest.hasPrefix(prefix) {
            let prefixLen = (prefix as NSString).length
            if mdCol <= indentLen + prefixLen {
                return 0
            }
            let bodyMd = max(0, mdCol - indentLen - prefixLen)
            let mdBody = restNS.substring(from: prefixLen)
            return min(visibleOffset(forMarkdownColumn: bodyMd, inInlineMarkdown: mdBody), vis.length)
        }
        if mdCol <= indentLen {
            return 0
        }
        let bodyMd = max(0, mdCol - indentLen)
        return min(visibleOffset(forMarkdownColumn: bodyMd, inInlineMarkdown: rest), vis.length)
    }

    // MARK: - Inline marker-aware column mapping

    /// Decorated visible text strips `` ` `` / `**` / `~~` / `*…*` / `_…_` markers — map offsets accordingly.
    private static func markdownColumn(forVisibleOffset visibleOffset: Int, inInlineMarkdown markdown: String) -> Int {
        let md = markdown as NSString
        let target = max(0, visibleOffset)
        var mi = 0
        var vi = 0
        while mi < md.length {
            if vi >= target { return mi }
            if let span = inlineSpan(at: mi, in: md) {
                if vi + span.visAdvance >= target {
                    let into = target - vi
                    return mi + span.openLen + into
                }
                vi += span.visAdvance
                mi += span.mdAdvance
                continue
            }
            vi += 1
            mi += 1
        }
        return md.length
    }

    private static func visibleOffset(forMarkdownColumn mdColumn: Int, inInlineMarkdown markdown: String) -> Int {
        let md = markdown as NSString
        let target = max(0, min(mdColumn, md.length))
        var mi = 0
        var vi = 0
        while mi < md.length {
            if mi >= target { return vi }
            if let span = inlineSpan(at: mi, in: md) {
                let contentStart = mi + span.openLen
                let contentEnd = mi + span.mdAdvance - span.closeLen
                if target <= contentStart {
                    return vi
                }
                if target <= contentEnd {
                    return vi + (target - contentStart)
                }
                if target < mi + span.mdAdvance {
                    return vi + span.visAdvance
                }
                vi += span.visAdvance
                mi += span.mdAdvance
                continue
            }
            vi += 1
            mi += 1
        }
        return vi
    }

    private struct InlineSpan {
        var mdAdvance: Int
        var visAdvance: Int
        var openLen: Int
        var closeLen: Int
    }

    /// Match a stripped inline span at `mi` (same rules as `inlineAttributed`).
    private static func inlineSpan(at mi: Int, in md: NSString) -> InlineSpan? {
        // **bold**
        if mi + 1 < md.length,
           md.character(at: mi) == 42, md.character(at: mi + 1) == 42
        {
            var j = mi + 2
            while j + 1 < md.length {
                if md.character(at: j) == 42, md.character(at: j + 1) == 42 {
                    let content = j - (mi + 2)
                    return InlineSpan(mdAdvance: j + 2 - mi, visAdvance: content, openLen: 2, closeLen: 2)
                }
                j += 1
            }
        }

        // ~~strike~~
        if mi + 1 < md.length,
           md.character(at: mi) == 126, md.character(at: mi + 1) == 126
        {
            var j = mi + 2
            while j + 1 < md.length {
                if md.character(at: j) == 126, md.character(at: j + 1) == 126 {
                    let content = j - (mi + 2)
                    return InlineSpan(mdAdvance: j + 2 - mi, visAdvance: content, openLen: 2, closeLen: 2)
                }
                j += 1
            }
        }

        // `code`
        if md.character(at: mi) == 96 {
            var j = mi + 1
            while j < md.length {
                let c = md.character(at: j)
                if c == 10 { break }
                if c == 96 {
                    let content = j - (mi + 1)
                    if content > 0, content <= 120 {
                        return InlineSpan(mdAdvance: j + 1 - mi, visAdvance: content, openLen: 1, closeLen: 1)
                    }
                    break
                }
                j += 1
            }
        }

        // *italic* (not **)
        if md.character(at: mi) == 42,
           !(mi + 1 < md.length && md.character(at: mi + 1) == 42)
        {
            var j = mi + 1
            while j < md.length {
                let c = md.character(at: j)
                if c == 10 { break }
                if c == 42, !(j + 1 < md.length && md.character(at: j + 1) == 42) {
                    let content = j - (mi + 1)
                    if content > 0 {
                        return InlineSpan(mdAdvance: j + 1 - mi, visAdvance: content, openLen: 1, closeLen: 1)
                    }
                    break
                }
                j += 1
            }
        }

        // _italic_ (not __); skip word-interior `_` so snake_case stays literal.
        if md.character(at: mi) == 95,
           !(mi + 1 < md.length && md.character(at: mi + 1) == 95),
           !isWordUTF16(before: mi, in: md)
        {
            var j = mi + 1
            while j < md.length {
                let c = md.character(at: j)
                if c == 10 { break }
                if c == 95 {
                    if j + 1 < md.length, md.character(at: j + 1) == 95 {
                        j += 2
                        continue
                    }
                    if isWordUTF16(after: j, in: md) {
                        j += 1
                        continue
                    }
                    let content = j - (mi + 1)
                    // Reject spans with interior `_` (same as renderer).
                    var hasInteriorUnderscore = false
                    if content > 0 {
                        for k in (mi + 1)..<j where md.character(at: k) == 95 {
                            hasInteriorUnderscore = true
                            break
                        }
                    }
                    if content > 0, !hasInteriorUnderscore {
                        return InlineSpan(mdAdvance: j + 1 - mi, visAdvance: content, openLen: 1, closeLen: 1)
                    }
                    break
                }
                j += 1
            }
        }

        return nil
    }

    private static func isWordUTF16(before mi: Int, in md: NSString) -> Bool {
        guard mi > 0 else { return false }
        return isWordUTF16Scalar(md.character(at: mi - 1))
    }

    private static func isWordUTF16(after mi: Int, in md: NSString) -> Bool {
        let next = mi + 1
        guard next < md.length else { return false }
        return isWordUTF16Scalar(md.character(at: next))
    }

    private static func isWordUTF16Scalar(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
    }

    // MARK: - Task caret helpers

    /// Whether the caret sits in the task marker (attachment / `+ [ ]`).
    static func caretIsInTaskSlug(visibleParagraph: String, caretOffset: Int) -> Bool {
        guard caretOffset >= 0 else { return false }
        let line = visibleParagraph
        if line.hasPrefix("\u{FFFC}") {
            return caretOffset == 0
        }
        if line.hasPrefix("☑") || line.hasPrefix("☐") || line.hasPrefix("☒") || line.hasPrefix("▣") {
            return caretOffset == 0
        }
        if line.hasPrefix("+ [") || line.hasPrefix("- [") || line.hasPrefix("* [") {
            if let bracket = line.firstIndex(of: "]") {
                let end = line.distance(from: line.startIndex, to: bracket) + 1
                return caretOffset < end
            }
        }
        return false
    }

    /// Snap caret out of the whitespace gap between slug and body (avoids "left jump" stops).
    static func snapTaskCaretOffset(in paragraph: String, offset: Int) -> Int? {
        guard let bodyStart = taskBodyStartOffset(in: paragraph), offset < bodyStart else { return nil }
        guard let slugEnd = taskSlugEndOffset(in: paragraph), offset > slugEnd else { return nil }
        return taskSlugInteriorOffset(in: paragraph)
    }

    /// First character index of task body text (after marker / slug).
    static func taskBodyStartOffset(in paragraph: String) -> Int? {
        if paragraph.hasPrefix("\u{FFFC}") {
            return paragraph.count > 1 ? 1 : nil
        }
        if paragraph.hasPrefix("☑") || paragraph.hasPrefix("☐") || paragraph.hasPrefix("☒") || paragraph.hasPrefix("▣") {
            var i = 1
            while i < paragraph.count {
                let idx = paragraph.index(paragraph.startIndex, offsetBy: i)
                if paragraph[idx] != " " { return i }
                i += 1
            }
            return nil
        }
        if paragraph.hasPrefix("+ [") || paragraph.hasPrefix("- [") || paragraph.hasPrefix("* [") {
            guard let bracket = paragraph.firstIndex(of: "]") else { return nil }
            var i = paragraph.distance(from: paragraph.startIndex, to: bracket) + 1
            while i < paragraph.count {
                let idx = paragraph.index(paragraph.startIndex, offsetBy: i)
                if paragraph[idx] != " " { return i }
                i += 1
            }
            return nil
        }
        return nil
    }

    /// Index immediately after the `]` in an expanded slug line.
    private static func taskSlugEndOffset(in paragraph: String) -> Int? {
        guard paragraph.hasPrefix("+ [") || paragraph.hasPrefix("- [") || paragraph.hasPrefix("* [") else { return nil }
        guard let bracket = paragraph.firstIndex(of: "]") else { return nil }
        return paragraph.distance(from: paragraph.startIndex, to: bracket) + 1
    }

    /// Preferred caret when entering slug edit from the task body (inside `[ ]`).
    static func taskSlugInteriorOffset(in paragraph: String) -> Int {
        if let open = paragraph.firstIndex(of: "[") {
            let afterOpen = paragraph.index(after: open)
            if afterOpen < paragraph.endIndex, paragraph[afterOpen] == " " {
                return paragraph.distance(from: paragraph.startIndex, to: afterOpen)
            }
            return paragraph.distance(from: paragraph.startIndex, to: afterOpen)
        }
        return 0
    }

    /// Caret after expanding slug or collapsing back to checkbox + body.
    static func taskCaretAfterSlugToggle(
        paragraph: String,
        expanding: Bool
    ) -> Int {
        if expanding {
            return taskSlugInteriorOffset(in: paragraph)
        }
        return taskBodyStartOffset(in: paragraph) ?? 1
    }
}
