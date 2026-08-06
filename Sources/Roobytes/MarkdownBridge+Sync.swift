import Foundation

// MARK: - Live Preview sync recovery

extension MarkdownBridge {
    /// An empty **last** markdown line owns no characters in the view: the separator newline is
    /// tagged with the *previous* visible line, so the final paragraph is character-less and
    /// carries no `mdSourceLine`. True when `caret` sits in that paragraph.
    ///
    /// AppKit draws this as `extraLineFragment` (no glyphs, no gutter number) — Normal-mode
    /// caret must not rest there (see `caretLocationClampedOffTrailingEmpty`).
    public static func caretInTrailingEmptyParagraph(
        caretLocation caret: Int,
        in attributed: NSAttributedString
    ) -> Bool {
        let ns = attributed.string as NSString
        guard ns.length > 0, caret >= ns.length else { return false }
        return ns.character(at: ns.length - 1) == 10 // '\n'
    }

    /// When `caret` is in the character-less trailing empty paragraph, return the first
    /// non-blank column of the previous (last real) paragraph; otherwise `caret` unchanged.
    public static func caretLocationClampedOffTrailingEmpty(
        caretLocation caret: Int,
        in attributed: NSAttributedString
    ) -> Int {
        guard caretInTrailingEmptyParagraph(caretLocation: caret, in: attributed) else {
            return caret
        }
        let ns = attributed.string as NSString
        guard ns.length > 0 else { return 0 }
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(
            &start,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: ns.length - 1, length: 0)
        )
        let para = ns.substring(with: NSRange(location: start, length: max(0, contentsEnd - start)))
        let col = contentStartColumn(in: para)
        return start + min(col, max(0, contentsEnd - start))
    }

    /// Last markdown line `G` / document-end should land on. Skips a trailing `""` that has no
    /// view paragraph (POSIX final newline / character-less empty last line).
    public static func lastNavigableMarkdownLineIndex(
        in lines: [String],
        attributed: NSAttributedString
    ) -> Int {
        guard !lines.isEmpty else { return 0 }
        var idx = lines.count - 1
        while idx > 0,
              lines[idx].isEmpty,
              visibleParagraphStart(forSourceLine: idx, in: attributed) == nil
        {
            idx -= 1
        }
        return idx
    }

    /// `mdSourceLine` of the paragraph holding `caret`, or `nil` when it cannot be resolved.
    /// Never probes backwards out of the trailing empty paragraph: that newline belongs to the
    /// previous line, and reading it made sync mistake an emptied last line for a backspace join
    /// (the last line was then deleted and merged into the one above).
    public static func sourceLine(
        atCaretLocation caret: Int,
        in attributed: NSAttributedString
    ) -> Int? {
        let ns = attributed.string as NSString
        guard ns.length > 0 else { return nil }
        if caretInTrailingEmptyParagraph(caretLocation: caret, in: attributed) { return nil }

        let probe = max(0, min(caret, ns.length - 1))
        var paraStart = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(
            &paraStart,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: probe, length: 0)
        )
        guard paraStart < ns.length else { return nil }
        return attributed.attribute(.mdSourceLine, at: paraStart, effectiveRange: nil) as? Int
    }

    /// Whether two source-line tags currently resolve to the same visible paragraph.
    /// AppKit commonly preserves both tags when deleting the newline between lines.
    public static func sourceLinesShareParagraph(
        _ first: Int,
        _ second: Int,
        in attributed: NSAttributedString,
        sourceLineParagraphIndex: SourceLineParagraphIndex? = nil
    ) -> Bool {
        if let sourceLineParagraphIndex,
           let firstStart = sourceLineParagraphIndex.startsBySourceLine[first],
           let secondStart = sourceLineParagraphIndex.startsBySourceLine[second]
        {
            return firstStart == secondStart
        }

        let full = NSRange(location: 0, length: attributed.length)
        guard full.length > 0 else { return false }

        func paragraphStart(for sourceLine: Int) -> Int? {
            var taggedLocation: Int?
            attributed.enumerateAttribute(.mdSourceLine, in: full, options: []) { value, range, stop in
                if let value = value as? Int, value == sourceLine {
                    taggedLocation = range.location
                    stop.pointee = true
                }
            }
            guard let taggedLocation else { return nil }
            var paragraphStart = 0
            var end = 0
            var contentsEnd = 0
            (attributed.string as NSString).getParagraphStart(
                &paragraphStart,
                end: &end,
                contentsEnd: &contentsEnd,
                for: NSRange(location: taggedLocation, length: 0)
            )
            return paragraphStart
        }

        guard let firstStart = paragraphStart(for: first),
              let secondStart = paragraphStart(for: second)
        else { return false }
        return firstStart == secondStart
    }

    /// When the user deletes the newline after the active line, NSTextView joins
    /// paragraphs in the view and sync writes the merged text into `activeLine` —
    /// but the next markdown line is left behind, resurfacing as a plain duplicate
    /// on the next restyle. Returns that absorbed neighbor index to remove.
    public static func lineIndexAbsorbedAfterJoin(
        activeLine: Int,
        activeViewText: String,
        markdownLines: [String],
        attributed: NSAttributedString,
        hiddenByFold: Set<Int>
    ) -> Int? {
        let next = activeLine + 1
        guard next < markdownLines.count else { return nil }
        if hiddenByFold.contains(next) { return nil }

        let activeStart = visibleParagraphStart(forSourceLine: activeLine, in: attributed)
        let nextStart = visibleParagraphStart(forSourceLine: next, in: attributed)

        // A trailing empty line is always character-less in the view, so a missing tag there is
        // normal — not evidence of a join. It is absorbed only once the final newline is gone,
        // otherwise every sync on the line above silently deleted the document's last line.
        if nextStart == nil,
           next == markdownLines.count - 1,
           markdownLines[next].trimmingCharacters(in: .whitespaces).isEmpty
        {
            let ns = attributed.string as NSString
            let endsWithNewline = ns.length > 0 && ns.character(at: ns.length - 1) == 10 // '\n'
            return endsWithNewline ? nil : next
        }

        let joined =
            sourceLinesShareParagraph(activeLine, next, in: attributed)
            // The absorbed line may lose its source tag entirely during the join.
            || (activeStart != nil && nextStart == nil)
        guard joined else { return nil }

        let neighbor = markdownLines[next]
        let trimmed = neighbor.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return next
        }

        let body = yankableContent(of: neighbor)
        if body.isEmpty {
            // Marker-only line (`    + [ ] `, `+ `) absorbed by join.
            return next
        }
        if activeViewText.hasSuffix(body) || activeViewText.contains(body) {
            return next
        }
        return nil
    }

    /// Rebuild markdown after backspace at column 0 joins the active line into the previous one.
    /// Prefer the joined view text when it is still raw; otherwise append the absorbed body
    /// onto `targetLine` (view may show a decorated `•` bullet from the previous line).
    public static func markdownAfterBackspaceJoin(
        targetLine: String,
        absorbedLine: String,
        joinedViewText: String?
    ) -> String {
        if let view = joinedViewText, !view.isEmpty {
            if !looksLikeDecoratedPreview(view) {
                return view
            }
            if let raw = rawMarkdown(fromDecoratedBulletView: view, templateLine: targetLine) {
                return raw
            }
        }
        let body = yankableContent(of: absorbedLine)
        if body.isEmpty { return targetLine }
        if targetLine.hasSuffix(" ") || body.hasPrefix(" ") {
            return targetLine + body
        }
        // Former separate list item — keep a word break after the join.
        return targetLine + " " + body
    }

    /// Resolve the plain text Insert sync should write for `activeLine`, or `nil` to skip.
    ///
    /// Prefer a non-empty visible paragraph tagged with that source line. When the view shows
    /// no characters for the active line, return `""` so clearing the line persists — skipping
    /// left stale markdown that Esc restyled back into the view (deleted `a` reappearing).
    public static func insertSyncViewLine(
        activeLine: Int,
        visibleParagraph: String?,
        caretParagraphText: String,
        caretSourceLine: Int?
    ) -> String? {
        if let visible = visibleParagraph, !visible.isEmpty {
            return visible
        }
        if let caretSourceLine, caretSourceLine != activeLine {
            return nil
        }
        if !caretParagraphText.isEmpty {
            return caretParagraphText
        }
        // Empty active line (deleted all glyphs, or fresh empty). Persist the clear.
        return ""
    }

    /// True when a view line still has Live Preview widgets (not editable source).
    public static func looksLikeDecoratedPreview(_ line: String) -> Bool {
        if line.contains("\u{FFFC}") { return true }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("☐") || trimmed.hasPrefix("☑") || trimmed.hasPrefix("☒")
            || trimmed.hasPrefix("□") || trimmed.hasPrefix("▣")
        {
            return true
        }
        if trimmed.hasPrefix("•") { return true }
        if trimmed.hasPrefix("─") { return true }
        return false
    }

    /// `• body` → `+ body` using indent from `templateLine` (or the view’s own indent).
    public static func rawMarkdown(fromDecoratedBulletView view: String, templateLine: String) -> String? {
        let trimmed = view.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("•") else { return nil }
        let body: String
        if trimmed.hasPrefix("• ") {
            body = String(trimmed.dropFirst(2))
        } else {
            body = String(trimmed.dropFirst(1))
        }
        let viewIndent = String(view.prefix(while: { $0 == " " || $0 == "\t" }))
        let (templateIndent, _) = splitIndent(templateLine)
        let indent = viewIndent.isEmpty ? templateIndent : viewIndent
        return indent + "+ " + body
    }
}
